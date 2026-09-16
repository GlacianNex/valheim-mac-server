import Foundation

/// Retains readiness and the latest count while reading only newly appended log bytes.
/// Cache is process-local; relaunching the manager reconstructs it from the current log.
final class ServerLogReader {
    static let shared = ServerLogReader()
    private struct Entry {
        var inode: UInt64
        var offset: UInt64 = 0
        var pending = Data()
        var online = false, players = "", code = ""
    }
    private var entries: [URL: Entry] = [:]
    private let lock = NSLock()

    func read(_ url: URL) -> (online: Bool, players: String, code: String) {
        lock.lock(); defer { lock.unlock() }
        guard let file = try? FileHandle(forReadingFrom: url) else {
            entries.removeValue(forKey: url); return (false, "", "")
        }
        defer { try? file.close() }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
            let end = try file.seekToEnd()
            var entry = entries[url] ?? Entry(inode: inode)
            if entry.inode != inode || end < entry.offset { entry = Entry(inode: inode) }
            try file.seek(toOffset: entry.offset)
            while entry.offset < end {
                let data = try file.read(upToCount: Int(min(65_536, end - entry.offset))) ?? Data()
                if data.isEmpty { break }
                entry.offset += UInt64(data.count)
                entry.pending.append(data)
                if let newline = entry.pending.lastIndex(of: 10) {
                    let events = Lifecycle.logEvents(String(decoding: entry.pending[...newline], as: UTF8.self))
                    entry.online = entry.online || events.online
                    if let players = events.players { entry.players = players }
                    if !events.code.isEmpty { entry.code = events.code }
                    entry.pending = Data(entry.pending.dropFirst(newline + 1))
                }
                // Server status messages are short; bound memory for malformed giant lines.
                if entry.pending.count > 65_536 { entry.pending = Data(entry.pending.suffix(4096)) }
            }
            if entries[url] == nil && entries.count >= 64 { entries.removeAll() }
            entries[url] = entry
            return (entry.online, entry.players, entry.code)
        } catch {
            entries.removeValue(forKey: url); return (false, "", "")
        }
    }
}
