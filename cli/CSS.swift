import Foundation

// 注入的 CSS。输出必须与 Python 版**逐字节一致**——两版共用同一份黄金文件，
// 差一个空格测试就红。改这里之前先看 tests/golden/。

let UNICODE_RANGE = "U+2E80-2EFF, U+3000-303F, U+3400-4DBF, "
                  + "U+4E00-9FFF, U+F900-FAFF, U+FF00-FFEF"
let UNICODE_RANGE_CJK = UNICODE_RANGE

// 英文的基础覆盖只到基本拉丁。刻意不含 U+00A0-00BF 那段符号区和私用区：
// Claude 界面上的图标就是 anthropic 字体里的字形，实测把 font-family 整个换掉时
// 它们显示成 É（U+00C9）和 □。
let UNICODE_RANGE_LATIN = "U+0020-007E"

// 带重音的拉丁字母。整段全是字母、没有符号，但**只给正文字体用，不给界面字体**：
// 图标落在 U+00C9 一带，而图标是 anthropic-sans 的字形；正文走 anthropic-serif。
let UNICODE_RANGE_LATIN_EXT = "U+00C0-00FF, U+0100-017F"

// 承载图标的字体族。同一批族也正好是「界面字体」：实测 anthropic-sans 用于
// 界面 chrome、输入框和用户自己发的消息，anthropic-serif 用于 Claude 的回复
// 与标题。所以 latin_scope=body 时跳过它们，等价于「只换正文、不动界面」。
let ICON_BEARING_FAMILIES: Set<String> = ["anthropic-sans"]
let PAGE_FONT_FAMILIES = ["anthropic-sans", "anthropic-serif"]

let EXTRA_FONT_FAMILIES = [
    "Helvetica", "Helvetica Neue", "Arial", "Georgia", "Times", "Times New Roman",
    "Inter", "Roboto", "Segoe UI", "SF Pro", "SF Pro Text", "SF Pro Display",
    "PingFang SC", "PingFang TC", "Hiragino Sans GB", "Heiti SC",
    "Microsoft YaHei", "Noto Sans SC", "Noto Sans CJK SC", "Source Han Sans SC",
]

let CDS_SERIF = "\"anthropic-serif\", ui-serif, Georgia, \"Times New Roman\", serif"
let CDS_SANS = "\"anthropic-sans\", ui-sans-serif, -apple-system, BlinkMacSystemFont, "
             + "\"Segoe UI\", sans-serif"

let CJK_FAMILY_BODY = "ClaudeCJKSerif"
let CJK_FAMILY_UI = "ClaudeCJKSerifUI"
let CLFONT_MONO_FAMILY = "ClfontMono"

// 远程 claude.ai 页面用的是 CDS 的 .cds-root 作用域版本，变量名带 --cds- 前缀
// （html 元素上就挂着 class="cds-root"）。本地应用外壳里那份无前缀的 :root 导出
// 是另一套，改它对界面没有任何影响——这一点是实测出来的，别改回去。
let CDS_MONO_VAR = "--cds-font-mono"

let SCALE_MIN = 80, SCALE_MAX = 150

func scaleOf(_ cfg: Config, _ key: String) -> Int {
    let v: Int
    if let i = cfg.raw[key] as? Int { v = i }
    else if let d = cfg.raw[key] as? Double { v = Int(d.rounded()) }
    else if let s = cfg.raw[key] as? String, let d = Double(s) { v = Int(d.rounded()) }
    else { v = 100 }
    return max(SCALE_MIN, min(SCALE_MAX, v))
}

func sizeAdjustCSS(_ scale: Int) -> String {
    scale != 100 ? "size-adjust:\(scale)%;" : ""
}

private func locs(_ names: [String?]) -> String {
    var seen = Set<String>(), out: [String] = []
    for n in names {
        guard let n, !n.isEmpty, !seen.contains(n) else { continue }
        seen.insert(n)
        out.append("local(\"\(n)\")")
    }
    return out.joined(separator: ", ")
}

/// (常规 src, 粗体 src)。GUI 选字体时会写入 <key>_regular / <key>_bold，
/// 这样粗体命中真实粗体面而不是系统合成加粗。
func srcs(_ cfg: Config, _ key: String = "font") -> (String, String) {
    let name = cfg.string(key)
    guard !name.isEmpty else { return ("", "") }
    var fonts = [name]
    if key == "font" { fonts += cfg.strings("fallback_fonts") }
    var reg = cfg.raw[key + "_regular"] as? String
    var bold = cfg.raw[key + "_bold"] as? String
    if key == "font", (reg ?? "").isEmpty, (bold ?? "").isEmpty, name == "Songti SC" {
        reg = "STSongti-SC-Regular"; bold = "STSongti-SC-Bold"
    }
    let regList: [String?] = [reg] + fonts.map { Optional($0) }
    let boldList: [String?] = [(bold?.isEmpty == false) ? bold : reg] + fonts.map { Optional($0) }
    return (locs(regList), locs(boldList))
}

struct ScopeSpec {
    let kind: String        // cjk | latin
    let range: String
    let reg: String
    let bold: String
    let scale: Int
}

func scopeSpecs(_ cfg: Config) -> [ScopeSpec] {
    var out: [ScopeSpec] = []
    let scope = cfg.scope
    if scope == "cjk" || scope == "both" {
        let (r, b) = srcs(cfg, "font")
        if !r.isEmpty {
            out.append(ScopeSpec(kind: "cjk", range: UNICODE_RANGE_CJK,
                                 reg: r, bold: b, scale: scaleOf(cfg, "font_scale")))
        }
    }
    if scope == "latin" || scope == "both" {
        let (r, b) = srcs(cfg, "font_latin")
        if !r.isEmpty {
            out.append(ScopeSpec(kind: "latin", range: UNICODE_RANGE_LATIN,
                                 reg: r, bold: b, scale: scaleOf(cfg, "font_scale_latin")))
        }
    }
    return out
}

/// 中文替换用的族。正文与界面各定义一份，除字号外完全相同——
/// 这样侧边栏、输入框的中文可以和正文用不同字号。
func fontFaceCSS(_ cfg: Config) -> String {
    let (reg, bold) = srcs(cfg)
    var out = ""
    for (fam, key) in [(CJK_FAMILY_BODY, "font_scale"), (CJK_FAMILY_UI, "font_scale_ui")] {
        let adj = sizeAdjustCSS(scaleOf(cfg, key))
        out += "@font-face{font-family:\"\(fam)\";font-weight:normal;"
             + "src:\(reg);unicode-range:\(UNICODE_RANGE);\(adj)}"
             + "@font-face{font-family:\"\(fam)\";font-weight:bold;"
             + "src:\(bold);unicode-range:\(UNICODE_RANGE);\(adj)}"
    }
    return out
}

/// 把 ClaudeCJKSerif 前插到 CDS 字体变量——拉丁不受影响（unicode-range）。
func varsCSS() -> String {
    ":root{"
    + "--font-anthropic-serif:\"\(CJK_FAMILY_BODY)\", \(CDS_SERIF) !important;"
    + "--font-anthropic-sans:\"\(CJK_FAMILY_UI)\", \(CDS_SANS) !important;"
    + "}"
}

/// 给页面自己那两个家族再补一条只覆盖指定码位的 @font-face。
/// 同名家族有多条声明时，重叠码位上后声明的生效；我们的样式追加在文档末尾。
/// 关键：**完全不改任何 font-family**——侧边栏那些图标就是 anthropic-sans 里的
/// 字形，一旦覆盖 font-family 就会变成豆腐块。
func faceOverrideCSS(_ cfg: Config, _ families: [String] = PAGE_FONT_FAMILIES) -> String {
    var out: [String] = []
    let bodyOnly = cfg.string("latin_scope") == "body"
    let uiScale = scaleOf(cfg, "font_scale_ui")
    for spec in scopeSpecs(cfg) {
        for fam in families {
            // 界面字体族走「界面字号」，正文族走中文/英文字号。侧边栏基准只有
            // 13px，跟着正文一起放大时看不出变化，分开给一个数才调得动。
            let adj = sizeAdjustCSS(ICON_BEARING_FAMILIES.contains(fam) ? uiScale : spec.scale)
            // 「仅正文」：界面字体族整个跳过。小字号的界面标签换成正文衬线体
            // 会显得单薄，这个选项就是为此留的。
            if spec.kind == "latin" && bodyOnly && ICON_BEARING_FAMILIES.contains(fam) {
                continue
            }
            // 正文字体可以连重音字母一起换；承载图标的界面字体不行
            var frng = spec.range
            if spec.kind == "latin" && !ICON_BEARING_FAMILIES.contains(fam) {
                frng = spec.range + ", " + UNICODE_RANGE_LATIN_EXT
            }
            for style in ["normal", "italic"] {
                // 页面自己的 face 声明的是可变字重 300 800，这里按常规/粗体拆两段，
                // 免得粗体落回原字体（那样又会走系统兜底）。
                out.append("@font-face{font-family:\"\(fam)\";src:\(spec.reg);"
                         + "unicode-range:\(frng);\(adj)"
                         + "font-weight:100 500;font-style:\(style);}")
                out.append("@font-face{font-family:\"\(fam)\";src:\(spec.bold);"
                         + "unicode-range:\(frng);\(adj)"
                         + "font-weight:501 900;font-style:\(style);}")
            }
        }
    }
    return out.joined()
}

func bruteCSS(_ cfg: Config) -> String { faceOverrideCSS(cfg, EXTRA_FONT_FAMILIES) }

/// 代码块字体。先定义我们自己的族（字号才有地方落，走 size-adjust），
/// 再把 CDS 的 mono token 指向它，保留原有 ui-monospace 兜底链。
/// 必须带 !important：这些 token 会被页面后加载的样式表重新声明。
func monoCSS(_ cfg: Config) -> String {
    guard !cfg.string("font_mono").isEmpty else { return "" }
    let (reg, bold) = srcs(cfg, "font_mono")
    guard !reg.isEmpty else { return "" }
    let adj = sizeAdjustCSS(scaleOf(cfg, "font_mono_scale"))
    let fam = CLFONT_MONO_FAMILY
    let stack = "\"\(fam)\", ui-monospace, SFMono-Regular, Menlo, monospace"
    return "@font-face{font-family:\"\(fam)\";src:\(reg);font-weight:100 500;\(adj)}"
         + "@font-face{font-family:\"\(fam)\";src:\(bold);font-weight:501 900;\(adj)}"
         + ":root,.cds-root{\(CDS_MONO_VAR):\(stack) !important;}"
}

private let hexRE = try! NSRegularExpression(pattern: "^#[0-9A-Fa-f]{6}$")

/// 页面底色。改 CDS 的 surface 语义 token，不动底层色阶——分隔线、边框也在用
/// 那些，一起改会牵连出对比度问题。
///
/// 两个必要条件都是实测得出的：变量名必须带 --cds- 前缀；必须加 !important
/// （不加时计算值纹丝不动）。只在浅色模式生效。
func backgroundCSS(_ cfg: Config) -> String {
    let color = cfg.string("bg_color").trimmingCharacters(in: .whitespaces)
    guard !color.isEmpty else { return "" }
    let r = NSRange(color.startIndex..., in: color)
    guard hexRE.firstMatch(in: color, range: r) != nil else {
        info("底色 '\(color)' 不是 #RRGGBB 形式，已忽略")
        return ""
    }
    func mix(_ pct: Int) -> String { "color-mix(in srgb, \(color) \(pct)%, #ffffff)" }
    // 各层的抬升幅度照原版来：原版 surface-0/1/2 是 #f9f9f7 / #fcfcfb / #ffffff，
    // 彼此只差 3 到 6 个色阶。早先按 60% / 30% 混白，换成米色底之后输入框那块
    // 七成是白的，压在米色页面上明显跳出来。
    let pairs: [(String, String)] = [
        ("--cds-surface-0", color),
        ("--cds-page-bg", color),
        ("--background-color-page", color),
        ("--cds-surface-1", mix(92)),
        ("--cds-surface-2", mix(85)),
        ("--cds-surface-3", mix(85)),
        ("--cds-surface-panel", mix(85)),
        ("--cds-surface-popover", mix(85)),
    ]
    let body = pairs.map { "\($0.0):\($0.1) !important;" }.joined()
    return ":root[data-mode=\"light\"],.cds-root[data-mode=\"light\"]{\(body)}"
         + "@media (prefers-color-scheme: light){"
         + ":root:not([data-mode=\"dark\"]),.cds-root:not([data-mode=\"dark\"]){\(body)}}"
}

func buildCSS(_ mode: String, _ cfg: Config) -> String {
    let scope = cfg.scope
    var parts = ["/* \(MARKER) mode=\(mode) scope=\(scope) */"]
    if scope == "cjk" || scope == "both" {
        // ClaudeCJKSerif + CDS 变量前插只服务于中文；只换英文时不要注入，
        // 否则中文也会跟着变。
        parts.append(fontFaceCSS(cfg))
        parts.append(varsCSS())
    }
    parts.append(faceOverrideCSS(cfg))
    parts.append(monoCSS(cfg))
    parts.append(backgroundCSS(cfg))
    if mode == "brute" { parts.append(bruteCSS(cfg)) }
    let css = parts.joined(separator: " ")
    precondition(!css.contains("`") && !css.contains("${") && !css.contains("\\"),
                 "CSS 含会破坏 JS 模板字符串的字符")
    return css
}
