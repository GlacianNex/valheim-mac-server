import Foundation

public final class LoginItems {
    public let paths: Paths
    public let executable: URL
    public static let serviceLabel = "io.github.glaciannex.valheimservermonitor.server"
    public static let monitorLabel = "io.github.glaciannex.valheimservermonitor.menu"
    public init(paths: Paths, executable: URL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL) {
        self.paths = paths; self.executable = executable
    }
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
        let profile = try Store(paths: paths).selected(); try Lifecycle.checkPorts(profile.port)
        guard FileManager.default.isExecutableFile(atPath: paths.executable.path) else { throw MonitorError("Install the native server first.") }
        try lifecycle.requestStart()
        try register(Self.serviceLabel, args: [executable.path, "--service"], keepAlive: true)
        // kickstart without -k never kills an already running service.
        try checkCommand("/bin/launchctl", ["kickstart", "\(domain)/\(Self.serviceLabel)"])
    }
    public func serverAtLogin(_ enabled: Bool) throws {
        try guardProduction()
        try Store(paths: paths).update { $0.autostart = enabled }
        // Registration while stopped must not unexpectedly start a server immediately.
        if enabled {
            let lifecycle = Lifecycle(paths: paths)
            if !lifecycle.isActive { try lifecycle.requestStop(wait: false) }
            try register(Self.serviceLabel, args: [executable.path, "--service"], keepAlive: true)
        }
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
