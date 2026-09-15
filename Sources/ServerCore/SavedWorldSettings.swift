import Foundation

/// Read-only metadata snapshot. Displayed values never become launch overrides.
public struct SavedWorldSettings {
    public let seed: String
    public let modifiers: [String: String]
    public let flags: [String: Bool]

    public static func read(profile: Profile, paths: Paths) throws -> SavedWorldSettings {
        let directory = try Store(paths: paths).saveDirectory(profile).appendingPathComponent("worlds_local/" + profile.world)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])) ?? []
        let generations = files.compactMap { url -> (Int, URL)? in
            let parts = url.lastPathComponent.split(separator: ".")
            guard parts.count == 3, parts[0] == "_main", parts[2] == "fwl2", let generation = Int(parts[1]),
                  FileManager.default.fileExists(atPath: directory.appendingPathComponent("_main.\(generation).ok").path),
                  FileManager.default.fileExists(atPath: directory.appendingPathComponent("_main.\(generation).db2").path) else { return nil }
            return (generation, url)
        }.sorted { $0.0 > $1.0 }
        let legacy = directory.appendingPathExtension("fwl")
        guard let file = generations.first?.1 ?? (FileManager.default.fileExists(atPath: legacy.path) ? legacy : nil) else { throw MonitorError("Saved world settings are not available yet.") }
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= 4_000_000 else { throw MonitorError("World metadata is not supported.") }
        return try decode(Data(contentsOf: file))
    }

    static func decode(_ data: Data) throws -> SavedWorldSettings {
        var reader = Reader(bytes: Array(data))
        guard try reader.uint32() == data.count - 4 else { throw MonitorError("World metadata is incomplete.") }
        let version = try reader.uint32()
        guard (26...41).contains(version) else { throw MonitorError("This world metadata version is not supported yet.") }
        _ = try reader.string() // World name.
        let seed = try reader.string()
        try reader.skip(4 + 8 + 4)
        if version >= 30 { guard try reader.byte() <= 1 else { throw MonitorError("Invalid world metadata.") } }
        let count = reader.offset == data.count && version < 30 ? 0 : try reader.uint32()
        guard count <= 4096 else { throw MonitorError("Invalid world settings count.") }
        var keys: [String] = []
        for _ in 0..<count { keys.append(try reader.string().lowercased()) }
        var modifiers = Dictionary(uniqueKeysWithValues: Profile.modifierChoices.keys.map { ($0, "default") })
        if let preset = keys.last(where: { $0.hasPrefix("preset ") }) {
            modifiers = Dictionary(uniqueKeysWithValues: Profile.modifierChoices.keys.map { ($0, "See saved preset: " + String(preset.dropFirst(7))) })
            for entry in preset.dropFirst(7).split(separator: ":") {
                guard let separator = entry.firstIndex(of: "_") else { continue }
                let name = String(entry[..<separator]), value = String(entry[entry.index(after: separator)...])
                if let key = Profile.modifierChoices.keys.first(where: { $0.lowercased() == name }) {
                    modifiers[key] = value
                }
            }
        }
        if let resource = keys.last(where: { $0.hasPrefix("resourcerate ") })?.split(separator: " ").last,
           let percent = Double(resource), percent.isFinite, percent >= 0 {
            modifiers["Resources"] = [50.0:"muchless",75:"less",100:"default",150:"more",200:"muchmore",300:"most"][percent] ?? "custom \(percent / 100)×"
        }
        return SavedWorldSettings(seed: seed, modifiers: modifiers, flags: Dictionary(uniqueKeysWithValues: Profile.flagNames.map { ($0, keys.contains($0)) }))
    }
    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        mutating func byte() throws -> UInt8 {
            guard offset < bytes.count else { throw MonitorError("World metadata is incomplete.") }
            defer { offset += 1 }; return bytes[offset]
        }
        mutating func uint32() throws -> Int {
            var result = 0
            for shift in stride(from: 0, through: 24, by: 8) { result |= Int(try byte()) << shift }
            return result
        }
        mutating func skip(_ count: Int) throws {
            guard count >= 0, count <= bytes.count - offset else { throw MonitorError("World metadata is incomplete.") }
            offset += count
        }
        mutating func string() throws -> String {
            var length = 0
            for shift in stride(from: 0, through: 28, by: 7) {
                let value = try byte(); length |= Int(value & 127) << shift
                if value & 128 == 0 {
                    guard length <= 65536, length <= bytes.count - offset else { throw MonitorError("Invalid world metadata string.") }
                    let end = offset + length
                    guard let result = String(bytes: bytes[offset..<end], encoding: .utf8) else { throw MonitorError("Invalid world metadata text.") }
                    offset = end; return result
                }
            }
            throw MonitorError("Invalid world metadata string length.")
        }
    }
}
