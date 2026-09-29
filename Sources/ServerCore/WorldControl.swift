import Foundation
import CryptoKit
import Darwin

public struct WorldMessageSettings: Codable {
    public var welcome = ""
    public var announcements: [String] = []
    public init() {}
    public static func validate(_ text: String, allowEmpty: Bool = false) throws {
        guard (allowEmpty || !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty), text.utf16.count <= 500,
              !text.contains("\n"), !text.contains("\r"), !text.contains("\0") else { throw MonitorError("Use one line, up to 500 characters.") }
    }
    public static func load(paths: Paths) throws -> Self {
        let url = paths.stateRoot.appendingPathComponent("world-control.json")
        guard FileManager.default.fileExists(atPath:url.path) else { return Self() }
        return try JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
    }
    public func save(paths: Paths) throws {
        try Self.validate(welcome,allowEmpty:true)
        guard announcements.count <= 50 else { throw MonitorError("Keep up to 50 saved announcements.") }
        for text in announcements { try Self.validate(text) }
        try atomicWrite(JSONEncoder().encode(self),to:paths.stateRoot.appendingPathComponent("world-control.json"))
    }
}
public struct WorldBackup: Codable {
    public let id: String
    public let name: String
    public let date: Date
    public let profile: String
    public let world: String
    public let files: [String:String]
}
public final class WorldBackups {
    public let paths: Paths
    public init(paths: Paths) { self.paths = paths }
    public var directory: URL { paths.root.appendingPathComponent("backups/" + (paths.profileID ?? "")) }
    private let fm = FileManager.default
    public func list() throws -> [WorldBackup] {
        guard fm.fileExists(atPath:directory.path) else { return [] }
        return try fm.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).compactMap {
            guard let item = try? JSONDecoder().decode(WorldBackup.self,from:Data(contentsOf:$0.appendingPathComponent("manifest.json"))),
                  item.id == $0.lastPathComponent, item.profile == paths.profileID else { return nil }; return item
        }.sorted { $0.date > $1.date }
    }
    private func stopped<T>(_ action: (Profile, URL) throws -> T) throws -> T {
        try paths.prepare()
        let lease = try MaintenanceLease(paths:paths,exclusive:false); defer { withExtendedLifetime(lease) {} }
        let fd = open(paths.file("service.lock").path,O_CREAT | O_RDWR | O_CLOEXEC,0o600)
        guard fd >= 0 else { throw MonitorError("Cannot lock this server.") }; defer { close(fd) }
        guard flock(fd,LOCK_EX | LOCK_NB) == 0 else { throw MonitorError("Stop this server before creating or restoring a backup.") }
        defer { flock(fd,LOCK_UN) }
        let life = Lifecycle(paths:paths)
        if let record = life.record, life.owns(record) { throw MonitorError("Stop this server first.") }
        return try withLock(paths.file("profiles.lock")) {
            let store = try Store(paths:paths), profile = try store.selected()
            guard profile.id == paths.profileID else { throw MonitorError("Select a server.") }
            return try action(profile,store.saveDirectory(profile).appendingPathComponent("worlds_local"))
        }
    }
    private func digest(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom:file); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount:1_048_576), !data.isEmpty { hash.update(data:data) }
        return hash.finalize().map { String(format:"%02x",$0) }.joined()
    }
    private func inventory(_ root: URL) throws -> [String:String] {
        guard (try root.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink != true else { throw MonitorError("Backups cannot contain symbolic links.") }
        var result: [String:String] = [:]
        guard let enumerator = fm.enumerator(at:root,includingPropertiesForKeys:[.isSymbolicLinkKey,.isRegularFileKey]) else { throw MonitorError("Cannot read world files.") }
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys:[.isSymbolicLinkKey,.isRegularFileKey])
            guard values.isSymbolicLink != true else { throw MonitorError("Backups cannot contain symbolic links.") }
            if values.isRegularFile == true { result[file.resolvingSymlinksInPath().pathComponents.dropFirst(root.resolvingSymlinksInPath().pathComponents.count).joined(separator:"/")] = try digest(file) }
        }
        guard !result.isEmpty else { throw MonitorError("No saved world exists yet.") }; return result
    }
    private func completeWorld(_ files: [String:String], world: String) -> Bool {
        if files[world + ".db"] != nil && files[world + ".fwl"] != nil { return true }
        let names = files.keys.filter { $0.hasPrefix(world + "/") }
        return [".db2",".fwl2",".ok"].allSatisfy { suffix in names.contains { $0.hasSuffix(suffix) } }
    }
    private func createLocked(name: String, profile: Profile, source: URL) throws -> WorldBackup {
        let name = name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100 else { throw MonitorError("Enter a backup name, up to 100 characters.") }
        let files = try inventory(source)
        guard completeWorld(files,world:profile.world) else { throw MonitorError("The saved world is incomplete.") }
        let item = WorldBackup(id:UUID().uuidString,name:name,date:Date(),profile:profile.id,world:profile.world,files:files)
        let folder = directory.appendingPathComponent(item.id), stage = directory.appendingPathComponent(".staging-" + UUID().uuidString)
        try fm.createDirectory(at:stage,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        defer { try? fm.removeItem(at:stage) }
        let data = stage.appendingPathComponent("worlds_local")
        try fm.copyItem(at:source,to:data)
        guard try inventory(data) == files else { throw MonitorError("Backup verification failed; world unchanged.") }
        try atomicWrite(encode(item),to:stage.appendingPathComponent("manifest.json"))
        try fm.moveItem(at:stage,to:folder); return item
    }
    @discardableResult public func create(name: String) throws -> WorldBackup { try stopped { try createLocked(name:name,profile:$0,source:$1) } }
    public func restore(id: String) throws {
        guard UUID(uuidString:id) != nil else { throw MonitorError("Invalid backup identifier.") }
        try stopped { profile, target in
            guard let backup = try list().first(where:{$0.id == id}), backup.world == profile.world else { throw MonitorError("Backup does not belong to this world.") }
            let source = directory.appendingPathComponent(id + "/worlds_local")
            guard try inventory(source) == backup.files, completeWorld(backup.files,world:profile.world) else { throw MonitorError("Backup verification failed; world unchanged.") }
            let stage = target.deletingLastPathComponent().appendingPathComponent("restore-" + UUID().uuidString)
            try fm.copyItem(at:source,to:stage); defer { try? fm.removeItem(at:stage) }
            guard try inventory(stage) == backup.files else { throw MonitorError("Restore verification failed.") }
            if fm.fileExists(atPath:target.path) { _ = try createLocked(name:"Before restore — " + String(backup.name.prefix(60)),profile:profile,source:target) }
            let previous = target.deletingLastPathComponent().appendingPathComponent("before-restore-" + UUID().uuidString)
            let exists = fm.fileExists(atPath:target.path)
            if exists { try fm.moveItem(at:target,to:previous) }
            do { try fm.moveItem(at:stage,to:target) }
            catch { if exists { try fm.moveItem(at:previous,to:target) }; throw error }
            // Keep the previous directory as an additional recovery copy; never delete a user's world here.
        }
    }
}
