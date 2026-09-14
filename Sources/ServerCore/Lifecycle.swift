import Foundation
import Darwin

public struct RunningRecord: Codable {
    public let pid: Int32
    public let executable: String
    public let started: String
    public let profile: String
    public let log: String
}
public struct ServerStatus: Codable {
    public var state = "Stopped", players = "", code = "", profileName = "No profile", selected = ""
    public var running = false, autostart = false, monitorAtLogin = false, installed = false
    public var profiles: [Summary] = []
    public var detail = ""
    public struct Summary: Codable { public let id: String; public let label: String }
}
public final class Lifecycle {
    public let paths: Paths
    public init(paths: Paths) { self.paths = paths }
    public static func bootID() -> String {
        var value = timeval(); var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &value, &size, nil, 0)
        return String(value.tv_sec)
    }
    public static func birth(_ pid: Int32) -> String {
        ((try? command("/bin/ps", ["-p", String(pid), "-o", "lstart="]).output) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func executable(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(cString: buffer)
    }
    public var record: RunningRecord? { try? JSONDecoder().decode(RunningRecord.self, from: Data(contentsOf: paths.file("running.json"))) }
    public func owns(_ record: RunningRecord) -> Bool {
        let actual = Self.executable(record.pid)
        guard !actual.isEmpty else { return false }
        let canonicalActual = URL(fileURLWithPath: actual).resolvingSymlinksInPath().path
        return record.executable == paths.executable.resolvingSymlinksInPath().path &&
            canonicalActual == record.executable && !record.started.isEmpty && Self.birth(record.pid) == record.started
    }
    public var isActive: Bool {
        if let record, owns(record) { return true }
        // The lock also covers the interval before the child PID has been recorded.
        let fd = open(paths.file("service.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return false }; defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 { return true }
        flock(fd, LOCK_UN); return false
    }
    public func status() throws -> ServerStatus {
        let db = try Store(paths: paths).load()
        var value = ServerStatus()
        value.autostart = db.autostart; value.monitorAtLogin = db.monitorAtLogin
        value.installed = FileManager.default.isExecutableFile(atPath: paths.executable.path)
        value.profiles = db.profiles.map { ServerStatus.Summary(id: $0.id, label: $0.label) }
        value.selected = db.selected; value.profileName = db.profiles.first { $0.id == db.selected }?.label ?? "No profile"
        value.running = isActive
        if value.running {
            value.state = FileManager.default.fileExists(atPath: paths.file("installing").path) ? "Installing" : "Starting"
            if requested("stop-request") { value.state = "Stopping" }
            if let record, owns(record) {
                let log = tail(URL(fileURLWithPath: record.log))
                let parsed = Self.parseLog(log)
                value.players = parsed.players; value.code = parsed.code
                let crossplay = db.profiles.first { $0.id == record.profile }?.crossplay ?? true
                let ready = crossplay ? !parsed.code.isEmpty : parsed.online
                if ready && value.state != "Stopping" { value.state = "Online" }
            }
        } else if !value.installed { value.state = "Setup needed" }
        value.detail = tail(paths.file("last-error.txt"), bytes: 4000)
        return value
    }
    public static func parseLog(_ log: String) -> (online: Bool, players: String, code: String) {
        func last(_ expression: String) -> String {
            guard let regex = try? NSRegularExpression(pattern: expression), let match = regex.matches(in: log, range: NSRange(log.startIndex..., in: log)).last,
                  let range = Range(match.range(at: 1), in: log) else { return "" }
            return String(log[range])
        }
        return (log.contains("Game server connected") || log.contains(" is active with "),
                last("(?:is active with|now) ([0-9]+) player"), last("with join code ([0-9]+)"))
    }
    public func requested(_ name: String) -> Bool { (try? String(contentsOf: paths.file(name), encoding: .utf8)) == Self.bootID() }
    public func requestStart() throws {
        try atomicWrite(Data(Self.bootID().utf8), to: paths.file("start-request"))
        try? FileManager.default.removeItem(at: paths.file("stop-request"))
        try? FileManager.default.removeItem(at: paths.file("last-error.txt"))
    }
    public func requestStop(wait: Bool = true) throws {
        try atomicWrite(Data(Self.bootID().utf8), to: paths.file("stop-request"))
        try? FileManager.default.removeItem(at: paths.file("start-request"))
        // A live service sends exactly one interrupt. Recover an orphan only after ownership checks.
        let fd = open(paths.file("service.lock").path, O_CREAT | O_RDWR, 0o600)
        if fd >= 0 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                defer { flock(fd, LOCK_UN) }
                if let record, owns(record) {
                    guard kill(record.pid, SIGINT) == 0 || errno == ESRCH else { close(fd); throw MonitorError("Could not request a clean shutdown.") }
                }
            }
            close(fd)
        }
        if wait {
            for _ in 0..<120 { if !isActive { return }; Thread.sleep(forTimeInterval: 1) }
            throw MonitorError("The server has not finished saving. It was not force-killed. Check the server log.")
        }
    }
    public static func checkPorts(_ base: Int) throws {
        guard (1...65534).contains(base) else { throw MonitorError("Port must be 1–65534.") }
        var descriptors: [Int32] = []
        defer { descriptors.forEach { close($0) } }
        for port in base...(base + 1) {
            let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard fd >= 0 else { throw MonitorError("Could not check UDP ports.") }
            descriptors.append(fd)
            var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET); address.sin_port = UInt16(port).bigEndian; address.sin_addr.s_addr = INADDR_ANY
            let result = withUnsafePointer(to: &address) { pointer in pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            guard result == 0 else { throw MonitorError("UDP port \(port) is already in use. Choose another port; the existing server was not touched.") }
        }
    }
    public func runService() throws {
        try paths.prepare()
        let fd = open(paths.file("service.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw MonitorError("Cannot create the service lock.") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return }
        defer { flock(fd, LOCK_UN) }
        if let record, owns(record) { return }
        try? FileManager.default.removeItem(at: paths.file("installing"))
        let store = try Store(paths: paths)
        let db = try store.load()
        guard !requested("stop-request"), db.autostart || requested("start-request") else { return }
        let profile = try store.selected(); try profile.validate()
        guard FileManager.default.isExecutableFile(atPath: paths.executable.path) else { throw MonitorError("Install the native server first.") }
        try Self.checkPorts(profile.port)
        try store.writeAccessLists(profile)
        let session = UUID().uuidString.lowercased()
        let log = paths.logs.appendingPathComponent("server-\(session).log")
        let console = paths.logs.appendingPathComponent("console-\(session).log")
        FileManager.default.createFile(atPath: console.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: console); defer { try? handle.close() }
        let child = Process(); child.executableURL = paths.executable
        child.currentDirectoryURL = paths.server
        child.arguments = try profile.arguments(saveDirectory: store.saveDirectory(profile), log: log)
        var environment = ProcessInfo.processInfo.environment; environment["SteamAppId"] = "892970"
        // The server depot omits steamclient.dylib. Use Valve's universal libraries already downloaded by SteamCMD.
        environment["DYLD_FALLBACK_LIBRARY_PATH"] = paths.file("runtime/steamcmd").path + ":/usr/local/lib:/usr/lib"
        child.environment = environment; child.standardInput = FileHandle.nullDevice; child.standardOutput = handle; child.standardError = handle
        let activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .automaticTerminationDisabled], reason: "Hosting a Valheim server")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        try child.run()
        let record = RunningRecord(pid: child.processIdentifier, executable: paths.executable.resolvingSymlinksInPath().path,
                                   started: Self.birth(child.processIdentifier), profile: profile.id, log: log.path)
        try atomicWrite(encode(record), to: paths.file("running.json"))
        try atomicWrite(Data(log.path.utf8), to: paths.file("latest-log"))
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        termination.setEventHandler { try? self.requestStop(wait: false) }; termination.resume()
        defer { termination.cancel() }
        var sentStop = false
        while child.isRunning {
            if requested("stop-request"), !sentStop { child.interrupt(); sentStop = true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        child.waitUntilExit()
        try? FileManager.default.removeItem(at: paths.file("running.json"))
        if !requested("stop-request") {
            throw MonitorError("The native server exited with code \(child.terminationStatus). See the server and console logs.")
        }
    }
}
