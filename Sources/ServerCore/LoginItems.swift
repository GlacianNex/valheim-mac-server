import Foundation

public final class LoginItems {
    public let paths: Paths
    public let executable: URL
    public static let serviceLabel = "io.github.glaciannex.valheimservermonitor.server"
    public static let monitorLabel = "io.github.glaciannex.valheimservermonitor.menu"
    public init(paths: Paths, executable: URL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL) {
        self.paths = paths; self.executable = executable
    }
    private var serviceLabel: String {
        guard let id = paths.profileID, !paths.usesLegacyState else { return Self.serviceLabel }
        return Self.serviceLabel + "." + id
    }
    private var serviceArguments: [String] { [executable.path, "--service"] + (paths.profileID.map { [$0] } ?? []) }
    private var domain: String { "gui/\(getuid())" }
    private func plist(_ label: String) -> URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    private func guardProduction() throws {
        guard !paths.isDevelopment else { throw MonitorError("Login item changes are disabled when VSM_HOME is set. Test the service directly in this isolated environment.") }
    }
    private func register(_ label: String, args: [String], keepAlive: Bool) throws {
        try guardProduction()
        var content: [String: Any] = ["Label": label, "ProgramArguments": args, "RunAtLoad": true,
            "StandardOutPath": paths.logs.appendingPathComponent(label + ".log").path,
            "StandardErrorPath": paths.logs.appendingPathComponent(label + "-error.log").path,
            "ExitTimeOut": 130, "ThrottleInterval": 30]
        if keepAlive { content["KeepAlive"] = ["SuccessfulExit": false] }
        try atomicWrite(PropertyListSerialization.data(fromPropertyList: content, format: .xml, options: 0), to: plist(label))
        try checkCommand("/bin/launchctl", ["enable", "\(domain)/\(label)"])
        let loaded = try command("/bin/launchctl", ["print", "\(domain)/\(label)"]).code == 0
        if !loaded { try checkCommand("/bin/launchctl", ["bootstrap", domain, plist(label).path]) }
    }
    public func start() throws {
        try guardProduction()
        let lifecycle = Lifecycle(paths: paths)
        guard !lifecycle.isActive else { return }
        let profile = try Store(paths: paths).selected(); try Fleet(paths: paths).checkProfilePorts(profile)
        guard FileManager.default.isExecutableFile(atPath: paths.executable.path) else { throw MonitorError("Install the native server first.") }
        try lifecycle.requestStart()
        try register(serviceLabel, args: serviceArguments, keepAlive: true)
        // kickstart without -k never kills an already running service.
        try checkCommand("/bin/launchctl", ["kickstart", "\(domain)/\(serviceLabel)"])
    }
    public func serverAtLogin(_ enabled: Bool) throws {
        try guardProduction()
        try Store(paths: paths).update { db in
            let id = paths.profileID ?? db.selected
            db.profileAutostart?[id] = enabled
            if id == db.legacyProfile { db.autostart = enabled }
        }
        // Registration while stopped must not unexpectedly start a server immediately.
        if enabled {
            let lifecycle = Lifecycle(paths: paths)
            if !lifecycle.isActive { try lifecycle.requestStop(wait: false) }
            try register(serviceLabel, args: serviceArguments, keepAlive: true)
        }
    }
    public func removeServerJob() throws {
        try guardProduction()
        guard !Lifecycle(paths: paths).isActive else { throw MonitorError("Stop this server before deleting it.") }
        try checkCommand("/bin/launchctl", ["disable", "\(domain)/\(serviceLabel)"])
        _ = try command("/bin/launchctl", ["bootout", "\(domain)/\(serviceLabel)"])
        if try command("/bin/launchctl", ["print", "\(domain)/\(serviceLabel)"]).code == 0 { throw MonitorError("Could not remove this server's background job. Try again.") }
        let file = plist(serviceLabel)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
    public func monitorAtLogin(_ enabled: Bool) throws {
        try guardProduction()
        if enabled { try register(Self.monitorLabel, args: ["/usr/bin/open", "-W", "-a", executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path], keepAlive: false) }
        else {
            // Do not bootout: open -W can terminate the current UI. Disable the next login only.
            try checkCommand("/bin/launchctl", ["disable", "\(domain)/\(Self.monitorLabel)"])
            if FileManager.default.fileExists(atPath: plist(Self.monitorLabel).path) { try FileManager.default.removeItem(at: plist(Self.monitorLabel)) }
        }
        try Store(paths: paths).update { $0.monitorAtLogin = enabled }
    }
}
