import Foundation

// ---------------------------------------------------------------- uninstall

func cmdUninstall(_ t: AppTarget, _ a: Args) {
    print("clfont uninstall（目标：\(t.app.path)）")
    guard t.version != nil else { die("未找到 \(t.app.path)") }
    requireCodesign()
    requireAppWrite(t)
    checkPrevTxn()
    if !quitClaude(t, a.yes) { die("Claude 仍在运行", 2) }
    // 光把 asar 还原回去是不够的：重签只能签成 ad-hoc，Anthropic 的开发者签名、
    // hardened runtime 和身份相关的 entitlement 都回不来。整包备份里躺着的才是
    // 原封不动的原版，能还原就优先用它。
    let backup = Backup.pristineForCurrent(t)
    let adhoc = Sign.isAdhoc(t)
    let fm = FileManager.default
    do {
        if !fm.fileExists(atPath: t.asar.path) && !fm.fileExists(atPath: t.asarBak.path) {
            step("从整包备份还原")
            try restoreFromBackup(t, a.yes)
        } else if !fm.fileExists(atPath: t.appDir.path)
                    && !fm.fileExists(atPath: t.asarBak.path)
                    && !isPatched(t) && adhoc && backup != nil {
            step("从整包备份还原（连 Anthropic 原始签名一起恢复）")
            try restoreFromBackup(t, a.yes, src: backup)
        } else if adhoc, let backup {
            step("从整包备份还原（连 Anthropic 原始签名一起恢复）")
            try restoreFromBackup(t, a.yes, src: backup)
        } else {
            step("还原")
            try restorePristine(t)
        }
        Journal.clear()
        // 主动还原后就不该再提醒「补丁失效，去重新应用」了
        var cfg = Config.load()
        if cfg.clearLastInstall(t) { cfg.save() }
        if let team = Sign.teamIdentifier(t) {
            print("\n✓ 已完全还原，且恢复了原始签名（TeamIdentifier=\(team)）。")
        } else {
            print("\n✓ 已完全还原（签名已验证）。")
            info("签名是 ad-hoc：Anthropic 的原始签名没能还原（没有当前版本的整包备份，"
                 + "或备份本身就已经是重签过的）。要彻底恢复请到 "
                 + "https://claude.ai/download 重新下载安装。")
        }
    } catch {
        print("\n✗ 还原失败：\(error)")
        print("  手动还原命令：\n" + manualRestoreText(t))
        exit(1)
    }
}

// ---------------------------------------------------------------- status

func cmdStatus(_ t: AppTarget) {
    let cfg = Config.load()
    print("clfont status（目标：\(t.app.path)）")
    guard let version = t.version else { bad("未找到 \(t.app.path)"); exit(1) }
    info("Claude 版本：\(version)")
    checkPrevTxn()

    let patched = isPatched(t)
    let last = cfg.lastInstall(t)
    if patched {
        let desc = last.isEmpty ? ""
            : "（\(last["mode"] ?? "?") 模式，\(last["time"] ?? "?")）"
        ok("已打补丁 \(desc)")
    } else {
        info("未打补丁")
    }
    // 上次打补丁时的 Claude 版本与现在对不上 = Claude 自己更新过。
    // 这一行是 GUI 判断「需要提醒用户重新应用」的依据，措辞改动需同步 GUI。
    if let lv = last["version"] as? String, lv != version {
        bad("补丁已失效：Claude 已更新到 \(version)（上次应用于 \(lv)），需要重新应用一次")
    }
    let fm = FileManager.default
    info("app.asar：\(fm.fileExists(atPath: t.asar.path) ? "存在" : "不存在")"
         + "，app.asar.bak（原版留底）：\(fm.fileExists(atPath: t.asarBak.path) ? "存在" : "不存在")")
    if fm.fileExists(atPath: t.asar.path) {
        let want = (try? asarHeaderHash(t.asar)) ?? ""
        info("asar 完整性哈希：\(want == plistGetAsarHash(t) ? "匹配" : "不匹配！app 将无法启动")")
    }
    info("codesign -v：\(Sign.valid(t) ? "通过" : "未通过！")")
    if Sign.nestedStripped(t) {
        bad("Helper 权限：缺失（旧版重签名的后果，Cowork/虚拟机等功能可能不可用；"
            + "重新应用一次即会自动修复）")
    } else {
        info("Helper 权限：完整")
    }
    let backups = Backup.list(t)
    info("整包备份：" + (backups.isEmpty ? "无"
         : backups.map { $0.lastPathComponent }.joined(separator: "、")))
    info("工具固定位置：\(P.canon.path)"
         + (fm.fileExists(atPath: P.canon.path) ? "（已安装）" : "（未安装，install 时会自动复制）"))
    // 字号只在非 100% 时才写出来：GUI 拿这一行里的字体名做标题
    func fmt(_ name: String, _ pct: Int) -> String {
        (name.isEmpty ? "—" : name) + (pct != 100 ? "（\(pct)%）" : "")
    }
    info("配置：范围 \(cfg.scope)，"
         + "中文字体 \(fmt(cfg.string("font"), scaleOf(cfg, "font_scale")))，"
         + "英文字体 \(fmt(cfg.string("font_latin"), scaleOf(cfg, "font_scale_latin")))，"
         + "模式 \(cfg.mode)")
    info("代码块字体 \(fmt(cfg.string("font_mono"), scaleOf(cfg, "font_mono_scale")))"
         + "，页面底色 \(cfg.string("bg_color").isEmpty ? "—" : cfg.string("bg_color"))"
         + "，英文范围 \(cfg.string("latin_scope") == "body" ? "仅正文" : "全部")"
         + "，界面字号 \(scaleOf(cfg, "font_scale_ui"))%")
}

// ---------------------------------------------------------------- doctor

func cmdDoctor(_ t: AppTarget) {
    print("clfont doctor（目标：\(t.app.path)）")
    var problems = 0
    let fm = FileManager.default
    let version = t.version
    if let version { ok("Claude.app 存在，版本 \(version)") }
    else { bad("未找到 \(t.app.path)"); problems += 1 }

    if let j = Journal.read(), j["corrupt"] == nil {
        bad("存在未完成事务（\(j["txn"] ?? "?") @ \(j["time"] ?? "?")，状态 \(j["status"] ?? "?")）"
            + "——跑 clfont uninstall 可修复")
        problems += 1
    } else {
        ok("无未完成事务")
    }

    let songti = ["/System/Library/Fonts/Supplemental/Songti.ttc",
                  "/System/Library/Fonts/Songti.ttc",
                  HOME + "/Library/Fonts/Songti.ttc"].first { fm.fileExists(atPath: $0) }
    if let songti { ok("Songti SC 字体存在：\(songti)") }
    else { bad("未找到 Songti.ttc（系统宋体），补丁后 CJK 可能落回默认 serif"); problems += 1 }

    if claudeRunning(t) { bad("Claude 正在运行（install/uninstall 前需退出，脚本会代为处理）") }
    else { ok("Claude 未在运行") }

    let attrs = try? fm.attributesOfFileSystem(forPath: HOME)
    let free = Double((attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0) / 1073741824
    if free >= 3 { ok(String(format: "磁盘剩余 %.1fGB（备份约需 1–2GB）", free)) }
    else { bad(String(format: "磁盘剩余仅 %.1fGB，可能不够备份", free)); problems += 1 }

    let (writeOK, writeDetail) = appWritePermitted(t)
    if writeOK { ok("「App 管理」权限：可写入目标 app") }
    else {
        bad("「App 管理」权限：无法写入 \(t.app.path)（\(writeDetail)）")
        info("请到「系统设置 → 隐私与安全性 → App 管理」为 Clfont（或从终端运行时的「终端」）打开开关")
        problems += 1
    }

    let (csOK, csDetail) = Sign.codesignAvailable()
    if csOK { ok("codesign 可用：\(csDetail)") }
    else {
        bad("codesign 不可用：\(csDetail)。先运行 xcode-select --install，"
            + "否则 install/uninstall 都无法完成，连回滚也签不了名")
        problems += 1
    }

    let backups = Backup.list(t)
    info("备份目录 \(P.dataDir.path)：当前目标有 \(backups.count) 份备份")
    if version != nil {
        if let team = Sign.teamIdentifier(t) {
            ok("签名身份：TeamIdentifier=\(team)（原厂签名）")
        } else if Backup.pristineForCurrent(t) != nil {
            info("签名身份：ad-hoc（已被 clfont 重签）。当前版本有整包备份，"
                 + "clfont uninstall 可恢复原始签名")
        } else {
            bad("签名身份：ad-hoc（已被 clfont 重签），且没有当前版本的整包备份，"
                + "原始签名无法还原——需要重新下载安装 Claude 才能恢复")
            problems += 1
        }
        if Sign.nestedStripped(t) {
            bad("Helper 权限：已被旧版重签名抹掉（Cowork、虚拟机等功能会不可用）")
            if Backup.pristineForCurrent(t) != nil { info("下次 clfont install 会自动从整包备份还原并修复") }
            else { info("没有可用备份，需重新下载安装 Claude 才能修复") }
            problems += 1
        } else {
            ok("Helper 权限：完整")
        }
    }
    if fm.fileExists(atPath: P.canon.path) { ok("工具固定位置已安装：\(P.canon.path)") }
    else { info("工具尚未安装到 \(P.canon.path)（install 时会自动复制）") }

    if version != nil {
        if fm.fileExists(atPath: t.appDir.path) {
            bad("存在 app/ 目录（旧机制残留）——当前 Claude 启用了 OnlyLoadAppFromAsar fuse，"
                + "该目录会导致 app 无法启动，运行 clfont uninstall 清理")
            problems += 1
        }
        if !fm.fileExists(atPath: t.asar.path) {
            bad("app.asar 缺失！运行 clfont uninstall 从整包备份恢复")
            problems += 1
        } else {
            if isPatched(t) {
                ok("已打补丁（asar 内检测到注入标记）")
            } else if fm.fileExists(atPath: t.asarBak.path) {
                bad("app.asar.bak 存在但 asar 无补丁标记（半成品状态），运行 clfont uninstall 可恢复")
                problems += 1
            } else {
                ok("未打补丁（原始状态）")
            }
            let want = (try? asarHeaderHash(t.asar)) ?? ""
            if want == plistGetAsarHash(t) { ok("asar 完整性哈希与 Info.plist 匹配") }
            else {
                bad("asar 完整性哈希与 Info.plist 不匹配——Claude 将无法启动！跑 clfont uninstall 修复")
                problems += 1
            }
        }
        if Sign.valid(t) { ok("codesign 验证通过") }
        else {
            bad("codesign 验证未通过——Claude 将无法启动！跑 clfont uninstall（会重签）")
            problems += 1
        }
    }
    print("\n" + (problems > 0 ? "✗ 发现 \(problems) 个问题" : "✓ 一切正常"))
    exit(problems > 0 ? 1 : 0)
}

// ---------------------------------------------------------------- backups

func cmdBackups(_ t: AppTarget, _ a: Args) {
    print("clfont backups（目标：\(t.app.path)）")
    let cur = t.version
    let items = Backup.list(t)
    let others = Backup.allBackups().filter { o in !items.contains(where: { $0.path == o.path }) }
    if items.isEmpty && others.isEmpty {
        info("没有任何整包备份。首次 install 时会自动创建。")
        return
    }
    let showAll = a.flags["--all"] != nil
    var total: Int64 = 0, dropBytes: Int64 = 0
    var prunable: [URL] = []
    for b in items {
        let size = Backup.size(b)
        total += size
        if Backup.version(b) == cur {
            ok("\(b.lastPathComponent)  \(humanSizeCLI(size))  ← 与当前版本一致，"
               + "还原时可连原始签名一起恢复，请勿删除")
        } else {
            dropBytes += size
            prunable.append(b)
            info("\(b.lastPathComponent)  \(humanSizeCLI(size))  ← 旧版本，已无法用于还原，可清理")
        }
    }
    // 目标换过路径后，旧路径的备份会成为孤儿：两个目标都列不到它。--all 一并显示。
    if !others.isEmpty {
        let osize = others.reduce(Int64(0)) { $0 + Backup.size($1) }
        if showAll {
            total += osize
            for b in others {
                let bsize = Backup.size(b)
                dropBytes += bsize
                prunable.append(b)
                info("\(b.lastPathComponent)  \(humanSizeCLI(bsize))  ← 属于其他目标（如测试 Claude）或已不存在的目标")
            }
        } else {
            info("另有 \(others.count) 份属于其他目标的备份（\(humanSizeCLI(osize))），"
                 + "用 clfont backups --all 查看和清理")
        }
    }
    let shown = items.count + (showAll ? others.count : 0)
    info("合计 \(humanSizeCLI(total))（\(shown) 份），"
         + "其中 \(prunable.count) 份可清理，可释放 \(humanSizeCLI(dropBytes))")

    if a.flags["--purge"] != nil {
        // 删光当前目标的备份，包括与当前版本一致的那份。只在「彻底删掉这个目标」
        // 时才用得上（比如删除测试副本），平时不该走这条路。
        guard !items.isEmpty else { return }
        guard confirm("  确认删除当前目标的全部 \(items.count) 份备份？", a.yes) else { return }
        for b in items {
            try? FileManager.default.removeItem(at: b)
            ok("已删除 \(b.lastPathComponent)")
        }
        return
    }
    if a.flags["--prune"] != nil {
        guard !prunable.isEmpty else { info("没有可清理的备份"); return }
        guard confirm("  确认删除上述 \(prunable.count) 份？", a.yes) else { return }
        for b in prunable {
            try? FileManager.default.removeItem(at: b)
            ok("已删除 \(b.lastPathComponent)")
        }
        info("释放约 \(humanSizeCLI(dropBytes))")
    }
}
