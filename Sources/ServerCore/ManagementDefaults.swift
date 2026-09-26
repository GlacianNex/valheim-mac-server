import Foundation
import Darwin

/// Installs defaults only on stopped servers. An explicit false remains an opt-out.
public enum ManagementDefaults {
    @discardableResult
    public static func installWhileStopped(paths: Paths, package: URL? = ManagedServer.package) throws -> Bool {
        let store = try Store(paths:paths)
        guard let id = paths.profileID, try store.load().managedServers?[id] == nil else { return false }
        guard FileManager.default.isExecutableFile(atPath:paths.executable.path) else { return false }
        let maintenance = try MaintenanceLease(paths:paths,exclusive:false)
        defer { withExtendedLifetime(maintenance) {} }
        let runtime = try RuntimeLease(paths:paths,exclusive:false)
        defer { withExtendedLifetime(runtime) {} }
        let fd = open(paths.file("service.lock").path,O_CREAT | O_RDWR | O_CLOEXEC,0o600)
        guard fd >= 0 else { throw MonitorError("Cannot check server state for management setup.") }
        defer { close(fd) }
        guard flock(fd,LOCK_EX | LOCK_NB) == 0 else { return false }
        defer { flock(fd,LOCK_UN) }
        let lifecycle = Lifecycle(paths:paths)
        if let record = lifecycle.record, lifecycle.owns(record) { return false }
        return try installBeforeLaunch(paths:paths,package:package)
    }

    /// Caller must own the service lock and a shared runtime lease (also used by runService).
    @discardableResult
    static func installBeforeLaunch(paths: Paths, package: URL? = ManagedServer.package) throws -> Bool {
        let store = try Store(paths:paths)
        guard let id = paths.profileID, try store.load().managedServers?[id] == nil else { return false }
        return try store.update { db in
            guard db.profiles.contains(where: { $0.id == id }), db.managedServers?[id] == nil else { return false }
            // Commit the default only after a verified installation succeeds. Failure leaves
            // the old preference and world intact, so the migration can safely be retried.
            try ManagedServer(paths:paths).prepare(package:package)
            if db.managedServers == nil { db.managedServers = [:] }
            db.managedServers?[id] = true
            return true
        }
    }
}
