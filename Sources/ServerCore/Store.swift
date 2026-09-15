import Foundation
import Darwin

public struct Database: Codable {
    public var schema = 1
    public var profiles: [Profile] = []
    public var selected = ""
    public var autostart = false
    public var monitorAtLogin = false
    public var legacyProfile: String?
    public var profileAutostart: [String: Bool]?
    public init() {}
}
public final class Store {
    public let paths: Paths
    public init(paths: Paths = Paths()) throws { self.paths = paths; try paths.prepare() }
    public func load() throws -> Database {
        guard FileManager.default.fileExists(atPath: paths.file("profiles.json").path) else { return Database() }
        let db = try JSONDecoder().decode(Database.self, from: Data(contentsOf: paths.file("profiles.json")))
        guard db.schema == 1 || db.schema == 2 else { throw MonitorError("This profile database needs a newer version of the app.") }
        return db
    }
    public func update<T>(_ operation: (inout Database) throws -> T) throws -> T {
        try withLock(paths.file("profiles.lock")) {
            var db = try load()
            if db.schema == 1 {
                let source = paths.file("profiles.json"), backup = paths.file("profiles-before-multiserver.json")
                if FileManager.default.fileExists(atPath: source.path), !FileManager.default.fileExists(atPath: backup.path) {
                    try atomicWrite(Data(contentsOf: source), to: backup)
                }
                db.legacyProfile = db.legacyProfile ?? db.selected
                db.profileAutostart = db.profileAutostart ?? [db.selected: db.autostart]
                db.schema = 2
            }
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
            if old != nil && Lifecycle(paths: servicePaths(profile.id, database: db)).isActive { throw MonitorError("Stop this server before editing its profile.") }
            if let old, (old.seed ?? "") != (profile.seed ?? "") { throw MonitorError("A world seed cannot be changed. Create a new server to use a different seed.") }
            if importSource != nil, !(profile.seed ?? "").isEmpty { throw MonitorError("Imported worlds keep their original seed. Clear World seed before importing.") }
            if let old, old.world != profile.world { throw MonitorError("Existing world filenames cannot be changed. Create another profile instead.") }
            guard !db.profiles.contains(where: { $0.id != profile.id && $0.label.caseInsensitiveCompare(profile.label) == .orderedSame }) else { throw MonitorError("A profile already has this name.") }
            let directory = saveDirectory(profile)
            if old == nil {
                guard !FileManager.default.fileExists(atPath: directory.path) else { throw MonitorError("A world directory already exists for this identifier.") }
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    if let importSource { try WorldImport.copy(source: importSource, world: profile.world, destination: directory.appendingPathComponent("worlds_local"), scratch: paths.root) }
                    else if let seed = profile.seed, !seed.isEmpty {
                        try WorldSeed.create(world: profile.world, seed: seed, saveDirectory: directory)
                    }
                } catch { try? FileManager.default.removeItem(at: directory); throw error }
            }
            if let index = db.profiles.firstIndex(where: { $0.id == profile.id }) { db.profiles[index] = profile }
            else { db.profiles.append(profile) }
            if db.selected.isEmpty { db.selected = profile.id }
            if db.legacyProfile?.isEmpty != false { db.legacyProfile = db.selected }
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
        guard let profile = db.profiles.first(where: { $0.id == (paths.profileID ?? db.selected) }) else { throw MonitorError("Create a server profile first.") }
        return profile
    }
    public func servicePaths(_ id: String, database: Database? = nil) -> Paths {
        let db = database ?? (try? load()) ?? Database()
        return Paths(root: paths.root, profileID: id, usesLegacyState: id == (db.legacyProfile ?? db.selected))
    }
    public func autostart(_ id: String, database: Database? = nil) -> Bool {
        let db = database ?? (try? load()) ?? Database()
        return db.profileAutostart?[id] ?? (id == (db.legacyProfile ?? db.selected) && db.autostart)
    }
    /// Remove a stopped server from the manager, keeping its world/settings recoverable.
    public func delete(_ id: String) throws -> URL {
        let recovery = paths.root.appendingPathComponent("deleted-servers/" + UUID().uuidString.lowercased())
        var movedWorld: URL?
        let scoped = servicePaths(id); try scoped.prepare()
        let fd = open(scoped.file("service.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw MonitorError("Cannot check server state.") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw MonitorError("Stop this server before deleting it.") }
        defer { flock(fd, LOCK_UN) }
        if let record = Lifecycle(paths: scoped).record, Lifecycle(paths: scoped).owns(record) { throw MonitorError("Stop this server before deleting it.") }
        do {
            return try update { db in
                guard let profile = db.profiles.first(where: { $0.id == id }) else { throw MonitorError("Server not found.") }
                try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try atomicWrite(encode(profile), to: recovery.appendingPathComponent("profile.json"))
                let world = saveDirectory(profile)
                if FileManager.default.fileExists(atPath: world.path) {
                    try FileManager.default.moveItem(at: world, to: recovery.appendingPathComponent("world"))
                    movedWorld = world
                }
                db.profiles.removeAll { $0.id == id }
                db.profileAutostart?.removeValue(forKey: id)
                if db.legacyProfile == id { db.autostart = false }
                if db.selected == id { db.selected = db.profiles.first?.id ?? "" }
                return recovery
            }
        } catch {
            if let world = movedWorld {
                do { try FileManager.default.moveItem(at: recovery.appendingPathComponent("world"), to: world) }
                catch { throw MonitorError("Deletion could not finish. The world is preserved at \(recovery.path).") }
            }
            throw error
        }
    }
    public func writeAccessLists(_ profile: Profile) throws {
        for (name, text) in [("adminlist.txt", profile.admins), ("bannedlist.txt", profile.banned), ("permittedlist.txt", profile.permitted)] {
            try atomicWrite(Data(text.replacingOccurrences(of: ",", with: "\n").utf8), to: saveDirectory(profile).appendingPathComponent(name))
        }
    }
}
