import Foundation

let KEEP_BACKUPS = 2

func humanSizeCLI(_ n: Int64) -> String {
    var v = Double(n)
    for unit in ["B", "KB", "MB", "GB", "TB"] {
        if v < 1024 || unit == "TB" {
            return (unit == "B" || unit == "KB")
                ? String(format: "%.0f %@", v, unit)
                : String(format: "%.1f %@", v, unit)
        }
        v /= 1024
    }
    return "\(n) B"
}

enum Backup {
    static func path(_ t: AppTarget, _ version: String) -> URL {
        P.dataDir.appendingPathComponent("Claude-backup-\(version)\(t.slug).app")
    }

    static func allBackups() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: P.dataDir, includingPropertiesForKeys: nil)) ?? []
        return items.filter {
            $0.lastPathComponent.hasPrefix("Claude-backup-")
                && $0.lastPathComponent.hasSuffix(".app")
        }
    }

    /// 只列当前目标的备份，按新到旧。
    /// 备份名形如 Claude-backup-<版本>[-<8位哈希>].app；带哈希的属于非默认目标。
    static func list(_ t: AppTarget) -> [URL] {
        let slug = t.slug
        var out: [URL] = []
        for p in allBackups() {
            let stem = String(p.lastPathComponent.dropFirst("Claude-backup-".count)
                                                 .dropLast(".app".count))
            let m = trailingSlug(stem)
            if slug.isEmpty { if m == nil { out.append(p) } }
            else if m == slug { out.append(p) }
        }
        return out.sorted {
            (mtime($0) ?? .distantPast) > (mtime($1) ?? .distantPast)
        }
    }

    private static func trailingSlug(_ stem: String) -> String? {
        guard stem.count > 9 else { return nil }
        let tail = String(stem.suffix(9))
        guard tail.hasPrefix("-") else { return nil }
        let hex = tail.dropFirst()
        return hex.allSatisfy { $0.isHexDigit && !$0.isUppercase } ? tail : nil
    }

    static func version(_ p: URL) -> String? {
        var stem = String(p.lastPathComponent.dropFirst("Claude-backup-".count)
                                             .dropLast(".app".count))
        if let s = trailingSlug(stem) { stem = String(stem.dropLast(s.count)) }
        return stem
    }

    private static func mtime(_ u: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date
    }

    /// 当前已安装版本对应的整包备份（打补丁前留的原版，签名是 Anthropic 的）。
    static func pristineForCurrent(_ t: AppTarget) -> URL? {
        guard let v = t.version else { return nil }
        let p = path(t, v)
        return FileManager.default.fileExists(
            atPath: p.appendingPathComponent("Contents/Info.plist").path) ? p : nil
    }

    /// APFS 克隆的块是共享的，这里给的是逻辑大小，实际占盘只会更小。
    static func size(_ p: URL) -> Int64 {
        let r = run(["du", "-sk", p.path])
        guard let first = r.out.split(separator: "\n").first,
              let kb = Int64(first.split(separator: "\t").first?
                .trimmingCharacters(in: .whitespaces) ?? "") else { return 0 }
        return kb * 1024
    }

    static func make(_ t: AppTarget, _ version: String) throws {
        try FileManager.default.createDirectory(at: P.dataDir, withIntermediateDirectories: true)
        let dest = path(t, version)
        if FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("Contents/Info.plist").path) {
            ok("当前版本 \(version) 的备份已存在，跳过：\(dest.path)")
            return
        }
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: HOME)
        let free = (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? Int64.max
        if free < 3 * 1024 * 1024 * 1024 {
            throw CLIError(String(format: "磁盘剩余空间不足 3GB（%.1fGB），中止",
                                  Double(free) / 1073741824))
        }
        info("整包备份（约 1 分钟）：ditto \(t.app.path) \(dest.path)")
        let r = run(["ditto", t.app.path, dest.path])
        if r.code != 0 {
            try? FileManager.default.removeItem(at: dest)
            throw CLIError("ditto 失败：\(r.out)")
        }
        ok("已备份到 \(dest.path)")
        let backups = list(t)
        if backups.count > KEEP_BACKUPS {
            for old in backups[KEEP_BACKUPS...] {
                info("清理旧备份：\(old.lastPathComponent)")
                try? FileManager.default.removeItem(at: old)
            }
        }
    }
}
