import Foundation

/// 配置。字段名与 Python 版完全一致——同一个 config.json 两版都要能读写。
struct Config {
    var raw: [String: Any]

    static let defaults: [String: Any] = [
        "scope": "cjk",
        "font": "Songti SC",
        "font_latin": "",
        "fallback_fonts": ["STSong", "Songti TC"],
        "mode": "auto",
        "font_scale": 100,
        "font_scale_latin": 100,
        "font_mono": "",
        "font_mono_scale": 100,
        "bg_color": "",
        "latin_scope": "all",
    ]

    static func load() -> Config {
        var c = defaults
        if let d = try? Data(contentsOf: P.configPath) {
            if let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                for (k, v) in j { c[k] = v }
            } else {
                info("配置文件损坏，忽略")
            }
        }
        return Config(raw: c)
    }

    func save() {
        try? FileManager.default.createDirectory(
            at: P.configPath.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(
            withJSONObject: raw,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? (d + Data("\n".utf8)).write(to: P.configPath)
        }
    }

    func string(_ key: String) -> String { raw[key] as? String ?? "" }
    func strings(_ key: String) -> [String] { raw[key] as? [String] ?? [] }
    mutating func set(_ key: String, _ v: Any) { raw[key] = v }

    var scope: String {
        let s = string("scope")
        return ["cjk", "latin", "both"].contains(s) ? s : "cjk"
    }
    var mode: String {
        let m = string("mode")
        return ["auto", "brute"].contains(m) ? m : "auto"
    }

    // ---- 上次打补丁的记录：必须按目标分开存
    //
    // 配置文件只有一份，正式版和测试副本共用。旧版把它记在 last_install 里，
    // 给测试副本打一次补丁就会覆盖掉正式版的记录，「Claude 更新后补丁失效」
    // 的提醒也就跟着失灵。

    private static func key(_ t: AppTarget) -> String { t.slug.isEmpty ? "default" : t.slug }

    func lastInstall(_ t: AppTarget) -> [String: Any] {
        if let per = raw["last_install_targets"] as? [String: Any],
           let rec = per[Self.key(t)] as? [String: Any] { return rec }
        // 旧版本留下的单份记录，只算默认目标的
        if t.slug.isEmpty, let legacy = raw["last_install"] as? [String: Any] { return legacy }
        return [:]
    }

    mutating func setLastInstall(_ t: AppTarget, _ rec: [String: Any]) {
        var per = raw["last_install_targets"] as? [String: Any] ?? [:]
        per[Self.key(t)] = rec
        raw["last_install_targets"] = per
        raw.removeValue(forKey: "last_install")
    }

    mutating func clearLastInstall(_ t: AppTarget) -> Bool {
        var changed = false
        if var per = raw["last_install_targets"] as? [String: Any],
           per.removeValue(forKey: Self.key(t)) != nil {
            raw["last_install_targets"] = per
            changed = true
        }
        if t.slug.isEmpty, raw.removeValue(forKey: "last_install") != nil { changed = true }
        return changed
    }
}
