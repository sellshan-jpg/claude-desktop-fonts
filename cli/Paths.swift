// clfont CLI（Swift 版）——路径与环境钩子
//
// 与 Python 版逐条对齐：命令行接口、输出文案、退出码都必须一致，
// 因为 GUI 靠输出里的字面量解析状态，回归测试也按同一套断言跑两版。

import Foundation

let MARKER = "clfont-v1"

/// 测试钩子。与 Python 版同名同义，测试脚本两版通用。
enum Env {
    static func str(_ key: String) -> String? {
        guard let v = ProcessInfo.processInfo.environment[key], !v.isEmpty else { return nil }
        return v
    }
    static func flag(_ key: String) -> Bool { str(key) != nil }
}

let HOME = FileManager.default.homeDirectoryForCurrentUser.path

enum P {
    static let dataDir = URL(fileURLWithPath:
        Env.str("CLFONT_DATA_DIR") ?? HOME + "/.local/share/clfont")
    static var logDir: URL { dataDir.appendingPathComponent("logs") }
    static var journal: URL { dataDir.appendingPathComponent("journal.json") }
    static let configPath = URL(fileURLWithPath:
        Env.str("CLFONT_CONFIG") ?? HOME + "/.config/clfont/config.json")
    static let canon = URL(fileURLWithPath:
        Env.str("CLFONT_BIN_DIR") ?? HOME + "/.local/bin").appendingPathComponent("clfont")
}

/// 当前操作的目标 app 及其内部路径。与 Python 的 set_app 一一对应。
struct AppTarget {
    let app: URL
    var res: URL { app.appendingPathComponent("Contents/Resources") }
    var asar: URL { res.appendingPathComponent("app.asar") }
    var asarBak: URL { res.appendingPathComponent("app.asar.bak") }
    var appDir: URL { res.appendingPathComponent("app") }
    var unpacked: URL { res.appendingPathComponent("app.asar.unpacked") }
    var infoPlist: URL { app.appendingPathComponent("Contents/Info.plist") }
    var binary: URL { app.appendingPathComponent("Contents/MacOS/Claude") }
    var helper: URL { app.appendingPathComponent("Contents/Frameworks/Claude Helper.app") }

    static let defaultPath = "/Applications/Claude.app"

    init(_ path: String) { app = URL(fileURLWithPath: path).standardizedFileURL }

    /// 非默认目标在备份名里加一段路径哈希。否则多个目标共用数据目录时会按版本号
    /// 撞车——曾导致给测试副本还原时取到正式版的备份。默认目标保持老命名不变。
    var slug: String {
        guard app.path != Self.defaultPath else { return "" }
        return "-" + sha256Hex(Data(app.path.utf8)).prefix(8)
    }

    var version: String? {
        guard let d = try? Data(contentsOf: infoPlist),
              let o = try? PropertyListSerialization.propertyList(from: d, format: nil),
              let dict = o as? [String: Any] else { return nil }
        return dict["CFBundleShortVersionString"] as? String ?? "?"
    }
}
