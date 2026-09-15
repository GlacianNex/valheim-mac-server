import Foundation
import Darwin

public final class Fleet {
    public let paths: Paths
    public init(paths: Paths) { self.paths = Paths(root: paths.root) }
    public static func state(for servers: [ServerStatus]) -> String {
        let running = servers.filter { $0.running }
        if running.contains(where: { $0.state == "Stopping" }) { return "Stopping" }
        if running.contains(where: { $0.state == "Starting" }) { return "Starting" }
        if running.contains(where: { $0.state == "Online" }) { return "Online" }
        return running.isEmpty ? "Stopped" : "Starting"
    }
    public func lifecycles() throws -> [Lifecycle] {
        let store = try Store(paths: paths), db = try store.load()
        return db.profiles.map { Lifecycle(paths: store.servicePaths($0.id, database: db)) }
    }
    public func statuses() throws -> [ServerStatus] { try lifecycles().map { try $0.status() } }
    public func runningIDs() throws -> [String] { try lifecycles().filter { $0.isActive }.compactMap { $0.paths.profileID } }
    public func resumeIDs() throws -> [String] {
        let store = try Store(paths: paths), db = try store.load(), running = Set(try runningIDs())
        return db.profiles.filter { running.contains($0.id) || store.autostart($0.id, database: db) }.map(\.id)
    }
    public func stopAll() throws {
        let servers = try lifecycles().filter { $0.isActive }
        for server in servers { try server.requestStop(wait: false) }
        for server in servers { try server.requestStop() }
    }
    public func start(_ ids: [String]) throws {
        let store = try Store(paths: paths), db = try store.load()
        var failures: [String] = []
        for id in Set(ids).sorted() {
            guard let profile = db.profiles.first(where: { $0.id == id }) else { failures.append("Profile no longer exists: " + id); continue }
            do { try LoginItems(paths: store.servicePaths(id, database: db)).start() }
            catch { failures.append(profile.label + ": " + error.localizedDescription) }
        }
        if !failures.isEmpty { throw MonitorError(failures.joined(separator: "\n")) }
    }
    public func checkProfilePorts(_ profile: Profile) throws {
        let store = try Store(paths: paths), db = try store.load()
        for other in db.profiles where other.id != profile.id {
            if abs(other.port - profile.port) <= 1,
               Lifecycle(paths: store.servicePaths(other.id, database: db)).isActive {
                throw MonitorError("UDP ports overlap with \(other.label). Choose a different port pair for \(profile.label).")
            }
        }
        try Lifecycle.checkPorts(profile.port)
    }
}

/// Services share the runtime; replacement takes exclusive ownership.
public final class RuntimeLease {
    private let fd: Int32
    public init(paths: Paths, exclusive: Bool) throws {
        fd = open(paths.root.appendingPathComponent("runtime.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw MonitorError("Cannot lock the server runtime.") }
        guard flock(fd, (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB) == 0 else {
            close(fd)
            throw MonitorError(exclusive ? "Stop all servers before updating the shared runtime." : "The app or server runtime is being updated. Try starting this server afterward.")
        }
    }
    deinit { flock(fd, LOCK_UN); close(fd) }
}
