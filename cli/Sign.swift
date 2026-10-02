import Foundation

// 代码签名。核心结论（实测得出，改动前请先复现）：
//
// 我们只改 Contents/Resources/app.asar 与 Contents/Info.plist，两者都由顶层
// 签名封存，嵌套的 Helper / Framework 签名一个都没被破坏——所以**不用 --deep**。
// 早期版本用了，把每个 Helper 也重签成不带 entitlement 的 ad-hoc，Claude Helper
// 因此丢掉 com.apple.security.virtualization，Cowork 与虚拟机功能失效。
//
// 也不加 --options runtime：顶层是 ad-hoc（无 team），而各 Framework 仍由
// Anthropic 签名；开启 hardened runtime 会一并打开库校验，团队不匹配将导致
// Electron Framework 加载失败。

/// 与开发者身份绑定的 entitlement。ad-hoc 签名既没有 team 也没有描述文件，
/// 这些项留着不会生效，反而可能让 AMFI 连整份 entitlement 一起拒掉。
let ENT_DROP: Set<String> = ["com.apple.application-identifier", "keychain-access-groups"]
let ENT_DROP_PREFIX = "com.apple.developer."

enum Sign {
    /// 确认 codesign 可用后再动 app：回滚同样要重签，等到那时才发现不可用，
    /// 会留下一个签不上名、起不来的 Claude。
    ///
    /// codesign 本身是系统自带的真二进制，并不随 Xcode 命令行工具安装。
    static func codesignAvailable() -> (Bool, String) {
        let exe = "/usr/bin/codesign"
        guard FileManager.default.isExecutableFile(atPath: exe) else {
            return (false, "系统里找不到 codesign")
        }
        // codesign 没有 --version；不带参数跑一下，真家伙会打印用法
        let r = run([exe])
        if r.out.contains("Usage: codesign") { return (true, exe) }
        let first = r.out.split(separator: "\n").first.map(String.init) ?? ""
        return (false, first.isEmpty ? "codesign 退出码 \(r.code)" : first)
    }

    static func valid(_ t: AppTarget) -> Bool {
        run(["/usr/bin/codesign", "-v", t.app.path]).code == 0
    }

    static func isAdhoc(_ t: AppTarget) -> Bool {
        run(["/usr/bin/codesign", "-dv", t.app.path]).out.contains("adhoc")
    }

    static func teamIdentifier(_ t: AppTarget) -> String? {
        for line in run(["/usr/bin/codesign", "-dv", t.app.path]).out.split(separator: "\n") {
            guard line.hasPrefix("TeamIdentifier=") else { continue }
            let v = String(line.dropFirst("TeamIdentifier=".count)).trimmingCharacters(in: .whitespaces)
            return (v.isEmpty || v == "not set") ? nil : v
        }
        return nil
    }

    /// 读某个 .app 的 entitlements；读不到、为空、解析失败一律返回 nil
    static func readEntitlements(_ appPath: URL) -> [String: Any]? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["-d", "--entitlements", "-", "--xml", appPath.path]
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe; p.standardError = errPipe
        do { try p.run() } catch { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0, !data.isEmpty,
              let o = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let d = o as? [String: Any], !d.isEmpty else { return nil }
        return d
    }

    static func entitlementsPath(_ t: AppTarget, _ version: String) -> URL {
        P.dataDir.appendingPathComponent("entitlements-\(version)\(t.slug).plist")
    }

    /// 把原版 app 的 entitlements 缓存下来，供之后每次重签名带回去。
    /// 必须赶在第一次改签名之前取——ad-hoc 一旦覆盖上去，原件就没了。
    /// 已经被旧版签成 ad-hoc 的机器，退而从整包备份里取。
    @discardableResult
    static func captureEntitlements(_ t: AppTarget) -> URL? {
        guard let version = t.version else { return nil }
        let dst = entitlementsPath(t, version)
        if FileManager.default.fileExists(atPath: dst.path) { return dst }
        let src: URL? = isAdhoc(t) ? Backup.pristineForCurrent(t) : t.app
        guard let src, let ent = readEntitlements(src) else { return nil }
        var kept: [String: Any] = [:]
        var dropped: [String] = []
        for (k, v) in ent {
            if ENT_DROP.contains(k) || k.hasPrefix(ENT_DROP_PREFIX) { dropped.append(k) }
            else { kept[k] = v }
        }
        try? FileManager.default.createDirectory(at: P.dataDir, withIntermediateDirectories: true)
        guard let d = try? PropertyListSerialization.data(
            fromPropertyList: kept, format: .xml, options: 0) else { return nil }
        try? d.write(to: dst)
        ok("已记录原版 entitlements（保留 \(kept.count) 项）：\(dst.lastPathComponent)")
        if !dropped.isEmpty {
            info("剔除与开发者身份绑定、ad-hoc 下无法生效的项：" + dropped.sorted().joined(separator: "、"))
        }
        return dst
    }

    static func entitlementsForResign(_ t: AppTarget) -> URL? {
        guard let version = t.version else { return nil }
        let p = entitlementsPath(t, version)
        return FileManager.default.fileExists(atPath: p.path) ? p : captureEntitlements(t)
    }

    /// 判断嵌套 Helper 的 entitlements 是否被抹掉过（旧版 --deep 的后果）。
    static func nestedStripped(_ t: AppTarget) -> Bool {
        guard FileManager.default.fileExists(atPath: t.helper.path) else { return false }
        return readEntitlements(t.helper) == nil
    }

    /// 只重签顶层 bundle，并带回原版 entitlements。
    ///
    /// **刻意不带 `-r`。** ad-hoc 签名的隐式指定要求是 `cdhash H"..."`，只认这一份
    /// 二进制。Squirrel.Mac 装更新前会拿运行中 app 的指定要求去校验下载来的新版，
    /// 新版 cdhash 必然不同，于是 Claude 的自动更新被彻底挡住，界面上还没有任何
    /// 提示（2026-10-01 在一台机器上实测到 666 次 did not pass validation，用户被
    /// 静默卡在旧版近三周）。
    ///
    /// 看上去只要 `-r` 写回原版那条指定要求就能修好——**实测过，不行**：
    ///   · 更新那半确实修好了：隔离实验台上，不带 -r 得到 did not pass validation，
    ///     带 -r 得到 Update downloaded and ready to install。
    ///   · 但钥匙串那半垮了：钥匙串 ACL 按 app 声明的指定要求评估访问者。声明成
    ///     Anthropic 那条，而我们是 ad-hoc 签名、永远满足不了，于是「始终允许」
    ///     存进去也不生效，**每次启动 Claude 都要重新输登录密码**。
    ///     正式机实测对照：cdhash 要求下重启不再弹；原版要求下重启必弹。
    /// 每次启动输密码比静默卡更新更难受，因此保持现状，改为检测并引导用户
    /// 「还原 → 更新 Claude → 重新应用」。
    static func resign(_ t: AppTarget) throws {
        let ent = entitlementsForResign(t)
        info("重签名顶层 bundle（"
             + (ent != nil ? "保留原版 entitlements" : "未取到原版 entitlements，将不带")
             + "，整包较大需要一会儿；此阶段中断也会触发自动回滚）…")
        var cmd = ["/usr/bin/codesign", "--force", "--sign", "-"]
        if let ent { cmd += ["--entitlements", ent.path] }
        cmd.append(t.app.path)
        let r = run(cmd)
        if r.code != 0 { throw CLIError("codesign 失败：\(r.out)") }
        // 验证失败时把 codesign 自己的说法带出来。只说「验证未通过」的话，
        // 用户和维护者都无从下手——成因可能是磁盘写满、app 在只读卷上、
        // 残留的 Helper 进程占着文件、扩展属性异常等，彼此处理方式完全不同。
        guard valid(t) else {
            let detail = run(["/usr/bin/codesign", "-v", "--verbose=4", t.app.path]).out
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CLIError("codesign -v 验证未通过"
                           + (detail.isEmpty ? "" : "\n    codesign 的说明：\n    "
                              + detail.replacingOccurrences(of: "\n", with: "\n    ")))
        }
        ok("签名验证通过")
    }
}

let APP_MGMT_HINT = """
需要「App 管理」权限才能修改 Claude。
    请打开「系统设置 → 隐私与安全性 → App 管理」，为 Clfont 打开开关，然后重新执行。
    （从终端运行时，需要为「终端」打开该开关。）
"""

/// 探测能否写目标 app —— macOS 的「App 管理」权限（TCC）。
///
/// 探测方式是把 Info.plist 的时间戳原样写回：这是一次真正的修改操作，会经过
/// 同一道检查，但文件内容与元数据都不变，代码签名也不受影响。
func appWritePermitted(_ t: AppTarget) -> (Bool, String) {
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: t.infoPlist.path)
        let mtime = attrs[.modificationDate] as? Date ?? Date()
        try FileManager.default.setAttributes([.modificationDate: mtime],
                                              ofItemAtPath: t.infoPlist.path)
        return (true, "")
    } catch {
        return (false, "\(error)")
    }
}
