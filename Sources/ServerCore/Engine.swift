import Foundation

public final class Engine {
    public let paths: Paths
    public init(paths: Paths = Paths()) { self.paths = paths }
    public func execute(_ action: String, arguments: [String] = [], input: Data? = nil) throws -> String {
        let store = try Store(paths: paths)
        let db = try store.load()
        let id = arguments.first ?? db.selected
        let scopedActions: Set<String> = ["start", "stop", "get-profile", "autostart-on", "autostart-off", "delete-server", "management-info", "management-command", "enable-management", "disable-management", "enable-networking", "disable-networking", "world-backups", "world-backup", "world-restore"]
        if scopedActions.contains(action), !db.profiles.contains(where: { $0.id == id }) { throw MonitorError("Profile not found.") }
        let servicePaths = store.servicePaths(id, database: db)
        let lifecycle = Lifecycle(paths: servicePaths)
        switch action {
        case "status":
            var status = try lifecycle.status()
            status.servers = try Fleet(paths: paths).statuses()
            status.running = status.servers.contains { $0.running }
            let running = status.servers.filter { $0.running }
            status.players = running.contains { Int($0.players) == nil } ? "" : String(running.compactMap { Int($0.players) }.reduce(0, +))
            status.state = Fleet.state(for: status.servers)
            return String(decoding: try encode(status), as: UTF8.self)
        case "default-profile":
            var profile = Profile()
            while db.profiles.contains(where: { abs($0.port - profile.port) <= 1 }), profile.port <= 65532 { profile.port += 2 }
            var form = profile.form; form["id"] = ""
            return String(decoding: try JSONSerialization.data(withJSONObject: form), as: UTF8.self)
        case "get-profile":
            let profile = try Store(paths: servicePaths).selected()
            var form = profile.form
            do {
                let saved = try SavedWorldSettings.read(profile: profile, paths: paths)
                form["_savedSeed"] = saved.seed
                form["_savedModifiers"] = saved.modifiers; form["_savedFlags"] = saved.flags
                form["_savedSettingsNote"] = "Inherited values below come from the latest completed world save. They are displayed without adding launch overrides. Changes made in-game may appear after the next save."
            } catch { form["_savedSettingsNote"] = "Saved world values could not be read. Unset fields preserve the world settings; they do not mean Normal or Disabled." }
            return String(decoding: try JSONSerialization.data(withJSONObject: form), as: UTF8.self)
        case "save-profile":
            guard let input, let form = try JSONSerialization.jsonObject(with: input) as? [String: Any] else { throw MonitorError("Invalid profile data.") }
            let source = (form["import"] as? String).flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            return try store.save(Profile(form: form), importSource: source)
        case "select-profile":
            guard let id = arguments.first else { throw MonitorError("Choose a profile.") }; try store.select(id)
        case "start": try LoginItems(paths: servicePaths).start()
        case "resume-after-update":
            try Fleet(paths: paths).start(arguments)
        case "delete-server":
            try LoginItems(paths: servicePaths).removeServerJob()
            return try store.delete(id).path
        case "stop": try lifecycle.requestStop()
        case "autostart-on": try LoginItems(paths: servicePaths).serverAtLogin(true)
        case "autostart-off": try LoginItems(paths: servicePaths).serverAtLogin(false)
        case "monitor-login-on": try LoginItems(paths: paths).monitorAtLogin(true)
        case "monitor-login-off": try LoginItems(paths: paths).monitorAtLogin(false)
        case "automatic-server-updates-on":
            try store.update { $0.automaticServerUpdates = true; $0.lastAutomaticServerUpdateAttempt = nil }
        case "automatic-server-updates-off":
            try store.update { $0.automaticServerUpdates = false }
        case "install": try Installer(paths: paths).install()
        case "world-backups": return String(decoding:try encode(WorldBackups(paths:servicePaths).list()),as:UTF8.self)
        case "world-backup":
            guard arguments.count == 2 else { throw MonitorError("Choose a backup name.") }
            return String(decoding:try encode(WorldBackups(paths:servicePaths).create(name:arguments[1])),as:UTF8.self)
        case "world-restore":
            guard arguments.count == 2 else { throw MonitorError("Choose a backup identifier.") }
            try WorldBackups(paths:servicePaths).restore(id:arguments[1])
        case "management-info":
            return try ManagedServer(paths: servicePaths).connection().send("serverInfo")
        case "management-command":
            guard arguments.count >= 2 else { throw MonitorError("Choose a server and command.") }
            let action = arguments[1]
            guard ["kick", "ban", "unban"].contains(action), arguments.count == 3,
                  !arguments[2].contains("\n"), !arguments[2].isEmpty else { throw MonitorError("Invalid moderation command.") }
            return try ManagedServer(paths: servicePaths).moderate(action:action,target:arguments[2])
        case "enable-networking", "disable-networking":
            guard db.profiles.contains(where: { $0.id == id }), !lifecycle.isActive else { throw MonitorError("Stop the server before changing network optimization.") }
            try store.update { if $0.networkOptimizations == nil { $0.networkOptimizations = [:] }; $0.networkOptimizations?[id] = action == "enable-networking" }
            return "OK"
        case "enable-management", "disable-management":
            guard db.profiles.contains(where: { $0.id == id }), !lifecycle.isActive else { throw MonitorError("Stop the server before changing management support.") }
            try store.update { if $0.managedServers == nil { $0.managedServers = [:] }; $0.managedServers?[id] = action == "enable-management" }
        case "check-server-update": return try ServerVersion.check(paths: paths)
        default: throw MonitorError("Unknown command.")
        }
        return "Done"
    }
}
