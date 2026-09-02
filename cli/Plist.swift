import Foundation

// Info.plist 读写。用 PropertyListSerialization 而不是调 PlistBuddy：
// 少一次 fork，也不依赖 /usr/libexec 里的工具。

func plistDict(_ url: URL) -> [String: Any]? {
    guard let d = try? Data(contentsOf: url),
          let o = try? PropertyListSerialization.propertyList(from: d, format: nil)
    else { return nil }
    return o as? [String: Any]
}

/// Info.plist 里记录的 app.asar 头哈希。改了 asar 不同步这个值，app 起不来。
func plistGetAsarHash(_ t: AppTarget) -> String? {
    guard let d = plistDict(t.infoPlist),
          let integrity = d["ElectronAsarIntegrity"] as? [String: Any],
          let entry = integrity["Resources/app.asar"] as? [String: Any]
    else { return nil }
    return entry["hash"] as? String
}

func plistSetAsarHash(_ t: AppTarget, _ value: String) throws {
    guard var d = plistDict(t.infoPlist) else { throw CLIError("读不到 Info.plist") }
    var integrity = d["ElectronAsarIntegrity"] as? [String: Any] ?? [:]
    var entry = integrity["Resources/app.asar"] as? [String: Any] ?? [:]
    entry["hash"] = value
    if entry["algorithm"] == nil { entry["algorithm"] = "SHA256" }
    integrity["Resources/app.asar"] = entry
    d["ElectronAsarIntegrity"] = integrity
    let out = try PropertyListSerialization.data(
        fromPropertyList: d, format: .xml, options: 0)
    try out.write(to: t.infoPlist, options: .atomic)
}
