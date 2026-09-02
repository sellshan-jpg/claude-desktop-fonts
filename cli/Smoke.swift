import Foundation

/// 按完整路径在 ps 里找目标 app 的进程。
/// 不用 pgrep：实测部分环境下匹配不到 Claude 主进程。
func claudePids(_ t: AppTarget) -> [Int32] {
    let r = run(["ps", "-axo", "pid=,comm="])
    var pids: [Int32] = []
    for line in r.out.split(separator: "\n") {
        let s = line.trimmingCharacters(in: .whitespaces)
        guard let sp = s.firstIndex(of: " ") else { continue }
        let pid = String(s[s.startIndex..<sp])
        let comm = String(s[s.index(after: sp)...]).trimmingCharacters(in: .whitespaces)
        if comm == t.binary.path, let n = Int32(pid) { pids.append(n) }
    }
    return pids
}

func claudeRunning(_ t: AppTarget) -> Bool { !claudePids(t).isEmpty }

func quitClaude(_ t: AppTarget, _ assumeYes: Bool) -> Bool {
    guard claudeRunning(t) else { return true }
    print("  ! Claude 正在运行，操作前必须退出。")
    guard confirm("    是否代为退出 Claude？", assumeYes) else { return false }
    // 只对「本次目标 app」的进程发信号。绝不能用 osascript 按应用名退出：
    // 那会退掉正在运行的那个 Claude（通常是正式版），而不是 --app 指定的副本。
    for pid in claudePids(t) { kill(pid, SIGTERM) }
    for _ in 0..<20 {
        if !claudeRunning(t) { ok("Claude 已退出"); return true }
        Thread.sleep(forTimeInterval: 0.5)
    }
    for pid in claudePids(t) { kill(pid, SIGKILL) }
    Thread.sleep(forTimeInterval: 1)
    if claudeRunning(t) { bad("Claude 仍在运行"); return false }
    ok("Claude 已退出")
    return true
}

/// 启动 app 验证「能活着起来」——事务 commit 的真正前提。
/// 第二轮事故：文件全绿但主进程静默退出（exit 0）。此测试专抓这种。
func smokeTest(_ t: AppTarget, timeout: TimeInterval = 20) -> Bool {
    if Env.flag("CLFONT_SMOKE_FORCE_FAIL") {
        Log.raw("smoke FORCE_FAIL hook -> return False")
        info("测试钩子 CLFONT_SMOKE_FORCE_FAIL：强制判定冒烟失败")
        return false
    }
    for pid in claudePids(t) { kill(pid, SIGTERM) }
    Thread.sleep(forTimeInterval: 1)

    var args = [t.binary.path]
    if let udd = Env.str("CLFONT_SMOKE_USER_DATA_DIR") { args += ["--user-data-dir", udd] }
    info("启动 app，最多观察 \(Int(timeout))s，确认进程存活…")
    Log.raw("smoke launch: " + args.joined(separator: " "))

    let p = Process()
    p.executableURL = URL(fileURLWithPath: args[0])
    p.arguments = Array(args.dropFirst())
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch {
        info("启动失败：\(error)")
        return false
    }

    var alive = false, stable = 0
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        Thread.sleep(forTimeInterval: 1.5)
        let pids = claudePids(t)
        if !p.isRunning && pids.isEmpty {
            info("主进程已退出（exit=\(p.terminationStatus)）且无存活进程 —— 冒烟失败")
            Log.raw("smoke fail: exited ec=\(p.terminationStatus)")
            break
        }
        if !pids.isEmpty {
            stable += 1
            if stable >= 4 { alive = true; break }   // ≈6s 持续存活
        }
    }
    // 无论成败，关闭本次启动的实例，避免残留影响后续回滚或文件操作
    for pid in claudePids(t) { kill(pid, SIGTERM) }
    if p.isRunning { p.terminate() }
    Thread.sleep(forTimeInterval: 2)
    for pid in claudePids(t) { kill(pid, SIGKILL) }
    Thread.sleep(forTimeInterval: 0.5)
    Log.raw("smoke result: alive=\(alive)")
    return alive
}

/// install 前把自身落盘到固定位置，保证事后可自救。失败则拒绝继续。
func ensureSelfInstalled() throws {
    let me = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let fm = FileManager.default
    if fm.fileExists(atPath: P.canon.path),
       P.canon.resolvingSymlinksInPath().path == me.path {
        ok("工具已在固定位置：\(P.canon.path)")
    } else {
        do {
            try fm.createDirectory(at: P.canon.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            _ = try? fm.removeItem(at: P.canon)
            try fm.copyItem(at: me, to: P.canon)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: P.canon.path)
            ok("已将自身安装到 \(P.canon.path)（供事后自救）")
        } catch {
            throw CLIError("无法把工具复制到 \(P.canon.path)（\(error)）。"
                         + "为保证失败时能自救，拒绝继续 install。")
        }
    }
    let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
    let dir = P.canon.deletingLastPathComponent().path
    if !paths.contains(where: { String($0) == dir }) {
        info("提示：\(dir) 不在 PATH 中，自救时请用完整路径 \(P.canon.path)")
    }
}
