import Foundation

/// 全程写日志：SIGKILL 级崩溃也要留下验尸材料。
enum Log {
    nonisolated(unsafe) private static var handle: FileHandle?
    nonisolated(unsafe) static var path: String = "-"

    static func open(_ cmd: String) {
        try? FileManager.default.createDirectory(at: P.logDir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let url = P.logDir.appendingPathComponent("clfont-\(f.string(from: Date()))-\(cmd).log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        path = url.path
        raw("=== clfont \(cmd) ===")
    }

    static func raw(_ s: String) {
        guard let handle else { return }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        handle.write(Data("[\(f.string(from: Date()))] \(s)\n".utf8))
    }

    static func close() { try? handle?.close(); handle = nil }
}
