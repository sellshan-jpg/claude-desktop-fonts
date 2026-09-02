import Foundation

/// 测试钩子：在指定步骤自杀。tag:int 抛中断，否则 SIGKILL。
/// 用来验证「任何一步崩掉都能修回原样」——这是回归测试里覆盖面最广的一项。
func maybeCrash(_ tag: String) throws {
    guard let spec = Env.str("CLFONT_CRASH_AT") else { return }
    let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.first == tag else { return }
    Log.raw("CRASH HOOK triggered: \(spec)")
    if parts.count > 1 && parts[1] == "int" { throw UserInterrupt() }
    print("  !! 测试钩子：SIGKILL @ \(tag)")
    kill(getpid(), SIGKILL)
}

struct UserInterrupt: Error {}

// ---------------------------------------------------------------- 事务日志

enum Journal {
    static func write(_ data: [String: Any]) {
        do {
            try FileManager.default.createDirectory(at: P.dataDir, withIntermediateDirectories: true)
            let tmp = URL(fileURLWithPath: P.journal.path + ".tmp")
            let d = try JSONSerialization.data(withJSONObject: data,
                                               options: [.prettyPrinted, .withoutEscapingSlashes])
            try d.write(to: tmp)
            _ = try? FileManager.default.removeItem(at: P.journal)
            try FileManager.default.moveItem(at: tmp, to: P.journal)
        } catch { Log.raw("journal 写入失败：\(error)") }
    }

    static func read() -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: P.journal.path) else { return nil }
        guard let d = try? Data(contentsOf: P.journal),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { return ["corrupt": true] }
        return o
    }

    static func clear() { try? FileManager.default.removeItem(at: P.journal) }
}

/// 事务：mark() 记录进度到 journal，addUndo() 入栈；rollback() 逆序撤销，
/// 收尾一律重签 + 验证——不假设「改回去就不用签」（resource seal 对目录结构敏感）。
final class Txn {
    private let name: String
    private let target: AppTarget
    private var steps: [[String: Any]] = []
    private var undo: [(String, () throws -> Void)] = []

    init(_ name: String, _ target: AppTarget) {
        self.name = name
        self.target = target
        Journal.write(state("started"))
    }

    private func state(_ status: String) -> [String: Any] {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return ["txn": name, "app": target.app.path, "status": status,
                "time": f.string(from: Date()), "steps": steps, "log": Log.path]
    }

    func mark(_ desc: String, done: Bool = true) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        steps.append(["step": desc, "done": done, "time": f.string(from: Date())])
        Journal.write(state("in-progress"))
        Log.raw("txn mark: \(desc) done=\(done)")
    }

    func addUndo(_ desc: String, _ fn: @escaping () throws -> Void) {
        undo.append((desc, fn))
    }

    func commit() { Journal.clear(); Log.raw("txn commit") }

    @discardableResult
    func rollback() -> Bool {
        // 回滚期间屏蔽 Ctrl+C，避免二次中断留下半成品
        signal(SIGINT, SIG_IGN)
        print("\n▸ 正在回滚（请勿再次中断）…")
        Log.raw("txn rollback begin")
        Journal.write(state("rolling-back"))
        var failed: [String] = []
        for (desc, fn) in undo.reversed() {
            do { try fn(); ok("已撤销：\(desc)") }
            catch { bad("撤销失败：\(desc) —— \(error)"); failed.append(desc) }
        }
        do { try Sign.resign(target) }
        catch { bad("回滚收尾重签失败：\(error)"); failed.append("重签名") }
        signal(SIGINT, SIG_DFL)
        if !failed.isEmpty {
            Journal.write(state("rollback-incomplete"))
            print("\n✗ 回滚未完全成功（失败项：" + failed.joined(separator: "、") + "）")
            print("  手动还原命令：\n" + manualRestoreText(target))
            return false
        }
        Journal.clear()
        print("\n✓ 已回滚到原始状态（签名已验证）。")
        return true
    }
}

func manualRestoreText(_ t: AppTarget) -> String {
    """
      首选（工具自救）：
        \(P.canon.path) uninstall
      或手动执行（注意：必须同步 Info.plist 的 asar 完整性哈希，否则 app 起不来）：
        cd "\(t.res.path)"
        rm -rf app app.asar.clfont-new*
        [ -f app.asar.bak ] && mv -f app.asar.bak app.asar
        codesign --force --sign - "\(t.app.path)"
    """
}
