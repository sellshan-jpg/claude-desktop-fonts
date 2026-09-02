import Foundation
import CryptoKit

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// 跑一条命令，返回 (退出码, stdout+stderr)
@discardableResult
func run(_ args: [String], cwd: URL? = nil) -> (code: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = args
    if let cwd { p.currentDirectoryURL = cwd }
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (127, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

// ---- 输出。前缀与 Python 版逐字对齐：GUI 与测试都在匹配这些字面量。

func step(_ s: String) { print("\n▸ \(s)"); Log.raw("step: \(s)") }
func info(_ s: String) { print("  · \(s)"); Log.raw("info: \(s)") }
func ok(_ s: String) { print("  ✓ \(s)"); Log.raw("ok: \(s)") }
func bad(_ s: String) { print("  ✗ \(s)"); Log.raw("bad: \(s)") }

func die(_ msg: String, _ code: Int32 = 1) -> Never {
    print("\n✗ \(msg)")
    Log.raw("die: \(msg)")
    exit(code)
}

func confirm(_ prompt: String, _ assumeYes: Bool) -> Bool {
    if assumeYes { print("\(prompt) [y/N] y（--yes）"); return true }
    print(prompt + " [y/N] ", terminator: "")
    guard let line = readLine() else { return false }
    return ["y", "yes"].contains(line.trimmingCharacters(in: .whitespaces).lowercased())
}

func humanSize(_ bytes: Int64) -> String {
    var v = Double(bytes)
    for unit in ["B", "KB", "MB", "GB"] {
        if v < 1024 || unit == "GB" {
            return unit == "B" ? "\(Int(v))B" : String(format: "%.1f%@", v, unit)
        }
        v /= 1024
    }
    return "\(bytes)B"
}
