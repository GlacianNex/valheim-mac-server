import Foundation

/// A new, ungenerated world's metadata. Never used to rewrite an existing world.
enum WorldSeed {
    static func validate(_ seed: String) throws {
        guard seed.utf8.count <= 10, seed.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }) else { throw MonitorError("World seed must be 1–10 letters or digits, or blank for random. Seeds are case-sensitive.") }
    }

    // Valheim's GetStableHashCode, with the same 32-bit overflow behavior.
    static func hash(_ seed: String) -> Int32 {
        var a: UInt32 = 5381, b: UInt32 = 5381
        for (i, c) in seed.utf16.enumerated() {
            if i % 2 == 0 { a = (a &* 33) ^ UInt32(c) }
            else { b = (b &* 33) ^ UInt32(c) }
        }
        return Int32(bitPattern: a &+ (b &* 1566083941))
    }

    static func create(world: String, seed: String, saveDirectory: URL) throws {
        try validate(seed)
        guard !seed.isEmpty else { return }
        let directory = saveDirectory.appendingPathComponent("worlds_local")
        // The caller allocates a fresh per-profile directory. Refuse even partial saves.
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            throw MonitorError("Cannot set a seed in an existing world directory.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var body = Writer()
        // Legacy, non-chunked metadata version 35 is accepted by the current server.
        // World generation 2 matches its new-world constructor; needsDB=false asks it
        // to generate terrain. It upgrades to chunked saves on its first save.
        body.integer(Int32(35))
        body.string(world); body.string(seed)
        body.integer(hash(seed))
        body.integer(Int64.random(in: 1...Int64.max))
        body.integer(Int32(2))
        body.data.append(0) // needsDB
        body.integer(Int32(0)) // starting global keys
        var file = Writer(); file.integer(Int32(body.data.count)); file.data.append(body.data)
        try atomicWrite(file.data, to: directory.appendingPathComponent(world + ".fwl"))
    }

    private struct Writer {
        var data = Data()
        mutating func integer<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        mutating func string(_ value: String) {
            let bytes = Data(value.utf8)
            var count = bytes.count
            repeat {
                data.append(UInt8(count & 127) | (count > 127 ? 128 : 0))
                count >>= 7
            } while count > 0
            data.append(bytes)
        }
    }
}
