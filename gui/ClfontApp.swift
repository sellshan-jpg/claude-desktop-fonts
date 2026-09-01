import SwiftUI
import AppKit

// clfont GUI（macOS 26）
// 界面按 design_handoff_clfont_ui/README.md 的方案 1a 实现。
// 只调用打包在 bundle 里的 clfont CLI；备份、重打包、重签、冒烟测试、失败回滚
// 全部由 CLI 负责，GUI 自己不碰 Claude.app 的任何文件。

// MARK: - 设计 tokens

extension Color {
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

// MARK: - 更新说明

/// 面向用户的更新说明：只说「改了什么」和「你要做什么」，不堆术语。
struct ReleaseNote: Identifiable {
    let version: String
    let changes: [String]
    /// 需要用户配合的动作；没有就留空
    let action: String?
    var id: String { version }
}

let releaseNotes: [ReleaseNote] = [
    ReleaseNote(
        version: "5.1",
        changes: [
            "修复替换英文时，侧边栏、输入框等区域字体不跟随变化的问题。",
            "修复 Claude 思考过程文本字体偶发不跟随变化的问题。",
        ],
        action: "若此前已为 Claude 应用过字体，需重新执行一次「应用」，本次修复方可生效。"),
    ReleaseNote(
        version: "5.0",
        changes: [
            "支持替换中文、英文或中英文，中英文字体可分别指定。",
            "提供测试 Claude，可在改动日常使用的应用之前先确认效果。",
            "支持随时还原，并在备份可用时一并恢复 Claude 的原始签名。",
        ],
        action: nil),
]

// MARK: - 开发者工具

enum Toolchain {
    /// clfont 的实际操作由一段 Python 脚本完成，而 `/usr/bin/python3` 是 Xcode
    /// 命令行工具的转发壳（和 git 一样 118KB）——没装 CLT 时它只会弹系统安装
    /// 提示，脚本根本起不来。所以这道检查必须在 GUI 层做：CLI 里那道检查等不到
    /// 执行的机会。（codesign 相反，是系统自带的真二进制，不依赖 CLT。）
    ///
    /// 用 `xcode-select -p` 探测，而不是直接跑 python3：前者不会触发安装弹窗，
    /// 不至于每次启动都打扰用户。
    static func ready() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        p.arguments = ["-p"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// 触发系统自带的安装流程（弹 Apple 的安装对话框，不需要下载 Xcode）
    static func requestInstall() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        p.arguments = ["--install"]
        try? p.run()
    }
}

// MARK: - 目标

enum Target: String, CaseIterable, Identifiable {
    case production, testCopy
    var id: String { rawValue }
    var label: String { self == .production ? "正式 Claude" : "测试 Claude" }
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
    @Published var fonts: [FontChoice] = []
    @Published var latinFonts: [FontChoice] = []

    /// 备份统计按目标缓存：切回来时立刻有内容，不必重新扫盘
    @Published var backupInfo: [Target: (summary: String, prunable: Int)] = [:]
    @Published var backupLoading: Set<Target> = []
    @Published var toolsReady = true

    func checkTools() { toolsReady = Toolchain.ready() }

    var replacesCJK: Bool { scope == "cjk" || scope == "both" }
    var replacesLatin: Bool { scope == "latin" || scope == "both" }
    @Published var statuses: [Target: AppStatus] = [:]
    var current: AppStatus { statuses[target] ?? AppStatus() }

    /// nil = 用 CLI 的默认目标（/Applications/Claude.app）
    func cliPath(_ t: Target) -> String? {
        t == .production ? nil : Paths.testApp
    }
    func fullPath(_ t: Target) -> String {
        t == .production ? "/Applications/Claude.app" : Paths.testApp
    }
    func exists(_ t: Target) -> Bool {
        FileManager.default.fileExists(atPath: fullPath(t))
    }
    func displayPath(_ t: Target) -> String {
        if t == .production { return "/Applications/Claude.app" }
        return exists(t) ? "~/Library/Application Support/clfont" : "尚未创建，点击右上角创建"
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
        if !fonts.contains(where: { $0.family == fontFamily }), let f = fonts.first {
            fontFamily = f.family
        }
        if fontLatin.isEmpty || !latinFonts.contains(where: { $0.family == fontLatin }) {
            fontLatin = latinFonts.first?.family ?? ""
        }
    }

    func fontChoice(_ family: String) -> FontChoice? {
        (fonts + latinFonts).first { $0.family == family }
    }

    func loadConfig() {
        guard let d = try? Data(contentsOf: configURL),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        fontFamily = j["font"] as? String ?? fontFamily
        fontLatin = j["font_latin"] as? String ?? fontLatin
        scope = j["scope"] as? String ?? scope
        mode = j["mode"] as? String ?? mode
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

    private func exec(_ args: [String], on t: Target, label: String, stream: Bool = true,
                      done: (@MainActor (Int32, String) -> Void)? = nil) {
        var a = args
        if let tp = cliPath(t) { a = ["--app", tp] + a }
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        if t == .testCopy {
            // 装补丁时的启动测试用独立配置目录，别去动用户正在用的那份
            env["CLFONT_SMOKE_USER_DATA_DIR"] = Paths.smokeProfile
        }
        spawn(exe: cli, args: a, env: env, label: label, stream: stream,
              echo: "clfont \(args.joined(separator: " "))  →  \(t.label)", done: done)
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
            log += "✗ 启动 CLI 失败：\(error.localizedDescription)\n"
            busy = false; busyLabel = ""
        }
    }

    /// 读取某个目标的状态并单独存起来
    func refresh(_ t: Target, then: (@MainActor () -> Void)? = nil) {
        guard exists(t) else {
            statuses[t] = AppStatus(loaded: true, missing: true)
            then?(); return
        }
        exec(["status"], on: t, label: "读取\(t.label)状态", stream: false) { [weak self] _, out in
            guard let self else { return }
            var s = AppStatus()
            s.loaded = true
            s.raw = out
            s.patched = out.contains("已打补丁")
            s.signOK = !out.contains("codesign -v：未通过")
            s.integrityOK = !out.contains("asar 完整性哈希：不匹配")
            if let r = out.range(of: "Claude 版本：") {
                s.version = String(out[r.upperBound...].prefix { !$0.isNewline })
                    .trimmingCharacters(in: .whitespaces)
            }
            if let r = out.range(of: "整包备份：") {
                let line = String(out[r.upperBound...].prefix { !$0.isNewline })
                    .trimmingCharacters(in: .whitespaces)
                s.backups = line == "无" ? [] : line.components(separatedBy: "、")
            }
            if let r = out.range(of: "字体 ") {
                s.font = String(out[r.upperBound...].prefix { $0 != "，" && !$0.isNewline })
            }
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            s.checkedAt = f.string(from: Date())
            self.statuses[t] = s
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
    func loadBackups(_ t: Target, force: Bool = false) {
        guard exists(t) else { backupInfo[t] = ("", 0); return }
        if !force, backupInfo[t] != nil { return }
        guard !backupLoading.contains(t) else { return }
        backupLoading.insert(t)
        var args = ["backups"]
        if let tp = cliPath(t) { args = ["--app", tp] + args }
        runQuiet(args) { [weak self] out in
            guard let self else { return }
            self.backupLoading.remove(t)
            var summary = ""
            var prunable = 0
            for raw in out.split(separator: "\n") where raw.contains("合计 ") {
                let line = String(raw)
                if let a = line.range(of: "合计 "), let b = line.range(of: "），其中") {
                    summary = String(line[a.upperBound..<b.lowerBound])
                        .replacingOccurrences(of: "（", with: " · ")
                }
                if let a = line.range(of: "其中 "), let b = line.range(of: " 份可清理") {
                    prunable = Int(line[a.upperBound..<b.lowerBound]) ?? 0
                }
            }
            self.backupInfo[t] = (summary, prunable)
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

    func pruneBackups(_ t: Target) {
        exec(["backups", "--prune", "-y"], on: t, label: "清理旧备份") {
            [weak self] _, _ in self?.loadBackups(t, force: true)
        }
    }

    func install() {
        saveConfig()
        let t = target
        exec(["install", "-y", "--scope", scope, "--mode", mode], on: t,
             label: "安装到「\(t.label)」：备份 → 重打包 → 重签名 → 启动测试（约 1–2 分钟）") {
            [weak self] _, _ in self?.refresh(t)
        }
    }

    func uninstall() {
        let t = target
        exec(["uninstall", "-y"], on: t, label: "还原「\(t.label)」：恢复原文件 → 重签名") {
            [weak self] _, _ in self?.refresh(t)
        }
    }

    func doctor() {
        let t = target
        exec(["doctor"], on: t, label: "自检「\(t.label)」") { [weak self] _, _ in self?.refresh(t) }
    }

    /// 重建测试副本：从正式版复制一份，换独立身份、去掉 claude:// 注册，
    /// 并把登录态播种过去。脚本随 app 打包在 Resources 里。
    func rebuildTestCopy() {
        guard let script = Bundle.main.path(forResource: "setup-test-copy", ofType: "sh") else {
            log += "\n✗ 找不到 setup-test-copy.sh\n"
            return
        }
        spawn(exe: "/bin/bash", args: [script],
              env: ProcessInfo.processInfo.environment,
              label: "创建测试副本：复制 → 换独立身份 → 重签名 → 播种登录态",
              stream: true, echo: "bash setup-test-copy.sh") { [weak self] _, _ in
            self?.refresh(.testCopy)
        }
    }

    /// 彻底移除测试 Claude：应用副本、配置目录、它自己的整包备份。
    func removeTestCopy() {
        guard let script = Bundle.main.path(forResource: "remove-test-copy", ofType: "sh") else {
            log += "\n✗ 找不到 remove-test-copy.sh\n"
            return
        }
        spawn(exe: "/bin/bash", args: [script],
              env: ProcessInfo.processInfo.environment,
              label: "移除测试 Claude：删除副本、配置目录与它的备份",
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
            log += "\n· 已启动测试 Claude（独立配置目录）\n"
        } catch {
            log += "\n✗ 启动测试 Claude 失败：\(error.localizedDescription)\n"
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

    private var sheetOpen: Bool { confirmRestore || showHelp || showWhatsNew }

    var body: some View {
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
        .ignoresSafeArea(edges: .top)
        .onAppear { m.checkTools(); m.loadFonts(); m.loadConfig(); m.refreshAll() }
        .animation(DS.ease24, value: m.target)
        .animation(DS.pop, value: m.scope)
        .animation(DS.pop, value: m.toolsReady)
        .onChange(of: m.target) { _, t in
            if detailOpen { m.loadBackups(t) }   // 有缓存就直接用，不再扫盘
        }
        .animation(DS.ease24, value: m.busy)
        .animation(DS.pop, value: detailOpen)
        .animation(DS.pop, value: logOpen)
        .animation(DS.pop, value: confirmRestore)
        .animation(DS.pop, value: showHelp)
        .animation(DS.pop, value: showWhatsNew)
        .alert("彻底删除测试 Claude？", isPresented: $confirmRemove) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { m.removeTestCopy() }
        } message: {
            Text("将删除测试 Claude 的应用副本、它的配置目录，以及它在 clfont 数据目录中的"
                 + "整包备份，可释放约 1 GB 空间。\n\n"
                 + "正式 Claude 及其备份不受影响。之后仍可随时重新创建。")
        }
        .alert("创建测试 Claude？", isPresented: $confirmRebuild) {
            Button("取消", role: .cancel) {}
            Button("创建", role: .destructive) { m.rebuildTestCopy() }
        } message: {
            Text("将从正式 Claude 复制一份副本，替换为独立的应用标识，并把当前的登录"
                 + "状态复制过去，因此无需重新登录。副本使用独立的配置目录，"
                 + "在其上进行的任何操作都不会影响正式 Claude。\n\n"
                 + "若副本已存在，将被删除后重新创建。")
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

    /// 没有命令行工具时，任何修改都执行不了——直接挡在最前面，并给一键安装入口。
    private var toolchainNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(DS.prod.opacity(0.16)).frame(width: 22, height: 22)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(DS.prod)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("需要先安装 Xcode 命令行工具")
                    .font(.system(size: 14, weight: .semibold))
                Text("Clfont 的实际操作由一段脚本完成，它依赖 macOS 的 python3，"
                     + "而该组件由 Xcode 命令行工具提供。未安装时无法执行任何修改，"
                     + "你的 Claude 也不会被改动。")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("安装命令行工具") { Toolchain.requestInstall() }
                        .buttonStyle(.glassProminent).tint(DS.prod)
                        .buttonBorderShape(.capsule)
                    Button("我已安装，重新检测") { m.checkTools() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12)).foregroundStyle(DS.accent)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(DS.prod.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(DS.prod.opacity(0.22), lineWidth: 1))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            appHeader
            if !m.toolsReady { toolchainNotice }
            statusCard
            targetGroup
            fontGroup
            actions
            if m.busy { busyRow }
            logSection
            VStack(alignment: .leading, spacing: 5) {
                Text("Clfont 仅在本机修改 Claude 的字体渲染：注入内容只有字体规则，"
                     + "不改动任何网络请求，也不读取账号信息与聊天记录。")
                Text("安装会先退出该 Claude，全程有完整备份；失败或中途取消都会自动回滚，"
                     + "随时可一键还原。重签名后首次启动可能要求重新授权钥匙串，属正常现象。")
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
                Text("使用 Clfont，在 Claude 里安全地使用你喜欢的中英文字体")
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
                        Text("新特性").font(.system(size: 13))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.accent)

                Button { showHelp = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 13, weight: .medium))
                        Text("如何使用").font(.system(size: 13))
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
                    Button(detailOpen ? "收起" : "详情") {
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
                    DetailRow(label: "asar 完整性",
                              value: s.integrityOK ? "匹配" : "不匹配", bad: !s.integrityOK)
                    DetailRow(label: "codesign",
                              value: s.signOK ? "通过" : "未通过", bad: !s.signOK)
                    DetailRow(label: "整包备份",
                              value: s.backups.isEmpty ? "无" : "\(s.backups.count) 份")
                    DetailRow(label: "磁盘剩余", value: m.diskFree)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12).padding(.bottom, 10)

                HStack(spacing: 8) {
                    Text("备份占用").font(.system(size: 12)).foregroundStyle(.secondary)
                    let info = m.backupInfo[m.target]
                    if m.backupLoading.contains(m.target) {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    } else {
                        Text(info?.summary.isEmpty == false ? info!.summary : "—")
                            .font(.system(size: 12, design: .monospaced))
                    }
                    Spacer()
                    if let n = info?.prunable, n > 0 {
                        Button("清理 \(n) 份旧备份") { m.pruneBackups(m.target) }
                            .buttonStyle(.plain)
                            .font(.system(size: 12)).foregroundStyle(DS.accent)
                            .disabled(m.busy)
                    } else if info?.summary.isEmpty == false {
                        Text("均需保留").font(.system(size: 11.5)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 14)
            }
        }
        .glassEffect(.regular, in: DS.card)
    }

    private func statusHeadline(_ s: AppStatus) -> String {
        if s.missing { return "找不到这个 Claude" }
        if !s.loaded { return "读取中…" }
        if s.patched { return "已应用 " + (s.font.isEmpty ? "字体" : s.font) }
        return "尚未应用，随时可以撤回"
    }

    private func statusSubline(_ s: AppStatus) -> String {
        if s.missing { return m.displayPath(m.target) }
        var parts = [m.target.label, s.version]
        parts.append(s.backups.isEmpty ? "未备份" : "已备份")
        if !s.checkedAt.isEmpty { parts.append("\(s.checkedAt) 检查") }
        return parts.joined(separator: " · ")
    }

    // MARK: 版本选择

    private var targetGroup: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                GroupLabel(text: "选择需要更换字体的 Claude 版本")
                Spacer()
                if !m.exists(.testCopy) {
                    // 还没建的时候一直显示，不用先点卡片才发现有这么个入口
                    Button("创建测试 Claude") { confirmRebuild = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 12)).foregroundStyle(DS.accent)
                        .disabled(m.busy)
                } else if m.target == .testCopy {
                    Button("重建") { confirmRebuild = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 12)).foregroundStyle(DS.accent)
                        .disabled(m.busy)
                    Text("·").font(.system(size: 12)).foregroundStyle(.tertiary)
                    Button("删除") { confirmRemove = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 12)).foregroundStyle(DS.danger)
                        .disabled(m.busy)
                }
            }
            HStack(spacing: 10) {
                targetTile(.production)
                targetTile(.testCopy)
            }
            Text("建议先在测试 Claude 上确认字体效果，再应用到正式 Claude。")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .padding(.leading, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func targetTile(_ t: Target) -> some View {
        let on = m.target == t
        let s = m.statuses[t] ?? AppStatus()
        let needsPick = (t == .testCopy && !m.exists(t))
        return Button { m.target = t } label: {
            HStack(spacing: 11) {
                tileIcon(t)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.label).font(.system(size: 14, weight: .semibold))
                    Text(m.displayPath(t))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                ZStack {
                    Circle().fill(t.tint).frame(width: 18, height: 18)
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
            DS.tile.fill(t.tint.opacity(on ? 0.22 : 0))
                .overlay(DS.tile.strokeBorder(t.tint.opacity(on ? 0.9 : 0), lineWidth: 2))
                .shadow(color: t.tint.opacity(on ? 0.22 : 0), radius: 7, y: 4)
        }
        .glassEffect(.regular, in: DS.tile)
        .opacity(s.missing && !needsPick ? 0.55 : 1)
        .animation(DS.ease24, value: on)
    }

    @ViewBuilder
    private func tileIcon(_ t: Target) -> some View {
        if m.exists(t) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: m.fullPath(t)))
                .resizable().frame(width: 34, height: 34)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                Image(systemName: t == .testCopy ? "plus" : "questionmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 34, height: 34)
        }
    }

    // MARK: 字体

    private var fontGroup: some View {
        VStack(alignment: .leading, spacing: 7) {
            GroupLabel(text: "字体")
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("替换范围").font(.system(size: 14))
                        Text("只换中文最安全；换英文会连同界面文字一起改变")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    GlassSwitch(selection: $m.scope,
                                options: [SwitchOption(value: "cjk", label: "中文"),
                                          SwitchOption(value: "latin", label: "英文"),
                                          SwitchOption(value: "both", label: "中英文")])
                        .frame(width: 220)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)

                if m.replacesCJK {
                    Divider().opacity(0.5)
                        .transition(.opacity)
                    HStack(spacing: 16) {
                        Text("中文字体").font(.system(size: 14))
                        Spacer()
                        fontMenu(selection: $m.fontFamily, list: m.fonts)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if m.replacesLatin {
                    Divider().opacity(0.5)
                        .transition(.opacity)
                    HStack(spacing: 16) {
                        Text("英文字体").font(.system(size: 14))
                        Spacer()
                        fontMenu(selection: $m.fontLatin, list: m.latinFonts)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Divider().opacity(0.5)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("兼容模式").font(.system(size: 14))
                        Text("「标准」不生效时再用「扩展」，会多覆盖一批常见字体")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    GlassSwitch(selection: $m.mode,
                                options: [SwitchOption(value: "auto", label: "标准"),
                                          SwitchOption(value: "brute", label: "扩展")])
                        .frame(width: 170)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)

                Divider().opacity(0.5)

                VStack(alignment: .leading, spacing: 6) {
                    Text("预览").font(.system(size: 11)).foregroundStyle(.secondary)
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
        let cjk = Text("字体是沉默的声音")
            .font(m.replacesCJK ? .custom(m.fontFamily, size: 20) : .system(size: 20))
        let latin = Text("  ABCDE abcde 1234567890")
            .font(m.replacesLatin && !m.fontLatin.isEmpty
                  ? .custom(m.fontLatin, size: 20) : .system(size: 20))
        return Text("\(cjk)\(latin)")
    }

    /// 系统 pop-up button：右侧蓝色上下箭头方块、选中项打勾都是原生的，
    /// 和设计稿里画的那颗按钮是同一个东西。每行右侧用该字体渲染一个「字」。
    private func fontMenu(selection: Binding<String>, list: [FontChoice]) -> some View {
        Picker("", selection: selection) {
            ForEach(list) { f in
                Text("\(fontRowTitle(f))   \(Text("字A").font(.custom(f.family, size: 15)))")
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
                    Text(m.current.patched ? "重新应用到\(m.target.label)"
                                           : "应用到\(m.target.label)")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 38)
                }
                .buttonStyle(.glassProminent).tint(DS.accent)
                .buttonBorderShape(.capsule)
                .keyboardShortcut(.defaultAction)
                .disabled(m.busy || !m.exists(m.target) || !m.toolsReady)

                Button { m.doctor() } label: {
                    Text("自检").font(.system(size: 14))
                        .frame(height: 38).padding(.horizontal, 20)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .disabled(m.busy || !m.exists(m.target) || !m.toolsReady)

                Button { m.openTarget() } label: {
                    Text("打开").font(.system(size: 14))
                        .frame(height: 38).padding(.horizontal, 20)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .disabled(m.busy || !m.exists(m.target) || !m.toolsReady)

                DestructiveButton(title: "还原") { confirmRestore = true }
                    .disabled(m.busy || !m.exists(m.target) || !m.toolsReady)
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
                Button(logOpen ? "隐藏日志" : "显示日志（\(m.logLines.count)）") {
                    logOpen.toggle()
                }
                .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(DS.accent)

                if logOpen && !m.logLines.isEmpty {
                    Button("清除日志") { m.log = "" }
                        .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 7) {
                    BreathingDot()
                    Text("备份保护中，失败自动回滚")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }

            if logOpen {
                ScrollViewReader { sp in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            if m.logLines.isEmpty {
                                Text("日志已清除")
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
                Text("关于安全性").font(.system(size: 14, weight: .semibold))
                bullet("注入内容仅有字体规则（CSS @font-face），不改动任何网络请求，"
                       + "不伪造客户端身份，也不绕过任何限制或配额。")
                bullet("不读取、不上传账号信息与聊天记录，全部操作都在本机完成。")
                bullet("安装前会创建完整备份，任一环节失败或中途取消都会自动回滚，"
                       + "随时可一键还原。")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(DS.success.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(DS.success.opacity(0.18), lineWidth: 1))
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
                    Text("如何使用 Clfont")
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

                        helpStep(1, "首次使用：命令行工具与「App 管理」权限",
                                 "Clfont 的实际操作由一段脚本完成，它依赖 macOS 的 python3，而该组件由 "
                                 + "Xcode 命令行工具提供。未安装时窗口顶部会出现提示，点击其中的"
                                 + "「安装命令行工具」按系统引导完成即可，无需下载完整的 Xcode。\n"
                                 + "此外，修改 Claude 的应用包需要「App 管理」权限，macOS 会在第一次执行"
                                 + "安装时弹出系统请求，请选择「允许」。若此前误选了「不允许」，请前往"
                                 + "「系统设置 → 隐私与安全性 → App 管理」，为 Clfont 打开开关后重新执行。"
                                 + "本工具不需要「辅助功能」权限。")

                        helpStep(2, "建议先在测试 Claude 上验证",
                                 "应用修改需要对 Claude 重新签名，正式版的原始签名会因此被替换。为避免对日常"
                                 + "使用的应用反复改动，建议每次更换字体时先在测试 Claude 上确认效果。测试 "
                                 + "Claude 是正式版的完整副本，使用独立的应用标识与配置目录，与正式版互不影响。") {
                            ActionLine(lead: "在「测试 Claude」卡片上，点击", tail: "，约需 1 分钟") {
                                BtnChip(title: "创建测试 Claude", kind: .link)
                            }
                        }

                        helpStep(3, "选择替换范围与字体",
                                 "「替换范围」决定替换哪种文字。「中文」只改中文字形，界面图标不受影响，"
                                 + "也是推荐选项；「英文」与「中英文」会一并改变界面英文的观感，若之后发现"
                                 + "个别图标显示异常，请改回「中文」。选定范围后在下方选择对应字体，"
                                 + "预览会立即更新。") {
                            VStack(alignment: .leading, spacing: 6) {
                                ActionLine(lead: "替换范围") {
                                    SegChip(options: ["中文", "英文", "中英文"], selected: 0)
                                }
                                ActionLine(lead: "兼容模式", tail: "不生效时再改用「扩展」") {
                                    SegChip(options: ["标准", "扩展"], selected: 0)
                                }
                            }
                        }

                        helpStep(4, "应用到测试 Claude",
                                 "确认「测试 Claude」处于选中状态后执行安装，过程约 1 至 2 分钟，"
                                 + "期间请勿关闭窗口。") {
                            ActionLine(lead: "点击") { BtnChip(title: "应用到测试 Claude", kind: .primary) }
                        }

                        helpStep(5, "启动测试 Claude，确认字体效果",
                                 "首次启动时，系统会请求访问钥匙串「Claude Safe Storage」。请输入 Mac 的"
                                 + "登录密码（即锁屏密码）并选择「始终允许」。该弹窗可能连续出现多次"
                                 + "（实测最多 4 次），每次操作相同，属正常现象；全部允许后，副本会沿用"
                                 + "现有登录状态自动进入。\n"
                                 + "副本可能显示「为了安全，请重新登录」的提示条，可忽略，无需处理。"
                                 + "请仅用它确认字体效果，日常使用仍以正式 Claude 为准。") {
                            ActionLine(lead: "点击") { BtnChip(title: "打开", kind: .glass) }
                        }

                        helpStep(6, "应用到正式 Claude",
                                 "效果确认无误后，切换回「正式 Claude」卡片，再次执行安装。") {
                            ActionLine(lead: "点击") { BtnChip(title: "应用到正式 Claude", kind: .primary) }
                        }

                        helpStep(7, "安装流程与失败处理",
                                 "安装依次执行：退出目标应用 → 创建完整备份 → 重新打包 → 更新完整性哈希 → "
                                 + "重新签名 → 启动验证。任一环节失败或中途取消，都会自动回滚至原始状态并重新"
                                 + "验证签名，因此最坏的结果是「未能应用」，而非应用无法启动。")

                        helpStep(8, "Claude 更新后需重新应用",
                                 "Claude 自动更新会覆盖已应用的修改。此时状态区域会提示此前的修改可能已被"
                                 + "更新覆盖，重新执行一次安装即可。")

                        helpStep(9, "还原与自检",
                                 "如需撤销修改，使用「还原」；若能匹配到当前版本的完整备份，Anthropic 的原始"
                                 + "签名会一并恢复。遇到异常时使用「自检」，程序会检查应用完整性、未完成事务、"
                                 + "字体、磁盘空间、哈希与签名，结果记录在日志中。") {
                            ActionLine(lead: "点击") {
                                HStack(spacing: 6) {
                                    BtnChip(title: "还原", kind: .danger)
                                    BtnChip(title: "自检", kind: .glass)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 20)
                }
                .frame(maxHeight: 440)

                Divider().opacity(0.5)

                HStack {
                    Text("本工具仅修改所选的 Claude 应用包，不读取账号与会话数据。")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                    Button("知道了") { showHelp = false }
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
                Text("版本 \(n.version)").font(.system(size: 14, weight: .semibold))
                if n.version == appVersion {
                    Text("当前版本")
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
                        Text("新特性").font(.system(size: 17, weight: .semibold)).tracking(-0.17)
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
                    Spacer()
                    Button("知道了") { showWhatsNew = false }
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
                        Text("确认还原 Claude 字体？")
                            .font(.system(size: 15, weight: .semibold)).tracking(-0.15)
                        Text("会从备份恢复\(m.target.label)的 app.asar 并重新签名，"
                             + "当前的\(m.current.font.isEmpty ? m.fontFamily : m.current.font)"
                             + "设置将被移除。Claude 需要退出后重新打开。")
                            .font(.system(size: 12.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(m.current.backups.first.map { "备份 " + $0 }
                     ?? "没有整包备份，将用 app.asar.bak 原版留底还原")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9)
                        .fill(Color.secondary.opacity(0.09)))
                HStack(spacing: 9) {
                    Spacer()
                    Button("取消") { confirmRestore = false }
                        .buttonStyle(.glass).controlSize(.large)
                    Button("还原") { confirmRestore = false; m.uninstall() }
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
        else { return .failed("仓库地址没配置") }
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            // 404 既可能是仓库还没发过 Release，也可能是仓库名写错了；
            // 对用户来说结论一样：现在没有可下载的版本。
            if code == 404 { return .noRelease }
            if code == 403 { return .failed("GitHub 限流了，过一会儿再试") }
            guard code == 200 else { return .failed("GitHub 返回 \(code)") }
            guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = j["tag_name"] as? String,
                  let link = j["html_url"] as? String, let page = URL(string: link)
            else { return .failed("发布信息解析失败") }
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

struct AboutView: View {
    @State private var checking = false
    @State private var note = ""
    @State private var newRelease: Updater.Release?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 96, height: 96)
                VStack(spacing: 3) {
                    Text("Clfont").font(.system(size: 22, weight: .semibold)).tracking(-0.2)
                    Text("版本 \(Updater.version)（\(Updater.build)）")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text("替换 Claude 桌面版界面的显示字体，支持中文、英文或中英文")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 20)

            Divider().opacity(0.5)

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text("开发者").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text("赵万（Jovan）").font(.system(size: 12.5, weight: .medium))
                }

                if let r = newRelease {
                    Button { NSWorkspace.shared.open(r.page) } label: { buttonLabel("前往下载") }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule).tint(DS.accent)
                } else {
                    Button { check() } label: { buttonLabel("检查更新") }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .disabled(checking)
                }

                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 18)

            Divider().opacity(0.5)

            Text("仅修改本机安装的 Claude 应用包，不读取账号与会话数据")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .padding(.horizontal, 28).padding(.vertical, 12)
        }
        .frame(width: 360)
        .background { Color(nsColor: .windowBackgroundColor).ignoresSafeArea() }
    }

    private func buttonLabel(_ title: String) -> some View {
        HStack(spacing: 6) {
            if checking { ProgressView().controlSize(.small) }
            Text(title).font(.system(size: 13, weight: .medium))
        }
        .frame(maxWidth: .infinity).frame(height: 32)
    }

    private func check() {
        guard !Updater.repo.isEmpty else {
            note = "还没上架 GitHub，暂时没有可检查的版本。"
            return
        }
        checking = true; note = ""
        Task {
            defer { checking = false }
            switch await Updater.latest() {
            case .release(let r):
                if Updater.isNewer(r.tag, than: Updater.version) {
                    newRelease = r
                    note = "有新版本 \(r.tag)。"
                } else {
                    note = "已是最新版本。"
                }
            case .noRelease:
                note = "仓库里还没有发布任何版本。"
            case .failed(let why):
                note = "检查失败：\(why)"
            }
        }
    }
}

private struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("关于 Clfont") { openWindow(id: "about") }
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

        Window("关于 Clfont", id: "about") { AboutView() }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
    }
}
