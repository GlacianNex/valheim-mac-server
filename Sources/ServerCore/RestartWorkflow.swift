import Foundation
import Darwin

/// Prevent another maintenance operation or a new server startup during a countdown.
/// Running services do not retain this lease.
public final class MaintenanceLease {
    private var fd: Int32
    public init(paths: Paths, exclusive: Bool = true) throws {
        fd = open(paths.root.appendingPathComponent("maintenance.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw MonitorError("Cannot coordinate server maintenance.") }
        guard flock(fd, (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB) == 0 else {
            close(fd); fd = -1
            throw MonitorError("Server maintenance is in progress. Wait for it to finish or cancel its countdown.")
        }
    }
    public func release() { if fd >= 0 { flock(fd, LOCK_UN); close(fd); fd = -1 } }
    deinit { release() }
}

public struct RestartWorkflow {
    public var now: () -> Date = Date.init
    public var sleep: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)
    public var validate: () throws -> Void
    public var warn: (Int) throws -> Void
    public var stop: () throws -> Void
    public var install: () throws -> Void
    public var start: () throws -> Void
    public var progress: (ServerUpdateProgress) -> Void
    public init(validate: @escaping () throws -> Void, warn: @escaping (Int) throws -> Void,
                stop: @escaping () throws -> Void, install: @escaping () throws -> Void,
                start: @escaping () throws -> Void, progress: @escaping (ServerUpdateProgress) -> Void) {
        self.validate = validate; self.warn = warn; self.stop = stop; self.install = install; self.start = start; self.progress = progress
    }
    public func run(deadline: Date?, updating: Bool = true) throws {
        if let deadline {
            var countdown = UpdateCountdown(now: deadline.addingTimeInterval(-UpdateCountdown.duration))
            while countdown.remaining(at: now()) > 0 {
                try validate()
                if let minutes = countdown.warning(at: now()) { try warn(minutes) }
                let left = Int(ceil(countdown.remaining(at: now())))
                progress(ServerUpdateProgress(.countdown, message: String(format: "Restart in %d:%02d",left/60,left%60)))
                sleep(min(1, countdown.remaining(at: now())))
            }
        }
        try validate()
        progress(ServerUpdateProgress(.stopping, message: "Saving worlds and stopping servers…"))
        try stop()
        if updating { progress(ServerUpdateProgress(.installing, message: "Updating server files…")) }
        try install()
        progress(ServerUpdateProgress(.starting, message: "Starting servers…"))
        try start()
    }
}

public enum MaintenanceLog {
    public static func write(paths: Paths, server: String, message: String) throws {
        let file = paths.root.appendingPathComponent("logs/maintenance.log")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try withLock(paths.root.appendingPathComponent("maintenance-log.lock")) {
            if !FileManager.default.fileExists(atPath: file.path) { try atomicWrite(Data(),to:file) }
            let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
            try handle.seekToEnd()
            let line = "\(ISO8601DateFormatter().string(from:Date())) [\(server)] \(message.replacingOccurrences(of:"\n",with:" "))\n"
            try handle.write(contentsOf:Data(line.utf8))
        }
    }
}
