import Foundation

public struct Database: Codable {
    public var schema = 1
    public var profiles: [Profile] = []
    public var selected = ""
    public var autostart = false
    public var monitorAtLogin = false
    public init() {}
}
public final class Store {
    public let paths: Paths
    public init(paths: Paths = Paths()) throws { self.paths = paths; try paths.prepare() }
    public func load() throws -> Database {
        guard FileManager.default.fileExists(atPath: paths.file("profiles.json").path) else { return Database() }
        let db = try JSONDecoder().decode(Database.self, from: Data(contentsOf: paths.file("profiles.json")))
        guard db.schema == 1 else { throw MonitorError("This profile database needs a newer version of the app.") }
        return db
    }
    public func update<T>(_ operation: (inout Database) throws -> T) throws -> T {
        try withLock(paths.file("profiles.lock")) {
            var db = try load()
            let result = try operation(&db)
            try atomicWrite(encode(db), to: paths.file("profiles.json"))
            return result
        }
    }
    public func saveDirectory(_ profile: Profile) -> URL { paths.file("worlds/" + profile.id) }
    @discardableResult public func save(_ profile: Profile, importSource: URL? = nil) throws -> String {
        try profile.validate()
        return try update { db in
            let old = db.profiles.first { $0.id == profile.id }
            if old != nil && db.selected == profile.id && Lifecycle(paths: paths).isActive { throw MonitorError("Stop this server before editing its profile.") }
            if let old, old.world != profile.world { throw MonitorError("Existing world filenames cannot be changed. Create another profile instead.") }
            guard !db.profiles.contains(where: { $0.id != profile.id && $0.label.caseInsensitiveCompare(profile.label) == .orderedSame }) else { throw MonitorError("A profile already has this name.") }
            let directory = saveDirectory(profile)
            if old == nil {
                guard !FileManager.default.fileExists(atPath: directory.path) else { throw MonitorError("A world directory already exists for this identifier.") }
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    if let importSource { try WorldImport.copy(source: importSource, world: profile.world, destination: directory.appendingPathComponent("worlds_local"), scratch: paths.root) }
                } catch { try? FileManager.default.removeItem(at: directory); throw error }
            }
            if let index = db.profiles.firstIndex(where: { $0.id == profile.id }) { db.profiles[index] = profile }
            else { db.profiles.append(profile) }
            if db.selected.isEmpty { db.selected = profile.id }
            return profile.id
        }
    }
    public func select(_ id: String) throws {
        try update { db in
            guard !Lifecycle(paths: paths).isActive else { throw MonitorError("Stop the current server before switching profiles.") }
            guard db.profiles.contains(where: { $0.id == id }) else { throw MonitorError("Profile not found.") }
            db.selected = id
        }
    }
    public func selected() throws -> Profile {
        let db = try load()
        guard let profile = db.profiles.first(where: { $0.id == db.selected }) else { throw MonitorError("Create a server profile first.") }
        return profile
    }
    public func writeAccessLists(_ profile: Profile) throws {
        for (name, text) in [("adminlist.txt", profile.admins), ("bannedlist.txt", profile.banned), ("permittedlist.txt", profile.permitted)] {
            try atomicWrite(Data(text.replacingOccurrences(of: ",", with: "\n").utf8), to: saveDirectory(profile).appendingPathComponent(name))
        }
    }
}
