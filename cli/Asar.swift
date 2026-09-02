import Foundation

// asar 读写。两个易错点（Python 版注释里写着，往返测试盯着）：
//   1) pickle 头：inner = align4(4 + json_len)，outer = 4 + inner，
//      写入 (4, outer, inner, json_len)。
//   2) 内容去重：多个条目可共享同一 (offset,size)（如相同的 woff2），
//      必须按块去重写一次，并让共享它的所有条目指向同一新 offset。
// header 用保序 JSON（见 JSONOrdered.swift），否则重打包的字节顺序就变了。

let ASAR_BLOCK = 4194304

func asarIntegrity(_ buf: Data, blockSize: Int = ASAR_BLOCK) -> JSON {
    var blocks: [JSON] = []
    var i = 0
    while i < buf.count {
        blocks.append(.string(sha256Hex(buf.subdata(in: i..<min(i + blockSize, buf.count)))))
        i += blockSize
    }
    if blocks.isEmpty { blocks = [.string(sha256Hex(Data()))] }
    return .object([("algorithm", .string("SHA256")),
                    ("hash", .string(sha256Hex(buf))),
                    ("blockSize", .number(String(blockSize))),
                    ("blocks", .array(blocks))])
}

struct AsarHeader {
    var root: JSON
    let base: Int          // 内容区起始偏移
}

private func readHead(_ url: URL) throws -> (jsonLen: Int, pickleSize: Int, fh: FileHandle) {
    let fh = try FileHandle(forReadingFrom: url)
    guard let head = try fh.read(upToCount: 16), head.count == 16 else {
        try? fh.close()
        throw CLIError("asar 文件过小")
    }
    let v: [UInt32] = head.withUnsafeBytes { raw in
        (0..<4).map {
            UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))
        }
    }
    return (Int(v[3]), Int(v[1]), fh)
}

func asarReadHeader(_ url: URL) throws -> AsarHeader {
    let (jsonLen, pickleSize, fh) = try readHead(url)
    defer { try? fh.close() }
    guard let hdrData = try fh.read(upToCount: jsonLen) else {
        throw CLIError("asar 头读取失败")
    }
    return AsarHeader(root: try JSONParser.parse(hdrData), base: 8 + pickleSize)
}

/// header JSON 的 SHA256——Info.plist 里 ElectronAsarIntegrity 记的就是它。
func asarHeaderHash(_ url: URL) throws -> String {
    let (jsonLen, _, fh) = try readHead(url)
    defer { try? fh.close() }
    guard let hdr = try fh.read(upToCount: jsonLen) else { throw CLIError("asar 头读取失败") }
    return sha256Hex(hdr)
}

private struct BlockKey: Hashable { let off: Int; let size: Int }

/// 按原 offset 顺序重写内容区并重算 offset/size。
/// getBytes(相对路径, (offset, size)) -> 新内容
func asarPack(_ header: AsarHeader, _ out: URL,
              _ getBytes: (String, (Int, Int)) throws -> Data) throws {
    var root = header.root
    var blocks: [BlockKey: [[String]]] = [:]   // 块 -> 指向它的条目路径
    var order: [(BlockKey, String)] = []

    func walk(_ node: JSON, _ rel: String, _ path: [String]) {
        guard let files = node["files"]?.objectPairs else { return }
        for (name, entry) in files {
            let sub = rel + "/" + name
            let p = path + ["files", name]
            if entry["files"] != nil { walk(entry, sub, p); continue }
            if entry["link"] != nil { continue }
            if case .bool(true)? = entry["unpacked"] { continue }
            let off = entry["offset"]?.intValue ?? 0
            let size = entry["size"]?.intValue ?? 0
            let key = BlockKey(off: off, size: size)
            if blocks[key] == nil { blocks[key] = []; order.append((key, sub)) }
            blocks[key]!.append(p)
        }
    }
    walk(root, "", [])
    // 必须按 offset 排，不能按文件名——内容区顺序要与原文件一致
    order.sort { $0.0.off < $1.0.off }

    var blobs: [Data] = []
    var cursor = 0
    for (key, sub) in order {
        let data = try getBytes(sub, (key.off, key.size))
        if data.count != key.size && blocks[key]!.count > 1 {
            // 该内容块被多个条目共享，改它会殃及其它文件
            throw CLIError("拒绝修改被去重共享的内容块：\(sub)")
        }
        for path in blocks[key]! { updateEntry(&root, path, offset: cursor, data: data) }
        blobs.append(data)
        cursor += data.count
    }

    let hdrJSON = canonicalJSON(root)
    let jl = hdrJSON.count
    let inner = (4 + jl + 3) / 4 * 4
    let outer = 4 + inner
    var buf = Data()
    for x in [UInt32(4), UInt32(outer), UInt32(inner), UInt32(jl)] {
        withUnsafeBytes(of: x.littleEndian) { buf.append(contentsOf: $0) }
    }
    buf.append(hdrJSON)
    buf.append(Data(repeating: 0, count: inner - 4 - jl))
    for b in blobs { buf.append(b) }

    let tmp = URL(fileURLWithPath: out.path + ".tmp")
    try buf.write(to: tmp, options: .atomic)
    if FileManager.default.fileExists(atPath: out.path) {
        try FileManager.default.removeItem(at: out)
    }
    try FileManager.default.moveItem(at: tmp, to: out)
}

/// 沿路径把 offset/size/integrity 写回嵌套结构，保持键的原有顺序
private func updateEntry(_ root: inout JSON, _ path: [String], offset: Int, data: Data) {
    func rec(_ node: JSON, _ idx: Int) -> JSON {
        var n = node
        if idx >= path.count {
            n.set("offset", .string(String(offset)))
            n.set("size", .number(String(data.count)))
            if let old = n["integrity"] {
                n.set("integrity", asarIntegrity(
                    data, blockSize: old["blockSize"]?.intValue ?? ASAR_BLOCK))
            }
            return n
        }
        guard let child = n[path[idx]] else { return n }
        n.set(path[idx], rec(child, idx + 1))
        return n
    }
    root = rec(root, 0)
}

/// 从 asar 里取出某个文件的内容
func asarReadFile(_ url: URL, _ rel: String) throws -> Data? {
    let hdr = try asarReadHeader(url)
    var node = hdr.root
    for part in rel.split(separator: "/") {
        guard let files = node["files"], let next = files[String(part)] else { return nil }
        node = next
    }
    guard let off = node["offset"]?.intValue, let size = node["size"]?.intValue else { return nil }
    let fh = try FileHandle(forReadingFrom: url)
    defer { try? fh.close() }
    try fh.seek(toOffset: UInt64(hdr.base + off))
    return try fh.read(upToCount: size)
}

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ s: String) { description = s }
}
