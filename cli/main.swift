import Foundation

// 参数解析。刻意手写而不引第三方库：CLI 要能塞进 app bundle 独立运行，
// 依赖越少越好。接口必须与 Python 版一致——GUI 和回归测试按同一套调用。

struct Args {
    var cmd = ""
    var appPath = AppTarget.defaultPath
    var flags: [String: String] = [:]
    var yes = false

    func int(_ k: String) -> Int? { flags[k].flatMap { Int($0) } }
    func str(_ k: String) -> String? { flags[k] }
}

let boolFlags: Set<String> = ["--prune", "--purge", "--all"]
let takesValue: Set<String> = ["--app", "--scope", "--mode", "--scale",
                               "--scale-latin", "--mono", "--mono-scale", "--bg",
                               "--in", "--out", "--latin-scope", "--scale-ui"]

func parseArgs() -> Args {
    var a = Args()
    let argv = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < argv.count {
        let tok = argv[i]
        if tok == "-y" || tok == "--yes" { a.yes = true; i += 1; continue }
        if takesValue.contains(tok) {
            guard i + 1 < argv.count else { die("\(tok) 缺少取值", 2) }
            if tok == "--app" { a.appPath = argv[i + 1] } else { a.flags[tok] = argv[i + 1] }
            i += 2; continue
        }
        if tok.hasPrefix("--") {
            a.flags[tok] = "1"; i += 1; continue
        }
        if a.cmd.isEmpty { a.cmd = tok } 
        i += 1
    }
    return a
}

let args = parseArgs()
let target = AppTarget(args.appPath)

func applyOverrides(_ cfg: inout Config, _ a: Args) {
    if let v = a.str("--scope") { cfg.set("scope", v) }
    if let v = a.str("--mode") { cfg.set("mode", v) }
    if let v = a.int("--scale") { cfg.set("font_scale", v) }
    if let v = a.int("--scale-latin") { cfg.set("font_scale_latin", v) }
    if let v = a.str("--mono") { cfg.set("font_mono", v) }
    if let v = a.int("--mono-scale") { cfg.set("font_mono_scale", v) }
    if let v = a.str("--bg") { cfg.set("bg_color", v) }
    if let v = a.str("--latin-scope") { cfg.set("latin_scope", v) }
    if let v = a.int("--scale-ui") { cfg.set("font_scale_ui", v) }
}

switch args.cmd {
case "_css":
    var cfg = Config.load()
    applyOverrides(&cfg, args)
    // 用 print 而不是 FileHandle.write：后者绕过 stdout 缓冲，会抢在前面
    // 那些诊断信息之前输出，与 Python 版的顺序对不上。
    print(buildCSS(cfg.mode, cfg), terminator: "")
case "_repack":
    // 隐藏命令：原样重打包 asar，供测试验证「与原文件逐字节一致」。
    // 这条性质是整个方案的正确性自证：能原样复现，才谈得上只改想改的那一处。
    guard let src = args.str("--in"), let dst = args.str("--out") else {
        die("_repack 需要 --in 与 --out", 2)
    }
    do {
        let u = URL(fileURLWithPath: src)
        let hdr = try asarReadHeader(u)
        let fh = try FileHandle(forReadingFrom: u)
        defer { try? fh.close() }
        try asarPack(hdr, URL(fileURLWithPath: dst)) { _, key in
            try fh.seek(toOffset: UInt64(hdr.base + key.0))
            return try fh.read(upToCount: key.1) ?? Data()
        }
    } catch { die("重打包失败：\(error)") }

case "install":
    Log.open("install")
    cmdInstall(target, args)
case "uninstall":
    Log.open("uninstall")
    cmdUninstall(target, args)
case "status":
    Log.open("status")
    cmdStatus(target)
case "doctor":
    Log.open("doctor")
    cmdDoctor(target)
case "backups":
    Log.open("backups")
    cmdBackups(target, args)
case "":
    die("缺少子命令", 2)
default:
    die("未知子命令：\(args.cmd)", 2)
}
