import SwiftUI
import AppKit

// clfont GUI（macOS 26）
// 界面按 design_handoff_clfont_ui/README.md 的方案 1a 实现。
// 只调用打包在 bundle 里的 clfont CLI；备份、重打包、重签、冒烟测试、失败回滚
// 全部由 CLI 负责，GUI 自己不碰 Claude.app 的任何文件。

// MARK: - 文案

/// 界面语言。auto 跟随系统：系统首选语言以 zh 开头用中文，其余一律英文。
enum Lang: String, CaseIterable, Identifiable {
    case auto, zh, en
    var id: String { rawValue }

    /// 实际生效的语言（把 auto 解析掉）
    static func resolve(_ l: Lang) -> Lang {
        guard l == .auto else { return l }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? .zh : .en
    }
}

/// 界面文案集中在这里。中文是基准表：英文表缺哪一条就回落到中文，不会出现
/// 空字符串或 key 泄漏到界面上。
///
/// 调试版（-D CLFONT_DEBUG）会额外读取一份覆盖文件，可在运行中实时改文案，
/// 改完由开发者合并回本文件。覆盖文件：
/// ~/Library/Application Support/clfont/copy-overrides.json
final class Copy: ObservableObject {
    static let shared = Copy()

    /// 语言切换要让整个界面重画，所以放在这里当发布源，而不是各视图各读一份
    @Published var lang: Lang = Lang(rawValue:
        UserDefaults.standard.string(forKey: "uiLanguage") ?? "auto") ?? .auto {
        didSet { UserDefaults.standard.set(lang.rawValue, forKey: "uiLanguage") }
    }

    var effective: Lang { Lang.resolve(lang) }

    /// 中文是基准表；改文案请直接改这里。
    static let zh: [String: String] = [
        // 文案改动请直接改这里；调试版可实时预览，改完由开发者合并回来。
        "font.mode.desc": "「标准」不生效时再用「扩展」，会多覆盖一批常见字体",
        "font.preview.cjk": "字体是沉默的声音",
        "font.scope.desc": "只换中文最安全；换英文会连同界面文字一起改变",
        "footer.ops": "安装会先退出该 Claude，全程有完整备份；失败或中途取消都会把文件恢复原样，随时可用「还原」完全撤销。重签名后首次启动可能要求重新授权钥匙串，属正常现象。",
        "footer.safety": "Clfont 仅在本机修改 Claude 的字体渲染：注入内容只有字体规则，不改动任何网络请求，也不读取账号信息与聊天记录。",
        "header.subtitle": "使用 Clfont，在 Claude 里安全地使用你喜欢的中英文字体",
        "help.title": "如何使用 Clfont",
        "help.a2.lead": "在「测试 Claude」卡片上，点击",
        "help.a2.tail": "，约需 1 分钟",
        "help.a4.lead": "点击",
        "help.sec.start": "开始使用",
        "help.sec.settings": "各项设置",
        "help.sec.daily": "日常维护",

        "help.step1.title": "首次使用：授予「App 管理」权限",
        "help.step1.body": "修改 Claude 的应用包需要「App 管理」权限。第一次执行应用时 macOS 会弹出请求，选择「允许」即可。\n若此前误选了「不允许」，程序会在界面上说明，并提供直接前往「系统设置 → 隐私与安全性 → App 管理」的按钮，打开开关后重新执行。\n除此之外不需要任何额外组件，也不需要「辅助功能」权限。",
        "help.step2.title": "先在测试 Claude 上确认效果",
        "help.step2.body": "应用字体需要给 Claude 重新签名，正式版的原始签名会因此被替换。为避免反复改动日常使用的应用，建议每次换字体先在测试 Claude 上看效果。\n测试 Claude 是正式版的完整副本，有独立的应用标识与配置目录，怎么折腾都不影响正式版。首次启动会要求授权钥匙串「Claude Safe Storage」，输入 Mac 的登录密码并选「始终允许」；该弹窗可能连续出现几次（实测最多 4 次），每次都一样处理。",
        "help.step3.title": "应用到正式 Claude",
        "help.step3.body": "效果满意后，切回「正式 Claude」卡片再执行一次。整个过程约 1 至 2 分钟，期间请勿关闭窗口。",

        "help.step4.title": "替换范围与字体",
        "help.step4.body": "「中文」只改中文字形，界面图标不受影响，是推荐选项。「英文」和「中英文」会连界面上的英文一起改；若之后发现个别图标显示异常，改回「中文」即可。\n选定范围后在下方挑字体，预览会立即更新。",
        "help.step5.title": "字号",
        "help.step5.body": "中文与英文可分别在 80% 到 150% 之间调节，用来弥补宋体这类字体默认显示偏小的问题。\n它只缩放被替换掉的那些字，界面图标、行距与整体布局都不动——不是把整个页面放大。",
        "help.step6.title": "代码块",
        "help.step6.body": "可单独指定代码块与行内代码的等宽字体和字号，正文不受影响。默认「保持不变」，此时完全不注入相关规则。",
        "help.step7.title": "页面底色",
        "help.step7.body": "把 Claude 的界面底色换成早期版本的米色。提供三档预设，也可以用取色器自选。\n仅在浅色模式生效；深色模式下这项设置不会起作用，无需担心配色被改坏。",
        "help.step8.title": "兼容模式",
        "help.step8.body": "保持「标准」即可。若个别区域的字体没跟着变，再切到「扩展」——它会把同样的替换规则扩展到更多常见字体族。",

        "help.step9.title": "Claude 更新后需重新应用",
        "help.step9.body": "Claude 的自动更新会重写应用内容，此前应用的字体随之失效。程序检测到这一情况时会在主界面提示，并附一个「重新应用」按钮，点一下就好，字体设置无需重选。",
        "help.step10.title": "还原与自检",
        "help.step10.body": "「还原」撤销全部修改。若能匹配到当前版本的完整备份，Anthropic 的原始签名会一并恢复。\n遇到异常先点「自检」：它会检查应用完整性、未完成的事务、字体、磁盘空间、哈希与签名，结果写进日志。",
        "help.step11.title": "应用过程与失败处理",
        "help.step11.body": "应用依次执行：退出目标应用 → 创建完整备份 → 重新打包 → 更新完整性哈希 → 重新签名 → 启动验证。\n任何一步失败或中途取消，都会把文件恢复原样并重新验证签名。所以最坏的结果是「没能应用」，而不是「Claude 打不开」。\n需要注意：自动回滚只恢复文件内容，不恢复 Claude 的原始签名；要连签名一起恢复，请执行「还原」。",

        "help.safety.title": "关于安全性",
        "help.safety.b1": "注入内容只有字体规则（CSS @font-face），不改动任何网络请求，也不绕过任何限制或配额。",
        "help.safety.b2": "不读取、不上传账号信息与聊天记录，全部操作都在本机完成。",
        "help.safety.b3": "应用前会创建完整备份。任一环节失败或中途取消都会把文件恢复原样，随时可用「还原」完全撤销。",
        "help.footer": "本工具只修改你选定的 Claude 应用包，不读取账号与会话数据。",
        "target.hint": "建议先在测试 Claude 上确认字体效果，再应用到正式 Claude。",
        "stale.action": "重新应用",
        "appmgmt.body": "修改 Claude 的应用包需要「App 管理」权限。系统会在第一次执行时弹出请求，若此前选择了「不允许」，请点击下方按钮前往设置，为 Clfont 打开开关后重新执行。",
        "appmgmt.open": "打开「App 管理」设置",
        "appmgmt.recheck": "我已打开，重新检测",
        "appmgmt.title": "无法修改 Claude：缺少「App 管理」权限",
        "update.auto": "启动时自动检查更新",
        "update.body": "下载后替换「应用程序」中的 Clfont 即可，字体设置会保留。若此前已为 Claude 应用过字体，更新后请重新执行一次「应用」。",
        "update.download": "前往下载",
        "update.later": "以后再说",
        "stale.body": "Claude 的自动更新会重写应用内容，此前应用的字体随之失效。重新应用一次即可恢复，设置无需重新选择。",
        "stale.title": "Claude 已更新，此前应用的字体已失效",
        "helper.body": "早期版本的 Clfont 在重新签名时会一并清除 Claude 内部组件的系统权限，导致 Cowork、虚拟机等功能不可用。重新应用一次，程序会从完整备份还原后再进行修改；若没有可用备份，请重新下载安装 Claude。",
        "helper.title": "检测到早期版本遗留的权限缺失",

        // —— 主界面
        "header.whatsnew": "新特性",
        "header.help": "如何使用",
        "target.prod": "正式 Claude",
        "target.test": "测试 Claude",
        "target.none": "尚未创建，点击右上角创建",
        "target.title": "选择需要更换字体的 Claude 版本",
        "target.create": "创建测试 Claude",
        "target.rebuild": "重建",
        "target.delete": "删除",

        // —— 状态卡
        "status.missing": "找不到这个 Claude",
        "status.loading": "读取中…",
        "status.applied": "已应用 {font}",
        "status.font": "字体",
        "status.stale": "字体当前未生效",
        "status.none": "尚未应用，随时可以撤回",
        "status.detail": "详情",
        "status.collapse": "收起",
        "status.backedup": "已备份",
        "status.nobackup": "未备份",
        "status.checked": "{time} 检查",
        "detail.integrity": "asar 完整性",
        "detail.match": "匹配",
        "detail.mismatch": "不匹配",
        "detail.pass": "通过",
        "detail.fail": "未通过",
        "detail.backups": "整包备份",
        "detail.none": "无",
        "detail.count": "{n} 份",
        "detail.disk": "磁盘剩余",
        "detail.usage": "备份占用",
        "detail.prune": "清理 {n} 份旧备份",
        "detail.keepall": "均需保留",

        // —— 字体设置
        "font.group": "字体",
        "font.scope": "替换范围",
        "font.scope.cjk": "中文",
        "font.scope.latin": "英文",
        "font.scope.both": "中英文",
        "font.cjk": "中文字体",
        "font.cjk.size": "中文字号",
        "font.latin": "英文字体",
        "font.latin.size": "英文字号",
        "font.mode": "兼容模式",
        "font.mode.std": "标准",
        "font.mode.ext": "扩展",
        "font.preview.label": "预览",
        "font.reset": "恢复 100%",
        "font.sample": "字A",

        // —— 代码块
        "code.group": "代码块",
        "code.font": "代码字体",
        "code.size": "代码字号",
        "code.desc": "只影响代码块与行内代码，正文不受影响",
        "code.keep": "保持不变",

        // —— 外观
        "look.group": "外观",
        "look.bg": "页面底色",
        "look.bg.desc": "把 Claude 的界面底色换成早期版本的米色。仅在浅色模式生效。",
        "look.bg.off": "不修改",
        "look.bg.custom": "自定",
        "header.lang": "Clfont 的界面语言",

        // —— 按钮
        "action.apply": "应用到{target}",
        "action.reapply": "重新应用到{target}",
        "action.doctor": "自检",
        "action.open": "打开",
        "action.restore": "还原",

        // —— 日志
        "log.show": "显示日志（{n}）",
        "log.hide": "隐藏日志",
        "log.clear": "清除日志",
        "log.cleared": "日志已清除",
        "log.guard": "备份保护中，失败自动回滚",

        // —— 进度提示
        "busy.status": "读取{target}状态",
        "busy.install": "安装到「{target}」：备份 → 重打包 → 重签名 → 启动测试（约 1–2 分钟）",
        "busy.uninstall": "还原「{target}」：恢复原文件 → 重签名",
        "busy.doctor": "自检「{target}」",
        "busy.prune": "清理旧备份",
        "busy.create": "创建测试副本：复制 → 换独立身份 → 重签名 → 播种登录态",
        "busy.remove": "移除测试 Claude：删除副本、配置目录与它的备份",
        "msg.clifail": "✗ 启动 CLI 失败：{err}",
        "msg.noscript": "✗ 找不到 {name}",
        "msg.opened": "· 已启动测试 Claude（独立配置目录）",
        "msg.openfail": "✗ 启动测试 Claude 失败：{err}",

        // —— 弹层
        "sheet.cancel": "取消",
        "sheet.ok": "知道了",
        "sheet.delete.title": "彻底删除测试 Claude？",
        "sheet.delete.ok": "删除",
        "sheet.delete.body": "将删除测试 Claude 的应用副本、它的配置目录，以及它在 clfont 数据目录中的整包备份，可释放约 1 GB 空间。\n\n正式 Claude 及其备份不受影响。之后仍可随时重新创建。",
        "sheet.create.title": "创建测试 Claude？",
        "sheet.create.ok": "创建",
        "sheet.create.body": "将从正式 Claude 复制一份副本，替换为独立的应用标识，并把当前的登录状态复制过去，因此无需重新登录。副本使用独立的配置目录，在其上进行的任何操作都不会影响正式 Claude。\n\n若副本已存在，将被删除后重新创建。",
        "sheet.restore.title": "确认还原 Claude 字体？",
        "sheet.restore.body": "会从备份恢复{target}的 app.asar 并重新签名，当前的{font}设置将被移除。Claude 需要退出后重新打开。",
        "sheet.restore.backup": "备份 {name}",
        "sheet.restore.nobackup": "没有整包备份，将用 app.asar.bak 原版留底还原",

        // —— 更新
        "update.check": "检查更新",
        "update.title": "Clfont {tag} 可供下载",
        "update.norepo": "还没上架 GitHub，暂时没有可检查的版本。",
        "update.found": "有新版本 {tag}。",
        "update.latest": "已是最新版本。",
        "update.norelease": "仓库里还没有发布任何版本。",
        "update.failed": "检查失败：{why}",
        "update.err.norepo": "仓库地址没配置",
        "update.err.rate": "GitHub 限流了，过一会儿再试",
        "update.err.code": "GitHub 返回 {code}",
        "update.err.parse": "发布信息解析失败",

        // —— 关于 / 新特性
        "about.title": "关于 Clfont",
        "about.version": "版本 {v}（{b}）",
        "about.tagline": "替换 Claude 桌面版界面的显示字体，支持中文、英文或中英文",
        "about.dev": "开发者",
        "about.devname": "赵万（Jovan）",
        "about.footer": "仅修改本机安装的 Claude 应用包，不读取账号与会话数据",
        "about.lang": "界面语言",
        "about.lang.auto": "跟随系统",
        "release.version": "版本 {v}",
        "release.current": "当前版本",

        // —— 教程里的操作行
    ]

    /// 英文表。缺的条目自动回落到中文，所以不必强求逐条对齐。
    static let en: [String: String] = [
        "help.title": "Using Clfont",
        "help.a2.lead": "On the Test Claude card, click",
        "help.a2.tail": ", which takes about a minute",
        "help.a4.lead": "Click",
        "help.sec.start": "Getting started",
        "help.sec.settings": "Settings",
        "help.sec.daily": "Day to day",

        "help.step1.title": "First run: the App Management permission",
        "help.step1.body": "Changing Claude's app bundle needs the App Management permission. macOS asks for it the first time you apply — choose Allow.\nIf you turned it down earlier, Clfont says so in the window and gives you a button straight to System Settings → Privacy & Security → App Management. Switch Clfont on there and try again.\nNothing else is needed. Clfont does not use Accessibility permission.",
        "help.step2.title": "Try it on the test Claude first",
        "help.step2.body": "Applying fonts means re-signing Claude, which replaces its original signature. So rather than keep reworking the app you use all day, try each font on the test Claude first.\nThe test Claude is a full copy with its own app identity and its own profile — nothing you do to it touches the real one. The first launch asks for the \"Claude Safe Storage\" keychain item: enter your Mac login password and pick Always Allow. It may ask a few times over (four, in our testing); answer it the same way each time.",
        "help.step3.title": "Apply to your main Claude",
        "help.step3.body": "Happy with how it looks? Switch back to the Main Claude card and apply again. It takes a minute or two — leave the window open while it works.",

        "help.step4.title": "Scope and fonts",
        "help.step4.body": "Chinese swaps Chinese characters only and leaves the interface icons alone, which is why it's the default. English and Both change the interface text as well; if an icon ever looks wrong afterwards, switch back to Chinese.\nPick your fonts underneath and the preview updates as you go.",
        "help.step5.title": "Size",
        "help.step5.body": "Chinese and English each scale from 80% to 150%, which helps with fonts like Songti that come out small at their default size.\nOnly the replaced characters scale. Icons, line spacing and layout stay put, so this is not the same as zooming the page.",
        "help.step6.title": "Code blocks",
        "help.step6.body": "Code blocks and inline code can take their own monospace font and size, with body text left alone. Leave it unchanged and Clfont writes no code-related rules at all.",
        "help.step7.title": "Page background",
        "help.step7.body": "Brings back the warm cream background of earlier Claude versions. Three presets, or pick your own with the colour well.\nLight mode only. In dark mode this setting does nothing, so there's no risk of wrecking the dark palette.",
        "help.step8.title": "Compatibility",
        "help.step8.body": "Leave this on Standard. If some corner of the interface keeps its old font, switch to Extended, which applies the same rules across a wider set of font families.",

        "help.step9.title": "Re-apply after Claude updates",
        "help.step9.body": "A Claude update rewrites the app, and your fonts go with it. Clfont notices and says so in the main window, with a Re-apply button next to it. One click and you're back — your settings were never lost.",
        "help.step10.title": "Restore and Diagnose",
        "help.step10.body": "Restore undoes everything. When a full backup of the current version is available, Anthropic's original signature comes back with it.\nIf something looks off, start with Diagnose: it checks app integrity, unfinished work, fonts, disk space, hashes and signatures, and writes what it finds to the log.",
        "help.step11.title": "What applying does, and what happens if it fails",
        "help.step11.body": "Applying works through: quit the target app → take a full backup → repack → update the integrity hash → re-sign → check that it launches.\nIf any step fails, or you cancel partway, the files go back as they were and the signature is verified again. The worst outcome is that nothing was applied, not a Claude that won't open.\nOne thing to know: that automatic rollback restores the files, not Claude's original signature. Use Restore if you want the signature back too.",

        "help.safety.title": "On safety",
        "help.safety.b1": "The only thing injected is font rules (CSS @font-face). Network requests are untouched, and nothing bypasses any limit or quota.",
        "help.safety.b2": "Your account and your conversations are never read or uploaded. Everything happens on this Mac.",
        "help.safety.b3": "A full backup is taken before anything changes. If a step fails or you cancel, the files go back as they were, and Restore undoes everything whenever you like.",
        "help.footer": "Clfont only touches the Claude app bundle you pick. It never reads your account or your conversations.",
        "font.mode.desc": "Only reach for Extended if Standard misses something",
        "font.preview.cjk": "字体是沉默的声音",
        "font.scope.desc": "Chinese alone is the safe choice; English restyles the interface too",
        "footer.ops": "Applying quits Claude first and always takes a full backup. If a step fails or you cancel, the files go back as they were, and Restore undoes everything whenever you like. macOS may ask for keychain access the next time Claude starts; that is expected.",
        "footer.safety": "Clfont changes how Claude draws text on this Mac, and nothing else. It injects font rules only: no network request is touched, and your account and conversations are never read.",
        "header.subtitle": "Put the fonts you like into Claude, safely",
        "target.hint": "Try the fonts on the test Claude before touching the real one.",
        "stale.action": "Re-apply",
        "stale.body": "A Claude update rewrote the app and took your fonts with it. Re-apply to get them back; your settings were never lost.",
        "stale.title": "Claude updated — your fonts were overwritten",
        "appmgmt.body": "Changing Claude's app bundle needs the App Management permission. macOS asks the first time you apply. If you turned it down, use the button below, switch Clfont on, and try again.",
        "appmgmt.open": "Open App Management settings",
        "appmgmt.recheck": "Enabled — check again",
        "appmgmt.title": "Can't modify Claude: App Management permission missing",
        "helper.body": "Older versions of Clfont stripped the system permissions from Claude's internal components while re-signing, which breaks Cowork and virtual machines. Apply once more and Clfont restores from a full backup before it changes anything. With no backup to work from, reinstall Claude.",
        "helper.title": "Permissions stripped by an earlier version",
        "update.auto": "Check for updates on launch",
        "update.body": "Download it and drop it into your Applications folder, replacing the old one. Your settings carry over. If you have already applied fonts to Claude, apply once more afterwards.",
        "update.download": "Download",
        "update.later": "Later",

        "header.whatsnew": "What's new",
        "header.help": "How to use",
        "target.prod": "Main Claude",
        "target.test": "Test Claude",
        "target.none": "Not created yet — use the button above",
        "target.title": "Which Claude do you want to restyle?",
        "target.create": "Create test Claude",
        "target.rebuild": "Rebuild",
        "target.delete": "Delete",

        "status.missing": "Can't find this Claude",
        "status.loading": "Reading…",
        "status.applied": "{font} applied",
        "status.font": "font",
        "status.stale": "Fonts are not in effect",
        "status.none": "Not applied. Reversible whenever you like",
        "status.detail": "Details",
        "status.collapse": "Hide",
        "status.backedup": "Backed up",
        "status.nobackup": "No backup",
        "status.checked": "checked {time}",
        "detail.integrity": "asar integrity",
        "detail.match": "OK",
        "detail.mismatch": "Mismatch",
        "detail.pass": "Valid",
        "detail.fail": "Invalid",
        "detail.backups": "Full backups",
        "detail.none": "None",
        "detail.count": "{n}",
        "detail.disk": "Free space",
        "detail.usage": "Backup size",
        "detail.prune": "Remove {n} old backup(s)",
        "detail.keepall": "All needed",

        "font.group": "Fonts",
        "font.scope": "Scope",
        "font.scope.cjk": "Chinese",
        "font.scope.latin": "English",
        "font.scope.both": "Both",
        "font.cjk": "Chinese font",
        "font.cjk.size": "Chinese size",
        "font.latin": "English font",
        "font.latin.size": "English size",
        "font.mode": "Compatibility",
        "font.mode.std": "Standard",
        "font.mode.ext": "Extended",
        "font.preview.label": "Preview",
        "font.reset": "Reset to 100%",
        "font.sample": "Aa字",

        "code.group": "Code blocks",
        "code.font": "Code font",
        "code.size": "Code size",
        "code.desc": "Code blocks and inline code only. Body text stays as it is",
        "code.keep": "Leave unchanged",

        "look.group": "Appearance",
        "look.bg": "Page background",
        "look.bg.desc": "Brings back the cream background of earlier Claude versions. Light mode only.",
        "look.bg.off": "Unchanged",
        "look.bg.custom": "Custom",
        "header.lang": "Clfont's own interface language",

        "action.apply": "Apply to {target}",
        "action.reapply": "Re-apply to {target}",
        "action.doctor": "Diagnose",
        "action.open": "Open",
        "action.restore": "Restore",

        "log.show": "Show log ({n})",
        "log.hide": "Hide log",
        "log.clear": "Clear log",
        "log.cleared": "Log cleared",
        "log.guard": "Backed up. Rolls back on its own if anything fails",

        "busy.status": "Reading {target} status",
        "busy.install": "Applying to {target}: backing up → repacking → re-signing → checking it launches (1–2 min)",
        "busy.uninstall": "Restoring {target}: put files back → re-sign",
        "busy.doctor": "Diagnosing {target}",
        "busy.prune": "Removing old backups",
        "busy.create": "Building the test copy: duplicating → new identity → re-signing → carrying your session across",
        "busy.remove": "Removing test Claude: copy, profile and its backups",
        "msg.clifail": "✗ Could not start the CLI: {err}",
        "msg.noscript": "✗ {name} not found",
        "msg.opened": "· Test Claude launched (separate profile)",
        "msg.openfail": "✗ Could not launch the test Claude: {err}",

        "sheet.cancel": "Cancel",
        "sheet.ok": "Got it",
        "sheet.delete.title": "Delete the test Claude?",
        "sheet.delete.ok": "Delete",
        "sheet.delete.body": "This removes the test Claude, its profile and its backups in Clfont's data folder, freeing around 1 GB.\n\nYour real Claude and its backups are untouched, and you can make a new test copy whenever you want.",
        "sheet.create.title": "Create a test Claude?",
        "sheet.create.ok": "Create",
        "sheet.create.body": "This makes a copy of your Claude, gives it its own app identity, and brings your current session across so you need not sign in again. The copy keeps a separate profile, so nothing you do in it reaches the real Claude.\n\nAny existing copy is replaced.",
        "sheet.restore.title": "Restore Claude's fonts?",
        "sheet.restore.body": "This restores {target}'s app.asar from backup and re-signs it. The current {font} setting is removed. Claude must be quit and reopened.",
        "sheet.restore.backup": "Backup {name}",
        "sheet.restore.nobackup": "No full backup — restoring from the app.asar.bak original",

        "update.check": "Check for updates",
        "update.title": "Clfont {tag} is available",
        "update.norepo": "Not published on GitHub yet, so there is nothing to check.",
        "update.found": "Version {tag} is available.",
        "update.latest": "You're on the latest version.",
        "update.norelease": "No releases have been published yet.",
        "update.failed": "Check failed: {why}",
        "update.err.norepo": "No repository configured",
        "update.err.rate": "GitHub is rate-limiting; try again shortly",
        "update.err.code": "GitHub returned {code}",
        "update.err.parse": "Could not read the release information",

        "about.title": "About Clfont",
        "about.version": "Version {v} ({b})",
        "about.tagline": "Swaps the display fonts in Claude for desktop: Chinese, English, or both",
        "about.dev": "Developer",
        "about.devname": "Wan Zhao (Jovan)",
        "about.footer": "Only touches the Claude installed on this Mac. Never reads accounts or conversations.",
        "about.lang": "Language",
        "about.lang.auto": "System",
        "release.version": "Version {v}",
        "release.current": "Current",

    ]

    static var fileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()
            + "/Library/Application Support/clfont/copy-overrides.json")
    }

    /// 调试版的实时改稿；与语言无关，覆盖当前生效的那一条
    @Published private(set) var overrides: [String: String] = [:]

    /// 调试面板列 key 用；英文缺的条目用中文补齐，保证覆盖全部 key
    static var defaults: [String: String] { en.merging(zh) { a, _ in a } }

    private init() { load() }

    func load() {
        guard let d = try? Data(contentsOf: Self.fileURL),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: String]
        else { overrides = [:]; return }
        overrides = j
    }

    func set(_ key: String, _ value: String) {
        let base = Copy.defaults[key] ?? ""
        if value == base { overrides.removeValue(forKey: key) }
        else { overrides[key] = value }
        save()
    }

    func reset() { overrides = [:]; save() }

    private func save() {
        let dir = Self.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(
            withJSONObject: overrides,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? d.write(to: Self.fileURL)
        }
    }

    func text(_ key: String) -> String {
        if let o = overrides[key] { return o }
        if effective == .en, let e = Copy.en[key] { return e }
        return Copy.zh[key] ?? key
    }
}

/// 取文案。`t("key")`；带占位符的用 `t("key", ["{n}": "3"])`。
func t(_ key: String) -> String { Copy.shared.text(key) }

func t(_ key: String, _ subs: [String: String]) -> String {
    var s = Copy.shared.text(key)
    for (k, v) in subs { s = s.replacingOccurrences(of: k, with: v) }
    return s
}

// MARK: - 设计 tokens

extension Color {
    /// 转成 #RRGGBB。ColorPicker 给的是显示色域的颜色，先转 sRGB 再取分量，
    /// 否则在广色域屏幕上取到的值会偏。
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X",
                      Int(ns.redComponent * 255 + 0.5),
                      Int(ns.greenComponent * 255 + 0.5),
                      Int(ns.blueComponent * 255 + 0.5))
    }

    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum DS {
    static let accent = Color(hex: 0x0A84FF)
    static let danger = Color(hex: 0xFF3B30)
    static let success = Color(hex: 0x34C759)
    /// 全 App 唯一不用蓝色主题的地方：两个目标各有自己的选中色
    static let prod = Color(hex: 0xD97757)
    static let test = Color(hex: 0x5E78DC)

    /// 一般状态过渡
    static let ease = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.22)
    static let ease24 = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.24)
    /// 弹层入场
    static let pop = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.24)

    static let card = RoundedRectangle(cornerRadius: 12, style: .continuous)
    static let tile = RoundedRectangle(cornerRadius: 13, style: .continuous)
    static let button = RoundedRectangle(cornerRadius: 11, style: .continuous)
}

/// 分组标题：11px / 600 / 字距 .06em / 弱色
private struct GroupLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.66)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
}

/// 提示条：圆形图标 + 标题 + 说明 + 可选操作。用于那些「不看见就会误解」的
/// 状态：缺命令行工具、Claude 更新后修改失效、早期版本遗留的权限缺失。
private struct NoticeCard<Actions: View>: View {
    let tint: Color
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.16)).frame(width: 22, height: 22)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(message)
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
                actions
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(tint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(tint.opacity(0.22), lineWidth: 1))
    }
}

// MARK: - 更新说明

/// 面向用户的更新说明：只说「改了什么」和「你要做什么」，不堆术语。
struct ReleaseNote: Identifiable {
    let version: String
    /// 中英文各存一份，改起来两边对照着看，不容易漏
    let zh: [String]
    let en: [String]
    /// 需要用户配合的动作；没有就留 nil
    let actionZH: String?
    let actionEN: String?
    var id: String { version }

    var changes: [String] { Copy.shared.effective == .en ? en : zh }
    var action: String? { Copy.shared.effective == .en ? actionEN : actionZH }
}

let releaseNotes: [ReleaseNote] = [
    ReleaseNote(
        version: "6.0",
        zh: [
            "不再需要 Xcode 命令行工具。命令行部分已重写并编入应用包，安装后即可直接使用，无需另行下载任何组件。",
            "新增页面底色调节，可把 Claude 的界面改成米黄等暖色。只在浅色模式下生效，深色模式不受影响。",
            "新增代码块字体与字号的单独设置。",
            "新增界面语言切换，支持简体中文与英文，默认跟随系统。",
            "修复替换英文时，带重音的拉丁字母（é ü ñ 等）不跟随变化的问题。",
        ],
        en: [
            "The Xcode Command Line Tools are no longer required. The command-line component has been rewritten and is now built into the app — nothing else to download.",
            "Added a page background color, so Claude's interface can be warmed up to cream or any other tint. Light mode only; dark mode is untouched.",
            "Added separate font and size settings for code blocks.",
            "Added an interface language switch — Simplified Chinese and English, following the system by default.",
            "Fixed accented Latin letters (é, ü, ñ and friends) not changing along with the rest of the English text.",
        ],
        actionZH: nil, actionEN: nil),
    ReleaseNote(
        version: "5.3",
        zh: [
            "新增字号调节。中文与英文可分别设置 80% 至 150%，用于弥补宋体等字体默认显示偏小的问题。该设置只作用于被替换的文字，界面图标、行距与整体布局均不受影响。",
            "缺少「App 管理」权限导致修改被系统拦下时，界面会给出说明，并提供直接前往对应设置面板的入口。",
            "执行修改前先行确认该权限，不再等到备份完成后才失败。",
        ],
        en: [
            "Added size adjustment. Chinese and English can each be set between 80% and 150%, which helps with fonts like Songti that render small by default. It only affects the replaced text — interface icons, line spacing and layout are unchanged.",
            "When the App Management permission is missing and macOS blocks the change, the window now explains why and offers a direct link to the right settings pane.",
            "That permission is now checked before any work begins, instead of failing after the backup completes.",
        ],
        actionZH: nil, actionEN: nil),
    ReleaseNote(
        version: "5.2",
        zh: [
            "修复应用字体后 Claude 的 Cowork、虚拟机等功能不可用的问题。此前重新签名时会一并清除 Claude 内部组件的系统权限，现已完整保留。",
            "对早期版本造成的上述权限缺失，程序会在检测到时提示，并在下次「应用」时从完整备份自动修复。",
            "Claude 自动更新覆盖已应用的字体时，主界面会直接给出提示与重新应用入口，不必自行察觉。",
            "修正测试 Claude 与正式 Claude 共用一份应用记录的问题，两者的状态现已分别记录。",
            "新增自动检查更新：启动时于后台查询一次，有新版本时在界面中提示。该功能可在「关于」中关闭。",
        ],
        en: [
            "Fixed Cowork and virtual machines becoming unavailable after applying fonts. Re-signing used to strip the system permissions of Claude's internal components; they are now preserved in full.",
            "Where an earlier version already stripped those permissions, Clfont detects it and repairs it from a full backup the next time you apply.",
            "When a Claude update overwrites your fonts, the main window now says so and offers a re-apply button.",
            "Fixed the test and production Claude sharing a single record of what was applied; each is now tracked separately.",
            "Added an automatic update check: once in the background on launch, with a notice when a new version is available. Can be turned off under About.",
        ],
        actionZH: "若此前已为 Claude 应用过字体，建议重新执行一次「应用」，以恢复被早期版本清除的系统权限。",
        actionEN: "If you have applied fonts with an earlier version, apply once more to restore the system permissions it stripped."),
    ReleaseNote(
        version: "5.1",
        zh: [
            "修复替换英文时，侧边栏、输入框等区域字体不跟随变化的问题。",
            "修复 Claude 思考过程文本字体偶发不跟随变化的问题。",
        ],
        en: [
            "Fixed the sidebar, composer and similar areas not picking up the new font when replacing English.",
            "Fixed Claude's thinking text occasionally keeping its original font.",
        ],
        actionZH: "若此前已为 Claude 应用过字体，需重新执行一次「应用」，本次修复方可生效。",
        actionEN: "If you have already applied fonts, apply once more for this fix to take effect."),
    ReleaseNote(
        version: "5.0",
        zh: [
            "支持替换中文、英文或中英文，中英文字体可分别指定。",
            "提供测试 Claude，可在改动日常使用的应用之前先确认效果。",
            "支持随时还原，并在备份可用时一并恢复 Claude 的原始签名。",
        ],
        en: [
            "Replace Chinese, English or both, with a separate font for each.",
            "A test Claude to try things on before touching the app you use every day.",
            "Restore at any time, bringing back Claude's original signature when a matching backup exists.",
        ],
        actionZH: nil, actionEN: nil),
]

// MARK: - CLI 输出标记

/// 这些**不是界面文案**，是 CLI（clfont，Python）输出里用来解析状态的字面量。
/// 界面切成英文时它们必须原样不动——改动前请同步改 CLI，两边一起改。
enum CLIMarker {
    static let patched = "已打补丁"
    static let signBad = "codesign -v：未通过"
    static let hashBad = "asar 完整性哈希：不匹配"
    static let stale = "补丁已失效"
    static let helperMissing = "Helper 权限：缺失"
    static let version = "Claude 版本："
    static let backups = "整包备份："
    static let none = "无"
    static let font = "字体 "
    static let totalPrefix = "合计 "
    static let totalMid = "），其中"
    static let prunablePrefix = "其中 "
    static let prunableSuffix = " 份可清理"
    static let appMgmtNeeded = "需要「App 管理」权限"
    static let appMgmtDenied = "「App 管理」权限：无法写入"
}

// MARK: - 目标

enum Target: String, CaseIterable, Identifiable {
    case production, testCopy
    var id: String { rawValue }
    var label: String { t(self == .production ? "target.prod" : "target.test") }
    var tint: Color { self == .production ? DS.prod : DS.test }
}

/// 测试副本相关路径。放在 Application Support 下，与用户数据同区。
enum Paths {
    static var support: String {
        NSHomeDirectory() + "/Library/Application Support/clfont"
    }
    static var testApp: String { support + "/Claude-test.app" }
    static var testProfile: String { support + "/test-profile" }
    static var smokeProfile: String { support + "/smoke-profile" }
}

/// 每个目标各自记一份状态，切换时立刻显示它自己的数据
struct AppStatus {
    var loaded = false
    var missing = false
    var patched = false
    var version = "—"
    var signOK = true
    var integrityOK = true
    /// Claude 自己更新过，此前应用的字体被覆盖掉了，需要重新应用一次
    var stale = false
    /// 嵌套 Helper 的权限是否完整（旧版重签名会把它抹掉，Cowork 等功能会失效）
    var helperOK = true
    var backups: [String] = []
    var font = ""
    var checkedAt = ""
    var raw = ""
}

// MARK: - 字体扫描

struct FontChoice: Identifiable, Hashable {
    let family: String
    /// 系统给出的本地化名（中文环境下如「宋体」）；与 family 相同时不展示
    let localized: String?
    let regular: String?
    let bold: String?
    var id: String { family }
}

enum FontScanner {
    static func cjkFamilies() -> [FontChoice] {
        families(covering: ["中", "文", "汉", "国"],
                 preferred: ["Songti SC", "Songti TC", "STSong", "Kaiti SC",
                             "STKaiti", "STFangsong", "Yuanti SC"])
    }

    /// 等宽字体。按 NSFont 的 fixedPitch 特征筛，比按名字猜可靠。
    static func monoFamilies() -> [FontChoice] {
        let mgr = NSFontManager.shared
        let mono = Set(mgr.availableFontFamilies.filter { fam in
            NSFont(name: fam, size: 12)?.fontDescriptor
                .symbolicTraits.contains(.monoSpace) ?? false
        })
        return families(covering: ["A", "0"],
                        preferred: ["SF Mono", "Menlo", "Monaco", "Courier New",
                                    "JetBrains Mono", "Fira Code", "Source Code Pro"])
            .filter { mono.contains($0.family) }
    }

    static func latinFamilies() -> [FontChoice] {
        families(covering: ["A", "a", "0", "?"],
                 preferred: ["Helvetica Neue", "Avenir Next", "Georgia", "Palatino",
                             "Times New Roman", "Optima", "Menlo"])
    }

    private static func families(covering probes: [Character],
                                 preferred: [String]) -> [FontChoice] {
        let mgr = NSFontManager.shared
        var out: [FontChoice] = []
        for fam in mgr.availableFontFamilies {
            guard let f = NSFont(name: fam, size: 12) else { continue }
            let set = f.coveredCharacterSet
            guard probes.allSatisfy({ c in c.unicodeScalars.allSatisfy { set.contains($0) } })
            else { continue }
            let reg = mgr.font(withFamily: fam, traits: [], weight: 5, size: 12)?.fontName
            let bold = mgr.font(withFamily: fam, traits: .boldFontMask,
                                weight: 9, size: 12)?.fontName
            let loc = mgr.localizedName(forFamily: fam, face: nil)
            out.append(FontChoice(family: fam,
                                  localized: loc == fam ? nil : loc,
                                  regular: reg,
                                  bold: bold == reg ? nil : bold))
        }
        return out.sorted {
            let a = preferred.firstIndex(of: $0.family) ?? Int.max
            let b = preferred.firstIndex(of: $1.family) ?? Int.max
            return a == b ? $0.family < $1.family : a < b
        }
    }
}

// MARK: - 模型

final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buf = ""
    func append(_ s: String) { lock.lock(); buf += s; lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return buf }
}

@MainActor final class Model: ObservableObject {
    @Published var log = ""
    @Published var busy = false
    @Published var busyLabel = ""
    @Published var target: Target = .production
    @Published var fontFamily = "Songti SC"
    @Published var fontLatin = ""
    @Published var scope = "cjk"          // cjk | latin | both
    @Published var mode = "auto"
    /// 字号百分比。走 @font-face 的 size-adjust，只缩放被替换掉的那些字符，
    /// 不动 CSS 的 font-size，因此图标与整体布局都不受影响。
    @Published var fontScale = 100.0
    @Published var fontScaleLatin = 100.0
    /// 代码块字体。空 = 不改，保持 Claude 原本的等宽字体。
    @Published var fontMono = ""
    @Published var fontMonoScale = 100.0
    /// 页面底色。空 = 不改。形如 #F0EEE6，只在浅色模式生效。
    @Published var bgColor = ""
    /// 上一次修改操作是否因缺少「App 管理」权限被系统拦下。
    /// 不做启动时的主动探测——那需要真的去写一次 Claude，会在用户还没提出
    /// 任何要求时就弹出系统授权请求。等到操作真的失败再提示，时机才对。
    @Published var appMgmtDenied = false
    @Published var fonts: [FontChoice] = []
    @Published var latinFonts: [FontChoice] = []
    @Published var monoFonts: [FontChoice] = []

    /// 备份统计按目标缓存：切回来时立刻有内容，不必重新扫盘
    @Published var backupInfo: [Target: (summary: String, prunable: Int)] = [:]
    @Published var backupLoading: Set<Target> = []


    var replacesCJK: Bool { scope == "cjk" || scope == "both" }
    var replacesLatin: Bool { scope == "latin" || scope == "both" }
    @Published var statuses: [Target: AppStatus] = [:]
    var current: AppStatus { statuses[target] ?? AppStatus() }

    /// nil = 用 CLI 的默认目标（/Applications/Claude.app）
    func cliPath(_ tgt: Target) -> String? {
        tgt == .production ? nil : Paths.testApp
    }
    func fullPath(_ tgt: Target) -> String {
        tgt == .production ? "/Applications/Claude.app" : Paths.testApp
    }
    func exists(_ tgt: Target) -> Bool {
        FileManager.default.fileExists(atPath: fullPath(tgt))
    }
    func displayPath(_ tgt: Target) -> String {
        if tgt == .production { return "/Applications/Claude.app" }
        return exists(tgt) ? "~/Library/Application Support/clfont" : t("target.none")
    }

    var logLines: [String] {
        log.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var diskFree: String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let v = try? url.resourceValues(
                  forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = v.volumeAvailableCapacityForImportantUsage else { return "—" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB]
        return f.string(fromByteCount: bytes)
    }

    private var cli: String {
        Bundle.main.path(forResource: "clfont", ofType: nil)
            ?? NSHomeDirectory() + "/.local/bin/clfont"
    }
    private var configURL: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.config/clfont/config.json")
    }

    func loadFonts() {
        fonts = FontScanner.cjkFamilies()
        latinFonts = FontScanner.latinFamilies()
        monoFonts = FontScanner.monoFamilies()
        if !fonts.contains(where: { $0.family == fontFamily }), let f = fonts.first {
            fontFamily = f.family
        }
        if fontLatin.isEmpty || !latinFonts.contains(where: { $0.family == fontLatin }) {
            fontLatin = latinFonts.first?.family ?? ""
        }
    }

    func fontChoice(_ family: String) -> FontChoice? {
        (fonts + latinFonts + monoFonts).first { $0.family == family }
    }

    func loadConfig() {
        guard let d = try? Data(contentsOf: configURL),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        fontFamily = j["font"] as? String ?? fontFamily
        fontLatin = j["font_latin"] as? String ?? fontLatin
        scope = j["scope"] as? String ?? scope
        mode = j["mode"] as? String ?? mode
        fontScale = (j["font_scale"] as? NSNumber)?.doubleValue ?? fontScale
        fontScaleLatin = (j["font_scale_latin"] as? NSNumber)?.doubleValue ?? fontScaleLatin
        fontMono = j["font_mono"] as? String ?? fontMono
        fontMonoScale = (j["font_mono_scale"] as? NSNumber)?.doubleValue ?? fontMonoScale
        bgColor = j["bg_color"] as? String ?? bgColor
    }

    func saveConfig() {
        var j: [String: Any] = [:]
        if let d = try? Data(contentsOf: configURL),
           let old = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { j = old }
        let c = fontChoice(fontFamily)
        let l = fontChoice(fontLatin)
        j["font"] = fontFamily
        j["font_latin"] = fontLatin
        j["scope"] = scope
        j["mode"] = mode
        j["font_scale"] = Int(fontScale.rounded())
        j["font_scale_latin"] = Int(fontScaleLatin.rounded())
        j["font_mono"] = fontMono
        j["font_mono_scale"] = Int(fontMonoScale.rounded())
        j["bg_color"] = bgColor
        if let mo = fontChoice(fontMono)?.regular { j["font_mono_regular"] = mo }
        else { j.removeValue(forKey: "font_mono_regular") }
        if let mb = fontChoice(fontMono)?.bold { j["font_mono_bold"] = mb }
        else { j.removeValue(forKey: "font_mono_bold") }
        if let r = c?.regular { j["font_regular"] = r } else { j.removeValue(forKey: "font_regular") }
        if let b = c?.bold { j["font_bold"] = b } else { j.removeValue(forKey: "font_bold") }
        if let r = l?.regular { j["font_latin_regular"] = r } else { j.removeValue(forKey: "font_latin_regular") }
        if let b = l?.bold { j["font_latin_bold"] = b } else { j.removeValue(forKey: "font_latin_bold") }
        if j["fallback_fonts"] == nil { j["fallback_fonts"] = ["STSong", "Songti TC"] }
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let out = try? JSONSerialization.data(withJSONObject: j,
                                                 options: [.prettyPrinted, .withoutEscapingSlashes]) {
            try? out.write(to: configURL)
        }
    }

    private func exec(_ args: [String], on tgt: Target, label: String, stream: Bool = true,
                      done: (@MainActor (Int32, String) -> Void)? = nil) {
        var a = args
        if let tp = cliPath(tgt) { a = ["--app", tp] + a }
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        if tgt == .testCopy {
            // 装补丁时的启动测试用独立配置目录，别去动用户正在用的那份
            env["CLFONT_SMOKE_USER_DATA_DIR"] = Paths.smokeProfile
        }
        spawn(exe: cli, args: a, env: env, label: label, stream: stream,
              echo: "clfont \(args.joined(separator: " "))  →  \(tgt.label)", done: done)
    }

    private func spawn(exe: String, args: [String], env: [String: String],
                       label: String, stream: Bool, echo: String,
                       done: (@MainActor (Int32, String) -> Void)? = nil) {
        if busy { return }
        busy = true; busyLabel = label
        if stream { log += "\n▸ \(echo)\n" }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        let box = OutputBox()
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            let s = String(decoding: d, as: UTF8.self)
            box.append(s)
            if stream { Task { @MainActor [weak self] in self?.log += s } }
        }
        p.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            let all = box.text
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.busy = false; self.busyLabel = ""
                done?(proc.terminationStatus, all)
            }
        }
        do { try p.run() } catch {
            log += t("msg.clifail", ["{err}": error.localizedDescription]) + "\n"
            busy = false; busyLabel = ""
        }
    }

    /// 读取某个目标的状态并单独存起来
    func refresh(_ tgt: Target, then: (@MainActor () -> Void)? = nil) {
        guard exists(tgt) else {
            statuses[tgt] = AppStatus(loaded: true, missing: true)
            then?(); return
        }
        exec(["status"], on: tgt, label: t("busy.status", ["{target}": tgt.label]), stream: false) { [weak self] _, out in
            guard let self else { return }
            var s = AppStatus()
            s.loaded = true
            s.raw = out
            s.patched = out.contains(CLIMarker.patched)
            s.signOK = !out.contains(CLIMarker.signBad)
            s.integrityOK = !out.contains(CLIMarker.hashBad)
            s.stale = out.contains(CLIMarker.stale)
            s.helperOK = !out.contains(CLIMarker.helperMissing)
            if let r = out.range(of: CLIMarker.version) {
                s.version = String(out[r.upperBound...].prefix { !$0.isNewline })
                    .trimmingCharacters(in: .whitespaces)
            }
            if let r = out.range(of: CLIMarker.backups) {
                let line = String(out[r.upperBound...].prefix { !$0.isNewline })
                    .trimmingCharacters(in: .whitespaces)
                s.backups = line == CLIMarker.none ? [] : line.components(separatedBy: "、")
            }
            if let r = out.range(of: CLIMarker.font) {
                s.font = String(out[r.upperBound...].prefix { $0 != "，" && !$0.isNewline })
            }
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            s.checkedAt = f.string(from: Date())
            self.statuses[tgt] = s
            then?()
        }
    }

    /// 两个目标都读一遍（串行，CLI 一次只跑一个）
    func refreshAll() {
        refresh(.production) { [weak self] in self?.refresh(.testCopy) }
    }

    /// 统计备份占用。du 要扫整个 app 包（1–2 秒），所以：只在展开「详情」时跑、
    /// 结果按目标缓存、并且**不走 busy 那条通道**——它只是只读统计，没必要把
    /// 整个界面禁用掉，否则切换目标时会灰一下，看着像卡顿。
    func loadBackups(_ tgt: Target, force: Bool = false) {
        guard exists(tgt) else { backupInfo[tgt] = ("", 0); return }
        if !force, backupInfo[tgt] != nil { return }
        guard !backupLoading.contains(tgt) else { return }
        backupLoading.insert(tgt)
        var args = ["backups"]
        if let tp = cliPath(tgt) { args = ["--app", tp] + args }
        runQuiet(args) { [weak self] out in
            guard let self else { return }
            self.backupLoading.remove(tgt)
            var summary = ""
            var prunable = 0
            for raw in out.split(separator: "\n") where raw.contains(CLIMarker.totalPrefix) {
                let line = String(raw)
                if let a = line.range(of: CLIMarker.totalPrefix), let b = line.range(of: CLIMarker.totalMid) {
                    summary = String(line[a.upperBound..<b.lowerBound])
                        .replacingOccurrences(of: "（", with: " · ")
                }
                if let a = line.range(of: CLIMarker.prunablePrefix), let b = line.range(of: CLIMarker.prunableSuffix) {
                    prunable = Int(line[a.upperBound..<b.lowerBound]) ?? 0
                }
            }
            self.backupInfo[tgt] = (summary, prunable)
        }
    }

    /// 只读命令：后台跑，不设 busy、不写日志、不影响界面可用性
    private func runQuiet(_ args: [String], done: @escaping @MainActor (String) -> Void) {
        let exe = cli
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            var text = ""
            do {
                try p.run()
                let d = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                text = String(decoding: d, as: UTF8.self)
            } catch {
                text = ""
            }
            let out = text
            await MainActor.run { done(out) }
        }
    }

    func pruneBackups(_ tgt: Target) {
        exec(["backups", "--prune", "-y"], on: tgt, label: t("busy.prune")) {
            [weak self] _, _ in self?.loadBackups(tgt, force: true)
        }
    }

    func install() {
        saveConfig()
        let tgt = target
        exec(["install", "-y", "--scope", scope, "--mode", mode,
              "--scale", String(Int(fontScale.rounded())),
              "--scale-latin", String(Int(fontScaleLatin.rounded())),
              "--mono", fontMono,
              "--mono-scale", String(Int(fontMonoScale.rounded())),
              "--bg", bgColor], on: tgt,
             label: t("busy.install", ["{target}": tgt.label])) {
            [weak self] _, out in
            self?.noteAppMgmt(out)
            self?.refresh(tgt)
        }
    }

    func uninstall() {
        let tgt = target
        exec(["uninstall", "-y"], on: tgt, label: t("busy.uninstall", ["{target}": tgt.label])) {
            [weak self] _, out in
            self?.noteAppMgmt(out)
            self?.refresh(tgt)
        }
    }

    func doctor() {
        let tgt = target
        exec(["doctor"], on: tgt, label: t("busy.doctor", ["{target}": tgt.label])) { [weak self] _, out in
            self?.noteAppMgmt(out)
            self?.refresh(tgt)
        }
    }

    /// 两处标记：install/uninstall 被拦下时的「需要「App 管理」权限」，以及
    /// doctor 的「无法写入」。注意 doctor 通过时也会打印「App 管理」四个字，
    /// 所以不能只匹配这四个字。措辞改动需与 CLI 同步。
    private func noteAppMgmt(_ out: String) {
        let denied = out.contains(CLIMarker.appMgmtNeeded)
            || out.contains(CLIMarker.appMgmtDenied)
        withAnimation(DS.ease) { appMgmtDenied = denied }
    }

    /// 重建测试副本：从正式版复制一份，换独立身份、去掉 claude:// 注册，
    /// 并把登录态播种过去。脚本随 app 打包在 Resources 里。
    func rebuildTestCopy() {
        guard let script = Bundle.main.path(forResource: "setup-test-copy", ofType: "sh") else {
            log += "\n" + t("msg.noscript", ["{name}": "setup-test-copy.sh"]) + "\n"
            return
        }
        spawn(exe: "/bin/bash", args: [script],
              env: ProcessInfo.processInfo.environment,
              label: t("busy.create"),
              stream: true, echo: "bash setup-test-copy.sh") { [weak self] _, _ in
            self?.refresh(.testCopy)
        }
    }

    /// 彻底移除测试 Claude：应用副本、配置目录、它自己的整包备份。
    func removeTestCopy() {
        guard let script = Bundle.main.path(forResource: "remove-test-copy", ofType: "sh") else {
            log += "\n" + t("msg.noscript", ["{name}": "remove-test-copy.sh"]) + "\n"
            return
        }
        spawn(exe: "/bin/bash", args: [script],
              env: ProcessInfo.processInfo.environment,
              label: t("busy.remove"),
              stream: true, echo: "bash remove-test-copy.sh") { [weak self] _, _ in
            guard let self else { return }
            self.target = .production
            self.backupInfo[.testCopy] = nil
            self.refresh(.testCopy)
        }
    }

    /// 打开当前目标。测试副本与正式版共用 CFBundleName，双击或 open 都会被
    /// LaunchServices 导向正式版，只能直接跑二进制并指定独立配置目录。
    func openTarget() {
        if target == .production {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/Applications/Claude.app"),
                configuration: NSWorkspace.OpenConfiguration())
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Paths.testApp + "/Contents/MacOS/Claude")
        p.arguments = ["--user-data-dir=" + Paths.testProfile]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            log += "\n" + t("msg.opened") + "\n"
        } catch {
            log += "\n" + t("msg.openfail", ["{err}": error.localizedDescription]) + "\n"
        }
    }
}

// MARK: - 小部件

/// 呼吸绿点 + 光环：2.8s 循环
private struct BreathingDot: View {
    @State private var breathe = false
    @State private var halo = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(DS.success.opacity(0.55), lineWidth: 1.5)
                .frame(width: 7, height: 7)
                .scaleEffect(halo ? 2.1 : 0.7)
                .opacity(halo ? 0 : 0.45)
            Circle()
                .fill(DS.success)
                .frame(width: 7, height: 7)
                .scaleEffect(breathe ? 1.12 : 1)
                .opacity(breathe ? 1 : 0.55)
        }
        .frame(width: 7, height: 7)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeOut(duration: 2.8).repeatForever(autoreverses: false)) {
                halo = true
            }
        }
    }
}

/// 破坏性文字按钮：平时只有红字，hover 才出淡红底
private struct DestructiveButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(DS.danger.opacity(enabled ? 1 : 0.4))
                .frame(height: 38)
                .padding(.horizontal, 16)
                .background {
                    Capsule().fill(DS.danger.opacity(hover && enabled ? 0.12 : 0))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(DS.ease, value: hover)
    }
}

private struct SwitchOption: Identifiable, Hashable {
    let value: String
    let label: String
    var id: String { value }
}

/// 玻璃切换：选中项是一枚会滑过去的玻璃胶囊
private struct GlassSwitch: View {
    @Binding var selection: String
    let options: [SwitchOption]
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { opt in
                let on = selection == opt.value
                Button { selection = opt.value } label: {
                    Text(opt.label)
                        .font(.system(size: 13, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background {
                    if on {
                        Color.clear
                            .glassEffect(.regular.tint(DS.accent), in: Capsule())
                            .matchedGeometryEffect(id: "glassSwitch", in: ns)
                    }
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color(hex: 0x787880).opacity(0.14)))
        .animation(DS.ease24, value: selection)
    }
}

/// 教学指引里内联的按钮样例：照着界面上真实按钮的样子缩小复刻一份，
/// 让用户一眼认出该点哪个，而不是只读到一个名字。
private enum ChipKind { case primary, glass, link, danger }

private struct BtnChip: View {
    let title: String
    var kind: ChipKind = .glass

    var body: some View {
        switch kind {
        case .primary:
            base.font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11).padding(.vertical, 4.5)
                .background(Capsule().fill(DS.accent))
                .shadow(color: DS.accent.opacity(0.28), radius: 3, y: 1)
        case .glass:
            base.font(.system(size: 11.5))
                .padding(.horizontal, 11).padding(.vertical, 4.5)
                .glassEffect(.regular, in: Capsule())
        case .danger:
            base.font(.system(size: 11.5))
                .foregroundStyle(DS.danger)
                .padding(.horizontal, 11).padding(.vertical, 4.5)
                .background(Capsule().fill(DS.danger.opacity(0.10)))
        case .link:
            base.font(.system(size: 12, weight: .medium)).foregroundStyle(DS.accent)
        }
    }

    private var base: Text { Text(title) }
}

/// 分段控件的复刻：各段共用一条轨道，选中的那段是实心胶囊
private struct SegChip: View {
    let options: [String]
    var selected: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, label in
                if i == selected {
                    Text(label)
                        .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 11).padding(.vertical, 4.5)
                        .background(Capsule().fill(DS.accent))
                } else {
                    Text(label)
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .padding(.horizontal, 11).padding(.vertical, 4.5)
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color(hex: 0x787880).opacity(0.14)))
    }
}

/// 「…… [按钮] ……」这样的操作提示行
private struct ActionLine<C: View>: View {
    let lead: String
    var tail: String = ""
    @ViewBuilder let chips: () -> C

    var body: some View {
        HStack(spacing: 7) {
            Text(lead).font(.system(size: 12.5)).foregroundStyle(.secondary)
            chips()
            if !tail.isEmpty {
                Text(tail).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }
}

/// 一行「标签 — 值」
private struct DetailRow: View {
    let label: String
    let value: String
    var bad = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(bad ? DS.danger : Color.primary)
        }
    }
}

// MARK: - 界面

struct ContentView: View {
    @StateObject private var m = Model()
    @State private var detailOpen = false
    @State private var logOpen = false
    @State private var confirmRestore = false
    @State private var showHelp = false
    @State private var showWhatsNew = false
    @StateObject private var updates = UpdateWatcher()
    /// 切换界面语言要让整个界面重画，所以正式版也观察它
    @ObservedObject private var copy = Copy.shared
#if CLFONT_DEBUG
    @State private var showDebug = true
    @State private var dbgBusy = false
    @State private var dbgSearch = ""
#endif
    @AppStorage("lastSeenVersion") private var lastSeenVersion = ""

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
    /// 版本变过、且这一版的说明还没看过时，图标上点一个小红点
    private var hasUnseenNotes: Bool {
        !appVersion.isEmpty && lastSeenVersion != appVersion
    }
    private func openWhatsNew() {
        showWhatsNew = true
        lastSeenVersion = appVersion
    }
    @State private var confirmRebuild = false
    @State private var confirmRemove = false
    /// 内容实测高度；初值取收起态的大致高度，免得首帧窗口先小后大跳一下
    @State private var contentH: CGFloat = 620

    /// 隐藏标题栏后窗口 frame 里仍然算着那约 32pt
    private var maxContentH: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - 32
    }

    private var busyNow: Bool {
#if CLFONT_DEBUG
        m.busy || dbgBusy
#else
        m.busy
#endif
    }

    private var sheetOpen: Bool { confirmRestore || showHelp || showWhatsNew }

    /// 主界面本体；调试版会在它右侧并排放一个调试面板
    private var mainColumn: some View {
        // 窗口高度跟着内容走（详情 / 日志就地展开），但不越过屏幕可见区域；
        // 真超出了才让内容自己滚，不然什么都点不到。
        ScrollView {
            content.background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { contentH = g.size.height }
                        .onChange(of: g.size.height) { _, h in contentH = h }
                }
            }
        }
        .scrollDisabled(contentH <= maxContentH)
        .frame(width: 700, height: min(contentH, maxContentH))
        // 背景走 .background，不参与布局，否则色斑会把窗口撑大、内容被居中；
        // 给它一个超出窗口的固定高度，免得隐藏标题栏那 32pt 露出窗口底色
        .background { backdrop.frame(height: 1400) }
        .overlay { if confirmRestore { restoreSheet } }
        .overlay { if showHelp { helpSheet } }
        .overlay { if showWhatsNew { whatsNewSheet } }
    }

    var body: some View {
        HStack(spacing: 0) {
            mainColumn
#if CLFONT_DEBUG
            if showDebug { debugPanel }
#endif
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            m.loadFonts(); m.loadConfig(); m.refreshAll()
            updates.checkIfDue()
        }
        .animation(DS.ease24, value: m.target)
        .animation(DS.pop, value: m.scope)
        .onChange(of: m.target) { _, t in
            if detailOpen { m.loadBackups(t) }   // 有缓存就直接用，不再扫盘
        }
        .animation(DS.ease24, value: m.busy)
        .animation(DS.pop, value: detailOpen)
        .animation(DS.pop, value: logOpen)
        .animation(DS.pop, value: confirmRestore)
        .animation(DS.pop, value: showHelp)
        .animation(DS.pop, value: showWhatsNew)
        .alert(t("sheet.delete.title"), isPresented: $confirmRemove) {
            Button(t("sheet.cancel"), role: .cancel) {}
            Button(t("sheet.delete.ok"), role: .destructive) { m.removeTestCopy() }
        } message: {
            Text(t("sheet.delete.body"))
        }
        .alert(t("sheet.create.title"), isPresented: $confirmRebuild) {
            Button(t("sheet.cancel"), role: .cancel) {}
            Button(t("sheet.create.ok"), role: .destructive) { m.rebuildTestCopy() }
        } message: {
            Text(t("sheet.create.body"))
        }
    }

    // 玻璃需要背后有东西才能折射：两层极淡色晕，几乎看不见但不要删
    private var backdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Circle().fill(Color(hex: 0x78AAFF).opacity(0.14))
                .frame(width: 520).blur(radius: 120).offset(x: -230, y: -300)
            Circle().fill(Color(hex: 0xFFA0BE).opacity(0.11))
                .frame(width: 460).blur(radius: 120).offset(x: 260, y: 330)
        }
        .ignoresSafeArea()
    }

    /// Claude 的自动更新会重写 app.asar，此前应用的字体随之消失。用户看到的
    /// 只是「字体自己变回去了」，不主动说明的话，多半会以为是本软件出了问题。
    private var staleNotice: some View {
        NoticeCard(tint: DS.prod, symbol: "arrow.clockwise",
                   title: t("stale.title"), message: t("stale.body")) {
            Button(t("stale.action")) { m.install() }
                .buttonStyle(.glassProminent).tint(DS.prod)
                .buttonBorderShape(.capsule)
                .disabled(busyNow)
                .padding(.top, 2)
        }
    }

    /// 早期版本重签名时用了 codesign --deep，把 Claude 内部组件的 entitlements
    /// 一并抹掉，Cowork、虚拟机等功能会静默失效。这种损伤无法就地修补，只能
    /// 从完整备份还原——「应用」时会自动处理，这里只负责让用户知道发生了什么。
    private var helperNotice: some View {
        NoticeCard(tint: DS.danger, symbol: "exclamationmark",
                   title: t("helper.title"), message: t("helper.body")) { EmptyView() }
    }

    /// 缺少「App 管理」权限时，任何修改都会被系统拦下。只在操作真的失败后
    /// 出现，并直接给出跳转到对应设置面板的入口。
    private var appMgmtNotice: some View {
        NoticeCard(tint: DS.danger, symbol: "lock",
                   title: t("appmgmt.title"), message: t("appmgmt.body")) {
            HStack(spacing: 10) {
                Button(t("appmgmt.open")) {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!)
                }
                .buttonStyle(.glassProminent).tint(DS.danger)
                .buttonBorderShape(.capsule)
                Button(t("appmgmt.recheck")) { m.doctor() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12)).foregroundStyle(DS.accent)
                    .disabled(busyNow)
            }
            .padding(.top, 2)
        }
    }

    /// 启动时后台查到的新版本。只在确实有更新时出现，「以后再说」之后同一版本
    /// 不再打扰；查不到、网络不通都不显示任何东西。
    private func updateNotice(_ r: Updater.Release) -> some View {
        NoticeCard(tint: DS.accent, symbol: "arrow.down",
                   title: t("update.title", ["{tag}": r.tag]), message: t("update.body")) {
            HStack(spacing: 10) {
                Button(t("update.download")) { NSWorkspace.shared.open(r.page) }
                    .buttonStyle(.glassProminent).tint(DS.accent)
                    .buttonBorderShape(.capsule)
                Button(t("update.later")) { updates.skip() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            appHeader
            statusCard
            if m.appMgmtDenied { appMgmtNotice }
            if m.current.loaded && !m.current.missing {
                if m.current.stale { staleNotice }
                if !m.current.helperOK { helperNotice }
            }
            if let r = updates.available { updateNotice(r) }
            targetGroup
            fontGroup
            codeGroup
            lookGroup
            actions
            if busyNow { busyRow }
            logSection
            VStack(alignment: .leading, spacing: 5) {
                Text(t("footer.safety"))
                Text(t("footer.ops"))
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        // 没有标题栏了，顶部留出红黄绿三个圆点的位置
        .padding(.top, 46)
        .padding(.bottom, 24)
        .blur(radius: sheetOpen ? 3 : 0)
        .disabled(sheetOpen)
    }

    // MARK: 应用头

    private var appHeader: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Clfont")
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.17)
                Text(t("header.subtitle"))
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 16) {
                Button { openWhatsNew() } label: {
                    HStack(spacing: 5) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .medium))
                            if hasUnseenNotes {
                                Circle().fill(DS.prod)
                                    .frame(width: 5, height: 5)
                                    .offset(x: 4, y: -2)
                            }
                        }
                        Text(t("header.whatsnew")).font(.system(size: 13))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.accent)

                // 放在头部而不是设置区：设置区里的每一项都是「对 Claude 做的修改」，
                // 界面语言只关乎 Clfont 自己，混在一起会被读成「把 Claude 汉化」。
                Menu {
                    Picker("", selection: $copy.lang) {
                        Text(t("about.lang.auto")).tag(Lang.auto)
                        Text("中文").tag(Lang.zh)
                        Text("English").tag(Lang.en)
                    }
                    .pickerStyle(.inline).labelsHidden()
                } label: {
                    Image(systemName: "globe")
                        .font(.system(size: 13, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(DS.accent)
                .help(t("header.lang"))

                Button { showHelp = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 13, weight: .medium))
                        Text(t("header.help")).font(.system(size: 13))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.accent)
            }
        }
    }

    // MARK: 状态卡

    private var statusCard: some View {
        let s = m.current
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(s.patched ? DS.success : Color.secondary.opacity(0.34))
                        .frame(width: 20, height: 20)
                    Image(systemName: s.patched ? "checkmark" : "minus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusHeadline(s))
                        .font(.system(size: 14, weight: .semibold))
                    Text(statusSubline(s))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if !s.missing {
                    Button(detailOpen ? t("status.collapse") : t("status.detail")) {
                        detailOpen.toggle()
                        if detailOpen { m.loadBackups(m.target) }
                    }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.accent)
                }
                Button { m.refresh(m.target) } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .disabled(m.busy)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            if detailOpen && !s.missing {
                Divider().opacity(0.5)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 20),
                                    GridItem(.flexible())],
                          alignment: .leading, spacing: 8) {
                    DetailRow(label: t("detail.integrity"),
                              value: t(s.integrityOK ? "detail.match" : "detail.mismatch"), bad: !s.integrityOK)
                    DetailRow(label: "codesign",
                              value: t(s.signOK ? "detail.pass" : "detail.fail"), bad: !s.signOK)
                    DetailRow(label: t("detail.backups"),
                              value: s.backups.isEmpty ? t("detail.none")
                                                      : t("detail.count", ["{n}": String(s.backups.count)]))
                    DetailRow(label: t("detail.disk"), value: m.diskFree)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12).padding(.bottom, 10)

                HStack(spacing: 8) {
                    Text(t("detail.usage")).font(.system(size: 12)).foregroundStyle(.secondary)
                    let info = m.backupInfo[m.target]
                    if m.backupLoading.contains(m.target) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    } else {
                        Text(info?.summary.isEmpty == false ? info!.summary : "—")
                            .font(.system(size: 12, design: .monospaced))
                    }
                    Spacer()
                    if let n = info?.prunable, n > 0 {
                        Button(t("detail.prune", ["{n}": String(n)])) { m.pruneBackups(m.target) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12)).foregroundStyle(DS.accent)
                            .disabled(m.busy)
                    } else if info?.summary.isEmpty == false {
                        Text(t("detail.keepall")).font(.system(size: 11.5)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 14)
            }
        }
        .glassEffect(.regular, in: DS.card)
    }

    private func statusHeadline(_ s: AppStatus) -> String {
        if s.missing { return t("status.missing") }
        if !s.loaded { return t("status.loading") }
        if s.patched { return t("status.applied", ["{font}": s.font.isEmpty ? t("status.font") : s.font]) }
        if s.stale { return t("status.stale") }     // 具体原因由下方提示条说明
        return t("status.none")
    }

    private func statusSubline(_ s: AppStatus) -> String {
        if s.missing { return m.displayPath(m.target) }
        var parts = [m.target.label, s.version]
        parts.append(t(s.backups.isEmpty ? "status.nobackup" : "status.backedup"))
        if !s.checkedAt.isEmpty { parts.append(t("status.checked", ["{time}": s.checkedAt])) }
        return parts.joined(separator: " · ")
    }

    // MARK: 版本选择

    private var targetGroup: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                GroupLabel(text: t("target.title"))
                Spacer()
                if !m.exists(.testCopy) {
                    // 还没建的时候一直显示，不用先点卡片才发现有这么个入口
                    Button(t("target.create")) { confirmRebuild = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 12)).foregroundStyle(DS.accent)
                        .disabled(m.busy)
                } else if m.target == .testCopy {
                    Button(t("target.rebuild")) { confirmRebuild = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 12)).foregroundStyle(DS.accent)
                        .disabled(m.busy)
                    Text("·").font(.system(size: 12)).foregroundStyle(.tertiary)
                    Button(t("target.delete")) { confirmRemove = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 12)).foregroundStyle(DS.danger)
                        .disabled(m.busy)
                }
            }
            HStack(spacing: 10) {
                targetTile(.production)
                targetTile(.testCopy)
            }
            Text(t("target.hint"))
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .padding(.leading, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func targetTile(_ tgt: Target) -> some View {
        let on = m.target == tgt
        let s = m.statuses[tgt] ?? AppStatus()
        let needsPick = (tgt == .testCopy && !m.exists(tgt))
        return Button { m.target = tgt } label: {
            HStack(spacing: 11) {
                tileIcon(tgt)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tgt.label).font(.system(size: 14, weight: .semibold))
                    Text(m.displayPath(tgt))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                ZStack {
                    Circle().fill(tgt.tint).frame(width: 18, height: 18)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                }
                .opacity(on && !needsPick ? 1 : 0)
                .scaleEffect(on && !needsPick ? 1 : 0.6)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(DS.tile)
        }
        .buttonStyle(.plain)
        .background {
            DS.tile.fill(tgt.tint.opacity(on ? 0.22 : 0))
                .overlay(DS.tile.strokeBorder(tgt.tint.opacity(on ? 0.9 : 0), lineWidth: 2))
                .shadow(color: tgt.tint.opacity(on ? 0.22 : 0), radius: 7, y: 4)
        }
        .glassEffect(.regular, in: DS.tile)
        .opacity(s.missing && !needsPick ? 0.55 : 1)
        .animation(DS.ease24, value: on)
    }

    @ViewBuilder
    private func tileIcon(_ tgt: Target) -> some View {
        if m.exists(tgt) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: m.fullPath(tgt)))
                .resizable().frame(width: 34, height: 34)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                Image(systemName: tgt == .testCopy ? "plus" : "questionmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 34, height: 34)
        }
    }

    // MARK: 字体

    /// 字号行。用 size-adjust 实现，所以调的是「被替换的那些字符显示多大」，
    /// 不是整页缩放——图标、间距、未替换的文字都不动。
    private func scaleRow(_ title: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 14) {
            Text(title).font(.system(size: 14))
            Spacer()
            Slider(value: value, in: 80...150, step: 5)
                .frame(width: 190)
            Text("\(Int(value.wrappedValue))%")
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(value.wrappedValue == 100 ? .secondary : .primary)
                .frame(width: 42, alignment: .trailing)
                .monospacedDigit()
            Button {
                withAnimation(DS.ease) { value.wrappedValue = 100 }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .disabled(value.wrappedValue == 100)
            .help(t("font.reset"))
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    /// 代码块字体。走 CDS 的 mono token，只影响代码块与行内代码。
    /// 「保持不变」= 空字符串，此时完全不注入相关规则。
    private var codeGroup: some View {
        VStack(alignment: .leading, spacing: 7) {
            GroupLabel(text: t("code.group"))
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t("code.font")).font(.system(size: 14))
                        Text(t("code.desc"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $m.fontMono) {
                        Text(t("code.keep")).tag("")
                        Divider()
                        ForEach(m.monoFonts) { f in
                            Text("\(fontRowTitle(f))   \(Text("Aa01").font(.custom(f.family, size: 14)))")
                                .tag(f.family)
                        }
                    }
                    .pickerStyle(.menu).labelsHidden().font(.system(size: 13))
                    .frame(maxWidth: 260)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)

                if !m.fontMono.isEmpty {
                    Divider().opacity(0.5).transition(.opacity)
                    scaleRow(t("code.size"), $m.fontMonoScale)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .glassEffect(.regular, in: DS.card)
        }
    }

    /// 底色预设。#F0EEE6 是照旧版 Claude 的暖米色取的；另两个更淡，
    /// 给觉得米黄太重的人。空字符串 = 不改。
    private static let bgPresets: [(String, String)] = [
        ("", "look.bg.off"), ("#F0EEE6", ""), ("#F7F4EC", ""), ("#F2F1EC", ""),
    ]

    private var lookGroup: some View {
        VStack(alignment: .leading, spacing: 7) {
            GroupLabel(text: t("look.group"))
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t("look.bg")).font(.system(size: 14))
                        Text(t("look.bg.desc"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        ForEach(Self.bgPresets, id: \.0) { hex, key in
                            bgSwatch(hex, label: key.isEmpty ? nil : t(key))
                        }
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: UInt32(m.bgColor.dropFirst(), radix: 16) ?? 0xF0EEE6) },
                            set: { m.bgColor = $0.hexString }))
                            .labelsHidden()
                            .help(t("look.bg.custom"))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 11)

            }
            .glassEffect(.regular, in: DS.card)
        }
    }

    private func bgSwatch(_ hex: String, label: String?) -> some View {
        let selected = m.bgColor.uppercased() == hex.uppercased()
        return Button {
            withAnimation(DS.ease) { m.bgColor = hex }
        } label: {
            ZStack {
                if hex.isEmpty {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                    Image(systemName: "slash.circle")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(hex: UInt32(hex.dropFirst(), radix: 16) ?? 0))
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                }
                if selected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(DS.accent, lineWidth: 2)
                }
            }
            .frame(width: 30, height: 26)
        }
        .buttonStyle(.plain)
        .help(label ?? hex)
    }

    private var fontGroup: some View {
        VStack(alignment: .leading, spacing: 7) {
            GroupLabel(text: t("font.group"))
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t("font.scope")).font(.system(size: 14))
                        Text(t("font.scope.desc"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    GlassSwitch(selection: $m.scope,
                                options: [SwitchOption(value: "cjk", label: t("font.scope.cjk")),
                                          SwitchOption(value: "latin", label: t("font.scope.latin")),
                                          SwitchOption(value: "both", label: t("font.scope.both"))])
                        .frame(width: 220)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)

                if m.replacesCJK {
                    Divider().opacity(0.5)
                        .transition(.opacity)
                    HStack(spacing: 16) {
                        Text(t("font.cjk")).font(.system(size: 14))
                        Spacer()
                        fontMenu(selection: $m.fontFamily, list: m.fonts)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .transition(.move(edge: .top).combined(with: .opacity))

                    Divider().opacity(0.5).transition(.opacity)
                    scaleRow(t("font.cjk.size"), $m.fontScale)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if m.replacesLatin {
                    Divider().opacity(0.5)
                        .transition(.opacity)
                    HStack(spacing: 16) {
                        Text(t("font.latin")).font(.system(size: 14))
                        Spacer()
                        fontMenu(selection: $m.fontLatin, list: m.latinFonts)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .transition(.move(edge: .top).combined(with: .opacity))

                    Divider().opacity(0.5).transition(.opacity)
                    scaleRow(t("font.latin.size"), $m.fontScaleLatin)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Divider().opacity(0.5)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t("font.mode")).font(.system(size: 14))
                        Text(t("font.mode.desc"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    GlassSwitch(selection: $m.mode,
                                options: [SwitchOption(value: "auto", label: t("font.mode.std")),
                                          SwitchOption(value: "brute", label: t("font.mode.ext"))])
                        .frame(width: 170)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)

                Divider().opacity(0.5)

                VStack(alignment: .leading, spacing: 6) {
                    Text(t("font.preview.label")).font(.system(size: 11)).foregroundStyle(.secondary)
                    previewLine
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .glassEffect(.regular, in: DS.card)
        }
        .disabled(m.busy)
    }

    /// 预览按分组分别用各自的字体渲染，没被替换的那部分保持系统字体，
    /// 所见即所得。
    private var previewLine: some View {
        // 预览里也按字号缩放，这样拖滑块能立刻看出效果
        let cjkSize = 20 * m.fontScale / 100
        let latinSize = 20 * m.fontScaleLatin / 100
        let cjk = Text(t("font.preview.cjk"))
            .font(m.replacesCJK ? .custom(m.fontFamily, size: cjkSize)
                                : .system(size: 20))
        let latin = Text("  ABCDE abcde 1234567890")
            .font(m.replacesLatin && !m.fontLatin.isEmpty
                  ? .custom(m.fontLatin, size: latinSize) : .system(size: 20))
        return Text("\(cjk)\(latin)")
    }

    /// 系统 pop-up button：右侧蓝色上下箭头方块、选中项打勾都是原生的，
    /// 和设计稿里画的那颗按钮是同一个东西。每行右侧用该字体渲染一个「字」。
    private func fontMenu(selection: Binding<String>, list: [FontChoice]) -> some View {
        Picker("", selection: selection) {
            ForEach(list) { f in
                Text("\(fontRowTitle(f))   \(Text(t("font.sample")).font(.custom(f.family, size: 15)))")
                    .tag(f.family)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(.system(size: 13))
        .frame(width: 210)
    }

    private func fontRowTitle(_ f: FontChoice) -> String {
        if let loc = f.localized { return "\(loc)  \(f.family)" }
        return f.family
    }

    // MARK: 按钮行

    private var actions: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button { m.install() } label: {
                    Text(t(m.current.patched ? "action.reapply" : "action.apply",
                         ["{target}": m.target.label]))
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 38)
                }
                .buttonStyle(.glassProminent).tint(DS.accent)
                .buttonBorderShape(.capsule)
                .keyboardShortcut(.defaultAction)
                .disabled(busyNow || !m.exists(m.target))

                Button { m.doctor() } label: {
                    Text(t("action.doctor")).font(.system(size: 14))
                        .frame(height: 38).padding(.horizontal, 20)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .disabled(busyNow || !m.exists(m.target))

                Button { m.openTarget() } label: {
                    Text(t("action.open")).font(.system(size: 14))
                        .frame(height: 38).padding(.horizontal, 20)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .disabled(busyNow || !m.exists(m.target))

                DestructiveButton(title: t("action.restore")) { confirmRestore = true }
                    .disabled(busyNow || !m.exists(m.target))
            }
        }
        .padding(.top, 2)
    }

    private var busyRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(m.busyLabel).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .glassEffect(.regular, in: Capsule())
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: 日志

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().opacity(0.5)
            HStack(spacing: 14) {
                Button(logOpen ? t("log.hide") : t("log.show", ["{n}": String(m.logLines.count)])) {
                    logOpen.toggle()
                }
                .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(DS.accent)

                if logOpen && !m.logLines.isEmpty {
                    Button(t("log.clear")) { m.log = "" }
                        .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 7) {
                    BreathingDot()
                    Text(t("log.guard"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }

            if logOpen {
                ScrollViewReader { sp in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            if m.logLines.isEmpty {
                                Text(t("log.cleared"))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            ForEach(Array(m.logLines.enumerated()), id: \.offset) { i, line in
                                logRow(line).id(i)
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                    .frame(maxHeight: 150)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onChange(of: m.log) { _, _ in sp.scrollTo("end", anchor: .bottom) }
                }
            }
        }
    }

    private func logRow(_ line: String) -> some View {
        let markers = ["✓", "✗", "·", "▸"]
        let first = line.first.map(String.init) ?? "·"
        let known = markers.contains(first)
        let body = known ? String(line.dropFirst()).trimmingCharacters(in: .whitespaces) : line
        let color: Color = first == "✓" ? DS.success
                         : first == "✗" ? DS.danger
                         : first == "▸" ? DS.accent : .secondary
        return HStack(alignment: .top, spacing: 8) {
            Text(known ? first : "·").foregroundStyle(known ? color : Color.secondary)
            Text(body).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 教程

    /// 纯色遮罩：窗口内的模糊由内容自己 .blur 做，
    /// .ultraThinMaterial 在 macOS 上只模糊窗口背后的桌面，会糊成一块灰板
    private func scrim(_ dismiss: @escaping () -> Void) -> some View {
        Color(hex: 0x14161E).opacity(0.22)
            .frame(width: 900, height: 1400)
            .onTapGesture(perform: dismiss)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Circle().fill(Color.secondary.opacity(0.45))
                .frame(width: 3.5, height: 3.5).padding(.top, 6.5)
            Text(text)
                .font(.system(size: 12.5)).foregroundStyle(.secondary)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 教程开头的安全性说明。只陈述可在代码里查证的事实，不对
    /// Anthropic 的账号处置作任何承诺。
    private var safetyNote: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(DS.success.opacity(0.15)).frame(width: 22, height: 22)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.success)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(t("help.safety.title")).font(.system(size: 14, weight: .semibold))
                bullet(t("help.safety.b1"))
                bullet(t("help.safety.b2"))
                bullet(t("help.safety.b3"))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(DS.success.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(DS.success.opacity(0.18), lineWidth: 1))
    }

    /// 分节标题。教程按「开始使用 / 各项设置 / 日常维护」分三段——
    /// 前三步是上手路径，中间五项各讲一个功能，最后三条是长期会用到的。
    private func helpSection(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.66)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }

    private func helpStep<C: View>(_ n: Int, _ title: String, _ body: String,
                                   @ViewBuilder extra: () -> C) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(DS.accent.opacity(0.14)).frame(width: 22, height: 22)
                Text("\(n)")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(body)
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
                extra()
            }
        }
    }

    private func helpStep(_ n: Int, _ title: String, _ body: String) -> some View {
        helpStep(n, title, body) { EmptyView() }
    }

    private var helpSheet: some View {
        ZStack {
            scrim { showHelp = false }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(t("help.title"))
                        .font(.system(size: 17, weight: .semibold)).tracking(-0.17)
                    Spacer()
                    Button { showHelp = false } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 16)

                Divider().opacity(0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        safetyNote

                        helpSection(t("help.sec.start"))
                        helpStep(1, t("help.step1.title"), t("help.step1.body"))

                        helpStep(2, t("help.step2.title"), t("help.step2.body")) {
                            ActionLine(lead: t("help.a2.lead"), tail: t("help.a2.tail")) {
                                BtnChip(title: t("target.create"), kind: .link)
                            }
                        }

                        helpStep(3, t("help.step3.title"), t("help.step3.body")) {
                            ActionLine(lead: t("help.a4.lead")) {
                                BtnChip(title: t("action.apply", ["{target}": t("target.prod")]),
                                        kind: .primary)
                            }
                        }

                        helpSection(t("help.sec.settings"))
                        helpStep(4, t("help.step4.title"), t("help.step4.body")) {
                            ActionLine(lead: t("font.scope")) {
                                SegChip(options: [t("font.scope.cjk"), t("font.scope.latin"),
                                                  t("font.scope.both")], selected: 0)
                            }
                        }

                        helpStep(5, t("help.step5.title"), t("help.step5.body"))
                        helpStep(6, t("help.step6.title"), t("help.step6.body"))
                        helpStep(7, t("help.step7.title"), t("help.step7.body"))

                        helpStep(8, t("help.step8.title"), t("help.step8.body")) {
                            ActionLine(lead: t("font.mode")) {
                                SegChip(options: [t("font.mode.std"), t("font.mode.ext")], selected: 0)
                            }
                        }

                        helpSection(t("help.sec.daily"))
                        helpStep(9, t("help.step9.title"), t("help.step9.body")) {
                            ActionLine(lead: t("help.a4.lead")) {
                                BtnChip(title: t("stale.action"), kind: .primary)
                            }
                        }

                        helpStep(10, t("help.step10.title"), t("help.step10.body")) {
                            ActionLine(lead: t("help.a4.lead")) {
                                HStack(spacing: 6) {
                                    BtnChip(title: t("action.restore"), kind: .danger)
                                    BtnChip(title: t("action.doctor"), kind: .glass)
                                }
                            }
                        }

                        helpStep(11, t("help.step11.title"), t("help.step11.body"))
                    }
                    .padding(.horizontal, 24).padding(.vertical, 20)
                }
                .frame(maxHeight: 440)

                Divider().opacity(0.5)

                HStack {
                    Text(t("help.footer"))
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                    Button(t("sheet.ok")) { showHelp = false }
                        .buttonStyle(.glassProminent).tint(DS.accent).controlSize(.large)
                }
                .padding(.horizontal, 24).padding(.vertical, 14)
            }
            .frame(width: 560)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 25, y: 22)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    // MARK: 新特性

    private func noteBlock(_ n: ReleaseNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(t("release.version", ["{v}": n.version])).font(.system(size: 14, weight: .semibold))
                if n.version == appVersion {
                    Text(t("release.current"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(DS.accent)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(DS.accent.opacity(0.12)))
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(n.changes.enumerated()), id: \.offset) { _, c in
                    bullet(c)
                }
            }
            if let a = n.action {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "hand.point.right.fill")
                        .font(.system(size: 11)).foregroundStyle(DS.prod)
                        .padding(.top, 2)
                    Text(a)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineSpacing(2.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.prod.opacity(0.09)))
            }
        }
    }

    private var whatsNewSheet: some View {
        ZStack {
            scrim { showWhatsNew = false }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(DS.accent)
                        Text(t("header.whatsnew")).font(.system(size: 17, weight: .semibold)).tracking(-0.17)
                    }
                    Spacer()
                    Button { showWhatsNew = false } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 16)

                Divider().opacity(0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(releaseNotes) { noteBlock($0) }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 20)
                }
                .frame(maxHeight: 380)

                Divider().opacity(0.5)

                HStack {
                    UpdateCheckButton()
                    Spacer()
                    Button(t("sheet.ok")) { showWhatsNew = false }
                        .buttonStyle(.glassProminent).tint(DS.accent).controlSize(.large)
                }
                .padding(.horizontal, 24).padding(.vertical, 14)
            }
            .frame(width: 520)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 25, y: 22)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    // MARK: 还原确认

    private var restoreSheet: some View {
        ZStack {
            scrim { confirmRestore = false }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 13) {
                    ZStack {
                        Circle().fill(DS.danger.opacity(0.16)).frame(width: 34, height: 34)
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(DS.danger)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(t("sheet.restore.title"))
                            .font(.system(size: 15, weight: .semibold)).tracking(-0.15)
                        Text(t("sheet.restore.body",
                               ["{target}": m.target.label,
                                "{font}": m.current.font.isEmpty ? m.fontFamily : m.current.font]))
                            .font(.system(size: 12.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(m.current.backups.first.map { t("sheet.restore.backup", ["{name}": $0]) }
                     ?? t("sheet.restore.nobackup"))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9)
                        .fill(Color.secondary.opacity(0.09)))
                HStack(spacing: 9) {
                    Spacer()
                    Button(t("sheet.cancel")) { confirmRestore = false }
                        .buttonStyle(.glass).controlSize(.large)
                    Button(t("action.restore")) { confirmRestore = false; m.uninstall() }
                        .buttonStyle(.glassProminent).tint(DS.danger).controlSize(.large)
                }
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
            .frame(width: 392)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 25, y: 22)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }
}

// MARK: - 关于

enum Updater {
    static let repo = "sellshan-jpg/clfont"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    struct Release { let tag: String; let page: URL }

    enum Result {
        case release(Release)
        case noRelease          // 仓库在，但还没发过 Release（GitHub 返回 404）
        case failed(String)
    }

    static func latest() async -> Result {
        guard !repo.isEmpty,
              let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")
        else { return .failed(t("update.err.norepo")) }
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            // 404 既可能是仓库还没发过 Release，也可能是仓库名写错了；
            // 对用户来说结论一样：现在没有可下载的版本。
            if code == 404 { return .noRelease }
            if code == 403 { return .failed(t("update.err.rate")) }
            guard code == 200 else { return .failed(t("update.err.code", ["{code}": String(code)])) }
            guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = j["tag_name"] as? String,
                  let link = j["html_url"] as? String, let page = URL(string: link)
            else { return .failed(t("update.err.parse")) }
            return .release(Release(tag: tag, page: page))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// 1.10 > 1.9：按数字比，不是按字符串
    static func isNewer(_ tag: String, than current: String) -> Bool {
        let a = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        return a.compare(current, options: .numeric) == .orderedDescending
    }
}

/// 启动时在后台静默检查一次新版本。
///
/// 三条原则：一天最多查一次；查失败一声不吭（自动检查不该因为断网打扰用户，
/// 手动「检查更新」仍会如实报错）；同一个版本被「以后再说」掉之后不再提示。
@MainActor
final class UpdateWatcher: ObservableObject {
    @Published var available: Updater.Release?

    private static let interval: TimeInterval = 24 * 3600
    private static let kEnabled = "autoCheckUpdates"
    private static let kLastCheck = "lastUpdateCheck"
    private static let kSkipped = "skippedUpdateTag"

    private let d = UserDefaults.standard

    /// 默认开启；用户可在「关于」里关掉
    var enabled: Bool {
        get { d.object(forKey: Self.kEnabled) as? Bool ?? true }
        set {
            d.set(newValue, forKey: Self.kEnabled)
            if !newValue { available = nil }
            objectWillChange.send()
        }
    }

    func checkIfDue() {
        guard enabled,
              Date().timeIntervalSince1970 - d.double(forKey: Self.kLastCheck) > Self.interval
        else { return }
        Task {
            let result = await Updater.latest()
            // 只有真的问到了答案才记时间戳；断网时留到下次启动再试
            guard case .release(let r) = result else {
                if case .noRelease = result { stampNow() }
                return
            }
            stampNow()
            guard Updater.isNewer(r.tag, than: Updater.version),
                  d.string(forKey: Self.kSkipped) != r.tag else { return }
            withAnimation(DS.ease) { available = r }
        }
    }

    /// 「以后再说」：记下这个版本号，下次有更新的版本才再提示
    func skip() {
        if let tag = available?.tag { d.set(tag, forKey: Self.kSkipped) }
        withAnimation(DS.ease) { available = nil }
    }

    private func stampNow() {
        d.set(Date().timeIntervalSince1970, forKey: Self.kLastCheck)
    }
}

/// 检查更新按钮：自带状态，结果就地显示。关于窗口与「新特性」共用。
struct UpdateCheckButton: View {
    /// true = 关于窗口里的整行按钮；false = 弹层底部的紧凑样式
    var fullWidth = false

    @State private var checking = false
    @State private var note = ""
    @State private var newRelease: Updater.Release?

    var body: some View {
        Group {
            if fullWidth {
                VStack(spacing: 12) { button; noteText }
            } else {
                HStack(spacing: 10) { button; noteText }
            }
        }
    }

    @ViewBuilder private var button: some View {
        if let r = newRelease {
            Button { NSWorkspace.shared.open(r.page) } label: { label(t("update.download")) }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule).tint(DS.accent)
        } else {
            Button { check() } label: { label(t("update.check")) }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .disabled(checking)
        }
    }

    @ViewBuilder private var noteText: some View {
        if !note.isEmpty {
            Text(note)
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .multilineTextAlignment(fullWidth ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func label(_ title: String) -> some View {
        HStack(spacing: 6) {
            if checking { ProgressView().controlSize(.small) }
            Text(title).font(.system(size: 13, weight: .medium))
        }
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .frame(height: fullWidth ? 32 : 26)
        .padding(.horizontal, fullWidth ? 0 : 12)
    }

    private func check() {
        guard !Updater.repo.isEmpty else {
            note = t("update.norepo")
            return
        }
        checking = true; note = ""
        Task {
            defer { checking = false }
            // 手动查过就算今天查过了，启动时不必再查一遍
            UserDefaults.standard.set(Date().timeIntervalSince1970,
                                      forKey: "lastUpdateCheck")
            switch await Updater.latest() {
            case .release(let r):
                if Updater.isNewer(r.tag, than: Updater.version) {
                    newRelease = r
                    note = t("update.found", ["{tag}": r.tag])
                } else {
                    note = t("update.latest")
                }
            case .noRelease:
                note = t("update.norelease")
            case .failed(let why):
                note = t("update.failed", ["{why}": why])
            }
        }
    }
}

struct AboutView: View {
    /// 只为让开关能刷新界面；实际读写走 UserDefaults
    @AppStorage("autoCheckUpdates") private var autoCheck = true
    @ObservedObject private var copy = Copy.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 96, height: 96)
                VStack(spacing: 3) {
                    Text("Clfont").font(.system(size: 22, weight: .semibold)).tracking(-0.2)
                    Text(t("about.version", ["{v}": Updater.version, "{b}": Updater.build]))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text(t("about.tagline"))
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 20)

            Divider().opacity(0.5)

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text(t("about.dev")).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text(t("about.devname")).font(.system(size: 12.5, weight: .medium))
                }

                HStack(spacing: 8) {
                    Text(t("about.lang")).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $copy.lang) {
                        Text(t("about.lang.auto")).tag(Lang.auto)
                        Text("中文").tag(Lang.zh)
                        Text("English").tag(Lang.en)
                    }
                    .pickerStyle(.menu).labelsHidden().fixedSize()
                    .font(.system(size: 12.5))
                }

                Toggle(t("update.auto"), isOn: $autoCheck)
                    .toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 12.5))

                UpdateCheckButton(fullWidth: true)
            }
            .padding(.horizontal, 28).padding(.vertical, 18)

            Divider().opacity(0.5)

            Text(t("about.footer"))
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .padding(.horizontal, 28).padding(.vertical, 12)
        }
        .frame(width: 360)
        .background { Color(nsColor: .windowBackgroundColor).ignoresSafeArea() }
    }
}

private struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(t("about.title")) { openWindow(id: "about") }
    }
}

@main
struct ClfontApp: App {
    var body: some Scene {
        WindowGroup("Clfont") { ContentView() }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
            .commands {
                CommandGroup(replacing: .appInfo) { AboutCommand() }
            }

        Window(t("about.title"), id: "about") { AboutView() }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
    }
}
