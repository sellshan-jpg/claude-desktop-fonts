import Foundation

/// 保序 JSON。
///
/// 为什么不用 JSONSerialization：Swift 的字典无序，而 asar 头必须按原顺序重新
/// 序列化——「原样重打包与官方 asar 逐字节一致」是整个方案的正确性自证，顺序
/// 一变就没了。Python 的 dict 自 3.7 起保序，json.dumps 直接就对。
///
/// 序列化规则对齐 `json.dumps(obj, separators=(",", ":"), ensure_ascii=False)`：
/// 分隔符无空格、非 ASCII 原样输出、不转义 `/`。数字保留原始 token，避免
/// 123 被写成 123.0。
indirect enum JSON {
    case object([(String, JSON)])
    case array([JSON])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    subscript(key: String) -> JSON? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.first { $0.0 == key }?.1
    }
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var intValue: Int? {
        if case .number(let n) = self { return Int(n) ?? Int(Double(n) ?? 0) }
        if case .string(let s) = self { return Int(s) }
        return nil
    }
    var objectPairs: [(String, JSON)]? {
        if case .object(let p) = self { return p }; return nil
    }

    /// 就地改写某个键（保持原有位置；不存在则追加到末尾）
    mutating func set(_ key: String, _ value: JSON) {
        guard case .object(var pairs) = self else { return }
        if let i = pairs.firstIndex(where: { $0.0 == key }) { pairs[i].1 = value }
        else { pairs.append((key, value)) }
        self = .object(pairs)
    }
}

// ---------------------------------------------------------------- 解析

struct JSONParser {
    private let s: [UInt8]
    private var i = 0
    init(_ data: Data) { s = [UInt8](data) }

    static func parse(_ data: Data) throws -> JSON {
        var p = JSONParser(data)
        p.skipWS()
        let v = try p.value()
        return v
    }

    private mutating func skipWS() {
        while i < s.count, s[i] == 0x20 || s[i] == 0x09 || s[i] == 0x0A || s[i] == 0x0D { i += 1 }
    }

    private mutating func value() throws -> JSON {
        skipWS()
        guard i < s.count else { throw CLIError("JSON 意外结束") }
        switch s[i] {
        case UInt8(ascii: "{"): return try object()
        case UInt8(ascii: "["): return try array()
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): i += 4; return .bool(true)
        case UInt8(ascii: "f"): i += 5; return .bool(false)
        case UInt8(ascii: "n"): i += 4; return .null
        default: return .number(number())
        }
    }

    private mutating func object() throws -> JSON {
        i += 1
        var pairs: [(String, JSON)] = []
        skipWS()
        if i < s.count, s[i] == UInt8(ascii: "}") { i += 1; return .object(pairs) }
        while true {
            skipWS()
            let k = try string()
            skipWS()
            guard i < s.count, s[i] == UInt8(ascii: ":") else { throw CLIError("JSON 缺少 :") }
            i += 1
            pairs.append((k, try value()))
            skipWS()
            guard i < s.count else { throw CLIError("JSON 对象未闭合") }
            if s[i] == UInt8(ascii: ",") { i += 1; continue }
            if s[i] == UInt8(ascii: "}") { i += 1; return .object(pairs) }
            throw CLIError("JSON 对象里遇到意外字符")
        }
    }

    private mutating func array() throws -> JSON {
        i += 1
        var items: [JSON] = []
        skipWS()
        if i < s.count, s[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
        while true {
            items.append(try value())
            skipWS()
            guard i < s.count else { throw CLIError("JSON 数组未闭合") }
            if s[i] == UInt8(ascii: ",") { i += 1; continue }
            if s[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
            throw CLIError("JSON 数组里遇到意外字符")
        }
    }

    private mutating func string() throws -> String {
        guard i < s.count, s[i] == UInt8(ascii: "\"") else { throw CLIError("JSON 缺少字符串") }
        i += 1
        var out = [UInt8]()
        while i < s.count {
            let c = s[i]
            if c == UInt8(ascii: "\"") { i += 1; return String(decoding: out, as: UTF8.self) }
            if c == UInt8(ascii: "\\") {
                i += 1
                guard i < s.count else { break }
                switch s[i] {
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "u"):
                    let hex = String(decoding: s[(i + 1)...min(i + 4, s.count - 1)], as: UTF8.self)
                    if let cp = UInt32(hex, radix: 16), let sc = Unicode.Scalar(cp) {
                        out.append(contentsOf: Array(String(Character(sc)).utf8))
                    }
                    i += 4
                default: out.append(s[i])
                }
                i += 1
                continue
            }
            out.append(c)
            i += 1
        }
        throw CLIError("JSON 字符串未闭合")
    }

    private mutating func number() -> String {
        let start = i
        while i < s.count {
            let c = s[i]
            let isNum = (c >= 0x30 && c <= 0x39) || c == UInt8(ascii: "-") || c == UInt8(ascii: "+")
                || c == UInt8(ascii: ".") || c == UInt8(ascii: "e") || c == UInt8(ascii: "E")
            if !isNum { break }
            i += 1
        }
        return String(decoding: s[start..<i], as: UTF8.self)
    }
}

// ---------------------------------------------------------------- 序列化

func canonicalJSON(_ v: JSON) -> Data {
    var out = Data()
    encode(v, into: &out)
    return out
}

private func encode(_ v: JSON, into out: inout Data) {
    switch v {
    case .object(let pairs):
        out.append(UInt8(ascii: "{"))
        for (n, (k, val)) in pairs.enumerated() {
            if n > 0 { out.append(UInt8(ascii: ",")) }
            encodeString(k, into: &out)
            out.append(UInt8(ascii: ":"))
            encode(val, into: &out)
        }
        out.append(UInt8(ascii: "}"))
    case .array(let items):
        out.append(UInt8(ascii: "["))
        for (n, item) in items.enumerated() {
            if n > 0 { out.append(UInt8(ascii: ",")) }
            encode(item, into: &out)
        }
        out.append(UInt8(ascii: "]"))
    case .string(let s): encodeString(s, into: &out)
    case .number(let n): out.append(contentsOf: Array(n.utf8))
    case .bool(let b): out.append(contentsOf: Array((b ? "true" : "false").utf8))
    case .null: out.append(contentsOf: Array("null".utf8))
    }
}

/// 转义规则对齐 Python 的 json.dumps(ensure_ascii=False)：
/// 只转义 `"`、`\` 与控制字符；`/` 与非 ASCII 一律原样输出。
private func encodeString(_ s: String, into out: inout Data) {
    out.append(UInt8(ascii: "\""))
    for scalar in s.unicodeScalars {
        switch scalar {
        case "\"": out.append(contentsOf: Array("\\\"".utf8))
        case "\\": out.append(contentsOf: Array("\\\\".utf8))
        case "\n": out.append(contentsOf: Array("\\n".utf8))
        case "\t": out.append(contentsOf: Array("\\t".utf8))
        case "\r": out.append(contentsOf: Array("\\r".utf8))
        case "\u{08}": out.append(contentsOf: Array("\\b".utf8))
        case "\u{0C}": out.append(contentsOf: Array("\\f".utf8))
        default:
            if scalar.value < 0x20 {
                out.append(contentsOf: Array(String(format: "\\u%04x", scalar.value).utf8))
            } else {
                out.append(contentsOf: Array(String(scalar).utf8))
            }
        }
    }
    out.append(UInt8(ascii: "\""))
}
