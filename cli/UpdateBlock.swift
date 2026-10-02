import Foundation

/// 检测「Claude 的自动更新被补丁挡住」。
///
/// 成因见 Sign.resign 的说明：我们必须重签名，ad-hoc 签名的指定要求退化成只认
/// 当前 cdhash，而 Squirrel.Mac 装更新前会拿运行中 app 的指定要求去校验下载来的
/// 新版——新版 cdhash 必然不同，于是每次检查都失败。失败只写进 Claude 自己的
/// 日志，界面上没有任何提示，用户会被静默卡在旧版（实测有人卡了近三周）。
///
/// 这里只读日志，不做任何写入，也不碰目标 app。
enum UpdateBlock {
    /// Electron 按 app 名字把日志放在这里；正式版与测试副本共用该目录
    /// （测试副本的 CFBundleName 刻意保持 "Claude"，见 setup-test-copy.sh）。
    /// 测试要能指到别处：否则会读到这台机器上真实的 Claude 日志，输出随机器而变。
    static var logDir: URL {
        if let o = ProcessInfo.processInfo.environment["CLFONT_CLAUDE_LOG_DIR"], !o.isEmpty {
            return URL(fileURLWithPath: o)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Claude")
    }

    static let needle = "did not pass validation"

    /// 日志每行以 `2026-10-01 23:00:45` 开头，与 last_install 记录的时间同格式，
    /// 所以字符串比较即可当时间比较用。
    private static func stamp(_ line: String) -> String? {
        guard line.count >= 19 else { return nil }
        let s = String(line.prefix(19))
        return s.count == 19 && s.hasPrefix("20") ? s : nil
    }

    /// 本次补丁生效之后被挡下的更新次数与最近一次时间。
    /// `since` 之前的记录一律不算——还原并更新过的机器日志里会留着旧的失败记录，
    /// 拿它们报警就成了误报。
    static func blocked(since: String) -> (count: Int, last: String)? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: logDir.path) else { return nil }
        var count = 0
        var last = ""
        for name in names where name.hasPrefix("main") && name.hasSuffix(".log") {
            let url = logDir.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard line.contains(needle), let t = stamp(String(line)) else { continue }
                guard since.isEmpty || t >= since else { continue }
                count += 1
                if t > last { last = t }
            }
        }
        return count > 0 ? (count, last) : nil
    }
}
