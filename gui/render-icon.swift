// 按 design_handoff_clfont_ui 的图标规范（方案 2b）重新出稿。
//
// 和交付的 PNG 的区别：**满画布、不透明**。macOS 26 会把带 alpha 的旧格式图标
// 塞进一层灰色底板里再缩小；只有不透明且画满整张画布的图，系统才会直接按新形状
// 裁圆角。所以这里去掉了原稿里 824/1024 的留白和自绘圆角+投影，几何值整体
// ×(1024/824)，右下角徽标也往里收，免得被系统的圆角切掉。
//
// 用法：swift render-icon.swift <输出目录>   → 写出全套尺寸 PNG

import AppKit
import ImageIO
import UniformTypeIdentifiers

let K: CGFloat = 1024.0 / 824.0     // 原稿的圆角方形是 824，现在铺满 1024
let S: CGFloat = 1024               // 主稿边长

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

/// CSS 的 y 轴朝下，CoreGraphics 朝上
func cg(_ yCSS: CGFloat) -> CGFloat { S - yCSS }

/// 按 CSS 盒模型摆一个字：给定字号 / line-height / 盒子的边距，算出基线位置。
/// 浏览器里 content area 高 = ascent + descent，half-leading 上下均分。
func drawGlyph(_ text: String, fontName: String, size: CGFloat, color: NSColor,
               left: CGFloat?, right: CGFloat?, top: CGFloat?, bottom: CGFloat?,
               lineHeight: CGFloat, ctx: CGContext) {
    guard let font = NSFont(name: fontName, size: size) else {
        FileHandle.standardError.write("找不到字体 \(fontName)\n".data(using: .utf8)!)
        exit(1)
    }
    let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let line = CTLineCreateWithAttributedString(attr)
    let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))

    let asc = font.ascender, desc = -font.descender
    let halfLeading = (lineHeight * size - (asc + desc)) / 2

    let penX: CGFloat
    if let l = left { penX = l } else { penX = (right! - advance) }

    let baselineCSS: CGFloat
    if let t = top { baselineCSS = t + halfLeading + asc }
    else { baselineCSS = bottom! - halfLeading - desc }

    ctx.textPosition = CGPoint(x: penX, y: cg(baselineCSS))
    CTLineDraw(line, ctx)
}

func linearGradient(_ ctx: CGContext, colors: [NSColor], locations: [CGFloat],
                    from: CGPoint, to: CGPoint, clip: CGPath) {
    ctx.saveGState()
    ctx.addPath(clip); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: colors.map { $0.cgColor } as CFArray,
                       locations: locations)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation,
                                                              .drawsAfterEndLocation])
    ctx.restoreGState()
}

/// 不透明画布：只要图里还有 alpha 通道，macOS 26 就会当成旧格式图标套一层灰底板，
/// 所以全程用 noneSkipLast，导出的 PNG 也不带 alpha。
func opaqueContext(_ size: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    return ctx
}

func renderMaster() -> CGImage {
    let ctx = opaqueContext(Int(S))
    let full = CGPath(rect: CGRect(x: 0, y: 0, width: S, height: S), transform: nil)

    // 底面：155deg 渐变，铺满整张画布（原稿是 824 的圆角方形，圆角现在交给系统）
    linearGradient(ctx, colors: [hex(0xFDFDFF), hex(0xF0F2F8), hex(0xE2E7F2)],
                   locations: [0, 0.52, 1],
                   from: CGPoint(x: S * 0.18, y: S), to: CGPoint(x: S * 0.82, y: 0), clip: full)

    // 后景「字」：黑体，黑 15%
    drawGlyph("字", fontName: "PingFangSC-Regular", size: 528 * K, color: hex(0x1C1C1E, 0.15),
              left: 90 * K, right: nil, top: 52 * K, bottom: nil, lineHeight: 1.35, ctx: ctx)

    // 前景「字」：宋体
    drawGlyph("字", fontName: "STSongti-SC-Bold", size: 540 * K, color: hex(0x1C1C1E),
              left: nil, right: S - 116 * K, top: nil, bottom: S - 154 * K,
              lineHeight: 1, ctx: ctx)

    // 底部色带：通宽
    let bandH = 70 * K
    linearGradient(ctx, colors: [hex(0xC2603F), hex(0xE8A06E)], locations: [0, 1],
                   from: CGPoint(x: 0, y: 0), to: CGPoint(x: S, y: 0),
                   clip: CGPath(rect: CGRect(x: 0, y: 0, width: S, height: bandH), transform: nil))

    // 互换徽标：原稿溢出在圆角方形外，满画布后会被系统圆角切掉，所以往里收
    let d = 218 * K
    let center = CGPoint(x: 840, y: cg(840))
    let badge = CGPath(ellipseIn: CGRect(x: center.x - d / 2, y: center.y - d / 2,
                                         width: d, height: d), transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * K), blur: 20 * K,
                  color: NSColor(srgbRed: 120 / 255, green: 50 / 255, blue: 20 / 255,
                                 alpha: 0.35).cgColor)
    ctx.addPath(badge); ctx.setFillColor(hex(0xD97757).cgColor); ctx.fillPath()
    ctx.restoreGState()
    linearGradient(ctx, colors: [hex(0xD97757), hex(0xB04D2B)], locations: [0, 1],
                   from: CGPoint(x: center.x - d / 2, y: center.y + d / 2),
                   to: CGPoint(x: center.x + d / 2, y: center.y - d / 2), clip: badge)

    // 徽标里的 ⇄
    let gs = 110 * K
    let gf = NSFont.systemFont(ofSize: gs, weight: .regular)
    let ga = NSAttributedString(string: "⇄", attributes: [.font: gf,
                                                          .foregroundColor: NSColor.white])
    let gl = CTLineCreateWithAttributedString(ga)
    var ascent: CGFloat = 0, descent: CGFloat = 0
    let gw = CGFloat(CTLineGetTypographicBounds(gl, &ascent, &descent, nil))
    ctx.textPosition = CGPoint(x: center.x - gw / 2,
                               y: center.y - (ascent - descent) / 2)
    CTLineDraw(gl, ctx)

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,
                                               1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func scaled(_ master: CGImage, to size: Int) -> CGImage {
    if size == Int(S) { return master }
    let ctx = opaqueContext(size)
    ctx.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let master = renderMaster()
for size in [16, 32, 64, 128, 256, 512, 1024] {
    writePNG(scaled(master, to: size),
             to: URL(fileURLWithPath: outDir + "/Clfont-icon-\(size).png"))
}
print("写出 \(outDir)/Clfont-icon-*.png")
