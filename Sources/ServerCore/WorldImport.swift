import Foundation

public enum WorldImport {
    public static func copy(source: URL, world: String, destination: URL, scratch: URL) throws {
        let fm = FileManager.default
        let staging = scratch.appendingPathComponent("import-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        if source.pathExtension.lowercased() == "zip" {
            let listing = try command("/usr/bin/unzip", ["-Z1", source.path])
            guard listing.code == 0 else { throw MonitorError("Cannot read this ZIP archive.") }
            for name in listing.output.split(separator: "\n") {
                let normalized = name.replacingOccurrences(of: "\\", with: "/")
                guard !normalized.hasPrefix("/"), !normalized.split(separator: "/").contains(".."), !normalized.contains(":") else { throw MonitorError("The ZIP contains an unsafe path.") }
            }
            let details = try command("/usr/bin/zipinfo", ["-l", source.path])
            guard details.code == 0 else { throw MonitorError("Cannot inspect the ZIP archive.") }
            var bytes: UInt64 = 0
            for line in details.output.split(separator: "\n") {
                let columns = line.split(whereSeparator: \.isWhitespace)
                if let first = columns.first, first.count == 10, ["-", "d", "l"].contains(String(first.prefix(1))) {
                    guard !first.hasPrefix("l") else { throw MonitorError("ZIP symbolic links are not supported.") }
                    if columns.count > 3, let size = UInt64(columns[3]) { bytes += size }
                }
            }
            guard bytes <= 8 * 1024 * 1024 * 1024 else { throw MonitorError("The expanded world ZIP exceeds 8 GB.") }
            try checkCommand("/usr/bin/ditto", ["-x", "-k", source.path, staging.path])
        } else {
            try rejectLinks(source)
            let isDirectory = (try source.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
            if isDirectory { try fm.copyItem(at: source, to: staging.appendingPathComponent(source.lastPathComponent)) }
            else if source.pathExtension.lowercased() == "db", fm.fileExists(atPath: source.deletingPathExtension().appendingPathExtension("fwl").path) {
                let partner = source.deletingPathExtension().appendingPathExtension("fwl")
                try rejectLinks(partner)
                try fm.copyItem(at: source, to: staging.appendingPathComponent(source.lastPathComponent))
                try fm.copyItem(at: partner, to: staging.appendingPathComponent(partner.lastPathComponent))
            } else { throw MonitorError("Choose a world ZIP, world folder, or .db file with its matching .fwl.") }
        }
        try rejectLinks(staging)
        let all = fm.enumerator(at: staging, includingPropertiesForKeys: [.isDirectoryKey])?.allObjects as? [URL] ?? []
        let modern = Set(all.filter { $0.pathExtension == "fwl2" }.map { $0.deletingLastPathComponent() })
        let legacy = all.filter { $0.pathExtension == "db" && fm.fileExists(atPath: $0.deletingPathExtension().appendingPathExtension("fwl").path) }
        guard modern.count + legacy.count == 1 else { throw MonitorError("Import must contain exactly one complete world.") }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        if let folder = modern.first {
            let contents = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            guard folder.lastPathComponent == world else { throw MonitorError("Set World filename to \(folder.lastPathComponent) to match the imported world.") }
            guard contents.contains(where: { $0.pathExtension == "db2" }), contents.contains(where: { $0.pathExtension == "ok" }) else { throw MonitorError("The world folder is incomplete.") }
            try fm.copyItem(at: folder, to: destination.appendingPathComponent(world))
        } else if let db = legacy.first {
            guard db.deletingPathExtension().lastPathComponent == world else { throw MonitorError("Set World filename to \(db.deletingPathExtension().lastPathComponent) to match the imported world.") }
            try fm.copyItem(at: db, to: destination.appendingPathComponent(db.lastPathComponent))
            let fwl = db.deletingPathExtension().appendingPathExtension("fwl")
            try fm.copyItem(at: fwl, to: destination.appendingPathComponent(fwl.lastPathComponent))
        }
    }
    private static func rejectLinks(_ root: URL) throws {
        let all = [root] + (FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])?.allObjects as? [URL] ?? [])
        for url in all where (try url.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true { throw MonitorError("World imports cannot contain symbolic links.") }
    }
}
