import Foundation

// 五个子命令。输出文案必须与 Python 版逐字一致：GUI 靠这些字面量解析状态
// （见 gui/ClfontApp.swift 的 CLIMarker），回归测试也按同一套断言跑两版。

func requireCodesign() {
    let (good, detail) = Sign.codesignAvailable()
    if good { return }
    die("""
        需要 Xcode 命令行工具（codesign）才能给 Claude 重新签名。
            \(detail)
            请先运行：xcode-select --install
            装好后重试。（此刻尚未对 Claude 做任何修改。）
        """)
}

func requireAppWrite(_ t: AppTarget) {
    let (good, detail) = appWritePermitted(t)
    if good { return }
    die("\(APP_MGMT_HINT)\n    （系统返回：\(detail)）\n    此刻尚未对 Claude 做任何修改。")
}

func checkPrevTxn() {
    guard let j = Journal.read() else { return }
    if j["corrupt"] != nil { info("发现损坏的事务日志，忽略"); return }
    bad("发现未完成的事务：\(j["txn"] ?? "?") @ \(j["time"] ?? "?")"
        + "（\(j["status"] ?? "?")），app=\(j["app"] ?? "?")")
    if let steps = j["steps"] as? [[String: Any]] {
        info("事务步骤：" + steps.map { "\($0["step"] ?? "")" }.joined(separator: "; "))
    }
    if let log = j["log"] as? String, !log.isEmpty { info("详细日志：\(log)") }
}

/// 修复旧版 --deep 重签留下的损伤。Helper 的 entitlements 被抹掉后无法就地补回，
/// 唯一的办法是拿打补丁前的整包备份整体还原。
func healNestedSignatures(_ t: AppTarget, _ assumeYes: Bool) throws {
    guard Sign.nestedStripped(t) else { return }
    if let bak = Backup.pristineForCurrent(t),
       Sign.readEntitlements(bak.appendingPathComponent("Contents/Frameworks/Claude Helper.app")) != nil {
        step("修复旧版重签名留下的损伤（Helper 丢失 entitlements，会导致 Cowork、虚拟机等功能不可用）")
        info("这类损伤无法就地修补，需要从整包备份整体还原后再打补丁。")
        try restoreFromBackup(t, assumeYes, src: bak)
        ok("已还原到原版签名，继续打补丁")
    } else {
        bad("检测到 Helper 缺少 entitlements（旧版重签名的后果），Cowork、虚拟机等功能可能不可用。")
        info("没有可用于修复的原版备份。如需彻底修复，"
             + "请到 https://claude.ai/download 重新下载安装 Claude 后再运行本工具。")
    }
}

func restoreFromBackup(_ t: AppTarget, _ assumeYes: Bool, src: URL? = nil) throws {
    let source: URL
    if let src { source = src }
    else {
        guard let first = Backup.list(t).first else {
            throw CLIError("没有 app.asar(.bak)，也没有整包备份。"
                         + "请到 https://claude.ai/download 重新下载安装 Claude。")
        }
        source = first
    }
    print("  将从整包备份还原：\(source.path)")
    print("  这会删除并替换整个 \(t.app.path)")
    guard confirm("  继续？", assumeYes) else { throw CLIError("用户取消") }
    try FileManager.default.removeItem(at: t.app)
    let r = run(["ditto", source.path, t.app.path])
    if r.code != 0 { throw CLIError("ditto 失败：\(r.out)") }
    // 备份里的 plist 哈希应与其 asar 自洽；不自洽则修正（否则 app 起不来）
    if FileManager.default.fileExists(atPath: t.asar.path) {
        let want = try asarHeaderHash(t.asar)
        if plistGetAsarHash(t) != want {
            info("修正备份的 ElectronAsarIntegrity 哈希 → \(want.prefix(12))…")
            try plistSetAsarHash(t, want)
            try Sign.resign(t)
            return
        }
    }
    if Sign.valid(t) { ok("签名验证通过") }
    else { info("备份签名校验未通过，重新 ad-hoc 签名"); try Sign.resign(t) }
}

// ---------------------------------------------------------------- install

func cmdInstall(_ t: AppTarget, _ a: Args) {
    print("clfont install（目标：\(t.app.path)）")
    var cfg = Config.load()
    applyOverrides(&cfg, a)
    let mode = cfg.mode
    if scopeSpecs(cfg).isEmpty && monoCSS(cfg).isEmpty && backgroundCSS(cfg).isEmpty {
        die("没有任何可应用的设置：scope=\(cfg.scope) 对应的字体名为空，"
            + "代码块字体与页面底色也都没设。")
    }

    step("准备")
    requireCodesign()
    requireAppWrite(t)
    do { try ensureSelfInstalled() } catch { die("\(error)") }
    guard let version = t.version else { die("未找到 \(t.app.path)") }
    ok("Claude Desktop \(version)")
    checkPrevTxn()
    let fm = FileManager.default
    if !fm.fileExists(atPath: t.asar.path) && !fm.fileExists(atPath: t.asarBak.path) {
        die("app.asar 与 app.asar.bak 均不存在，应用结构异常，中止。")
    }
    if !quitClaude(t, a.yes) { die("Claude 仍在运行", 2) }

    do { try healNestedSignatures(t, a.yes) } catch { die("\(error)") }
    Sign.captureEntitlements(t)

    let txn = Txn("install", t)
    do {
        // 幂等 / 清理任何残留：先修回原始状态
        if fm.fileExists(atPath: t.asarBak.path) || fm.fileExists(atPath: t.appDir.path)
            || isPatched(t) || !Sign.valid(t) {
            step("检测到旧补丁或残留，先修回原始状态（幂等）")
            try restorePristine(t)
            txn.mark("清理旧补丁")
        }

        step("整包备份")
        try Backup.make(t, version)
        txn.mark("备份")
        try maybeCrash("after-backup")

        step("重打包 app.asar（只改 renderer preload，主进程零改动）")
        let css = buildCSS(mode, cfg)
        let staged = t.res.appendingPathComponent("app.asar.clfont-new")
        txn.addUndo("删除临时 asar") { try? fm.removeItem(at: staged) }
        let patched = try patchAsar(t.asar, staged, css)
        ok("已注入：" + patched.map { String($0.dropFirst()) }.joined(separator: "、"))
        let newHash = try asarHeaderHash(staged)
        txn.mark("重打包")
        try maybeCrash("after-patch")

        step("上线补丁（备份原 asar → 替换 → 更新完整性哈希）")
        guard let oldHash = plistGetAsarHash(t) else {
            throw CLIError("读不到 Info.plist 的 ElectronAsarIntegrity 哈希")
        }
        txn.mark("即将替换 app.asar", done: false)
        _ = try? fm.removeItem(at: t.asarBak)
        try fm.copyItem(at: t.asar, to: t.asarBak)   // 原 asar 留底，供轻量还原
        txn.addUndo("app.asar.bak 还原回 app.asar 并删除 bak") {
            guard fm.fileExists(atPath: t.asarBak.path) else { return }
            _ = try? fm.removeItem(at: t.asar)
            try fm.copyItem(at: t.asarBak, to: t.asar)
            try fm.removeItem(at: t.asarBak)
        }
        _ = try? fm.removeItem(at: t.asar)
        try fm.moveItem(at: staged, to: t.asar)
        txn.mark("app.asar 已替换")
        try maybeCrash("after-move")

        txn.mark("即将更新 Info.plist 完整性哈希", done: false)
        try plistSetAsarHash(t, newHash)
        txn.addUndo("Info.plist 哈希改回原值") { try plistSetAsarHash(t, oldHash) }
        txn.mark("Info.plist 哈希已更新")
        ok("ElectronAsarIntegrity 哈希 \(oldHash.prefix(12))… → \(newHash.prefix(12))…")
        try maybeCrash("after-rename")

        step("重签名")
        try maybeCrash("before-resign")
        try Sign.resign(t)
        txn.mark("重签名并验证")

        // commit 的定义 = 「app 能活着起来」，不是「文件操作完成」
        step("启动冒烟测试（验证 app 能存活，失败即回滚）")
        try maybeCrash("before-smoke")
        guard smokeTest(t) else {
            throw CLIError("冒烟测试失败：打补丁后 app 无法存活。补丁已判定有害，回滚。")
        }
        ok("app 启动并存活，冒烟测试通过")
        txn.mark("冒烟测试通过")

        txn.commit()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        cfg.setLastInstall(t, ["version": version, "mode": mode, "time": f.string(from: Date())])
        cfg.save()

        print("\n✓ 完成。注入方式：\(mode)，替换范围：\(cfg.scope)，"
              + "中文字体：\(cfg.string("font").isEmpty ? "—" : cfg.string("font"))，"
              + "英文字体：\(cfg.string("font_latin").isEmpty ? "—" : cfg.string("font_latin"))")
        print("  说明：")
        print("  · 重签后首次启动 Claude 可能要求重新登录/授权钥匙串（Claude Safe Storage），属预期行为。")
        print("  · 若聊天中文仍非宋体，运行 clfont install --mode brute 加兜底规则。")
        print("  · Claude 更新后补丁会失效，重跑 clfont install 即可。")
        print("  · 日志：\(Log.path)")
        if mode == "brute" {
            print("  · 当前为 brute 兜底模式：CJK 覆盖已扩大到常见具名字体族，"
                  + "不改任何 font-family，图标不受影响。")
        }
    } catch {
        let isInterrupt = error is UserInterrupt
        let name = isInterrupt ? "用户中断" : "异常：\(error)"
        print("\n✗ install 失败（\(name)）")
        // 前面的探测只是提前量，真正的写操作仍可能撞上 TCC；这里补同一段指引
        if "\(error)".contains("Operation not permitted") {
            print("  " + APP_MGMT_HINT.replacingOccurrences(of: "\n    ", with: "\n  "))
        }
        Log.raw("install failed: \(error)")
        _ = txn.rollback()
        for stale in [t.res.appendingPathComponent("app.asar.clfont-new"),
                      t.res.appendingPathComponent("app.asar.clfont-new.tmp")] {
            try? fm.removeItem(at: stale)
        }
        exit(isInterrupt ? 130 : 1)
    }
}
