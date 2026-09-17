import AppKit
import ServerCore

struct ServerStatusPlaceholder: Decodable {
    var state = "Checking…", players = "", code = "", profileName = "No profile", selected = "", detail = ""
    var running = false, autostart = false, monitorAtLogin = false, installed = false
    var profiles: [Summary] = []
    var servers: [ServerStatusPlaceholder] = []
    struct Summary: Decodable { var id: String; var label: String }
}
class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var editor: ProfileEditor?
    var timer: Timer?
    var busy = false
    var refreshing = false
    var startFeedback = StartFeedback()
    var pendingStarts: [String: StartFeedback] = [:]
    var busyProfiles: Set<String> = []
    var statusGeneration = 0
    var installedBuild: String?
    var latestBuild: String?
    var checkingVersion = false
    var versionCheckFailed = false
    var lastVersionCheck: Date?
    var serverUpdate: ServerUpdateWindow?
    var setup: SetupWindow?
    let engine = Engine()
    var displayed = ServerStatusPlaceholder()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLocation.prepare { ready in
            guard ready else { NSApp.terminate(nil); return }
            self.finishLaunching()
        }
    }
    private func finishLaunching() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rebuild()
        refresh()
        if CommandLine.arguments.contains("--new-profile") { newProfile() }
        else if (try? Store(paths: engine.paths).load().profiles.isEmpty) != false || !FileManager.default.isExecutableFile(atPath: engine.paths.executable.path) { showSetup() }
        let statusTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(statusTimer, forMode: .common)
        timer = statusTimer
        if let index = CommandLine.arguments.firstIndex(of: "--resume-after-update") {
            perform("resume-after-update", args: Array(CommandLine.arguments.dropFirst(index + 1)))
        }
    }
    func command(_ action: String, args: [String] = [], input: Data? = nil) -> (Int32, String) {
        do { return (0, try engine.execute(action, arguments: args, input: input)) }
        catch { return (1, error.localizedDescription) }
    }
    func refresh() {
        checkServerVersion()
        guard !refreshing else { return }
        refreshing = true
        let generation = statusGeneration
        DispatchQueue.global(qos: .utility).async {
            let result = self.command("status")
            let parsed = result.0 == 0 ? try? JSONDecoder().decode(ServerStatusPlaceholder.self, from: Data(result.1.utf8)) : nil
            DispatchQueue.main.async {
                self.refreshing = false
                guard generation == self.statusGeneration else { self.refresh(); return }
                self.displayed = parsed ?? ServerStatusPlaceholder()
                for server in self.displayed.servers {
                    if self.pendingStarts[server.selected]?.observe(running: server.running) == true {
                        let alert = NSAlert(); alert.messageText = "Startup not confirmed: " + server.profileName
                        alert.informativeText = "Check this server's log for details. Other servers continue running."
                        alert.runModal()
                    }
                }
                if self.startFeedback.observe(running: parsed?.running == true) {
                    self.displayed.state = "Start not confirmed"
                    let alert = NSAlert(); alert.messageText = "Server startup has not been confirmed"
                    alert.informativeText = "The start request was sent, but the background service has not reported running. Open the server log for details. The manager will keep checking its status."
                    alert.addButton(withTitle: "Open Server Log"); alert.addButton(withTitle: "OK")
                    self.rebuild()
                    if alert.runModal() == .alertFirstButtonReturn { self.openLog() }
                }
                self.rebuild()
            }
        }
    }
    func add(_ menu: NSMenu, _ title: String, _ action: Selector? = nil, enabled: Bool = true) {
        let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
        row.target = self; row.isEnabled = enabled && action != nil
        menu.addItem(row)
    }
    func rebuild() {
        let serverUpdateAvailable = installedBuild.flatMap { installed in
            latestBuild.map { ServerVersion.updateAvailable(installed: installed, latest: $0) }
        } ?? false
        let stopping = displayed.state == "Stopping" || displayed.servers.contains { $0.state == "Stopping" }
        let starting = startFeedback.pending || pendingStarts.values.contains { $0.pending } || displayed.state == "Starting"
        let active = displayed.running || starting
        let state = stopping ? "Stopping…" : (starting ? "Starting…" : displayed.state)
        let online = displayed.state == "Online" && !starting && !stopping
        let color: NSColor = online ? .systemGreen : (active ? .systemOrange : .systemRed)
        let branding = NSImage(named: NSImage.applicationIconName)
        let light = NSImage(size: NSSize(width: serverUpdateAvailable ? 54 : 34, height: 18), flipped: false) { rect in
            branding?.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 22, y: 4, width: 10, height: 10)).fill()
            if serverUpdateAvailable {
                NSColor.systemYellow.setFill()
                NSBezierPath(ovalIn: NSRect(x: 38, y: 1, width: 16, height: 16)).fill()
                let mark = NSAttributedString(string: "!", attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.black])
                mark.draw(at: NSPoint(x: 43.5, y: 1))
            }
            return true
        }
        light.isTemplate = false
        item.button?.image = light
        item.button?.imagePosition = .imageLeading
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        item.button?.title = " Valheim · " + (stopping ? "Stopping…" : (starting ? "Starting…" : (displayed.players.isEmpty ? "—" : displayed.players)))
        item.button?.toolTip = "Valheim Server Manager for Mac — \(displayed.profileName) — \(state), \(displayed.players.isEmpty ? "unknown" : displayed.players) players. Refreshes every second; shows the latest player count reported in server logs."
        if serverUpdateAvailable { item.button?.toolTip?.append(" A Valheim server update is available. Open the menu to update.") }
        let menu = NSMenu(); menu.autoenablesItems = false
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        add(menu, "Valheim Server Manager for Mac · \(appVersion)")
        menu.addItem(.separator())
        if serverUpdateAvailable {
            add(menu, "Server Update Available — Update Now…", #selector(serverVersionClicked), enabled: !busy && busyProfiles.isEmpty && !checkingVersion && !starting && !stopping)
            menu.items.last?.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Server update available")
            menu.items.last?.toolTip = "A newer server build is available. Click to review the update before any servers are stopped."
            menu.addItem(.separator())
        }
        for server in displayed.servers {
            let pending = pendingStarts[server.selected]?.pending == true
            let serverStarting = pending || server.state == "Starting"
            let serverActive = server.running || pending
            let serverBusy = busy || busyProfiles.contains(server.selected)
            let playerSummary = serverStarting || server.players.isEmpty ? "Players: —" : "\(server.players) \(server.players == "1" ? "player" : "players")"
            let serverMenu = NSMenu(); serverMenu.autoenablesItems = false
            func action(_ title: String, _ selector: Selector, enabled: Bool = true) {
                add(serverMenu, title, selector, enabled: enabled)
                serverMenu.items.last?.representedObject = server.selected
            }
            if !serverStarting && !server.code.isEmpty { action("Join code: \(server.code) · Copy", #selector(copyServerCode(_:))) }
            else { add(serverMenu, "Join code: unavailable") }
            serverMenu.addItem(.separator())
            action(serverStarting ? "Starting Server…" : "Start Server", #selector(startProfile(_:)), enabled: !serverBusy && !serverActive && server.installed)
            action("Stop Server (Save & Stop)", #selector(stopProfile(_:)), enabled: !serverBusy && server.running)
            action(serverActive ? "View Settings…" : "Edit Server…", #selector(profileSettings(_:)), enabled: !serverBusy)
            action("Automatically Start at Login", #selector(profileAutostart(_:)), enabled: !serverBusy)
            serverMenu.items.last?.state = server.autostart ? .on : .off
            serverMenu.addItem(.separator())
            action("Open Server Log", #selector(profileLog(_:)))
            action("Open Logs Folder", #selector(profileFolder(_:)))
            if !server.detail.isEmpty { action("Show Last Server Error…", #selector(profileError(_:))) }
            serverMenu.addItem(.separator())
            action("Delete Server…", #selector(deleteProfile(_:)), enabled: !serverBusy && !serverActive)
            let row = NSMenuItem(title: "\(server.profileName) — \(pending ? "Starting…" : server.state) · \(playerSummary)", action: nil, keyEquivalent: "")
            row.submenu = serverMenu; row.isEnabled = true
            row.toolTip = "Player count is the last count reported in this server's log."
            menu.addItem(row)
        }
        menu.addItem(.separator())
        if let installedBuild {
            let suffix: String
            if checkingVersion { suffix = "Checking for updates…" }
            else if versionCheckFailed { suffix = "Check unavailable · Retry" }
            else if let latestBuild, ServerVersion.updateAvailable(installed: installedBuild, latest: latestBuild) { suffix = "Update available → \(latestBuild)…" }
            else if latestBuild != nil { suffix = "Up to date" }
            else { suffix = "Check for updates" }
            add(menu, "Valheim Server Build \(installedBuild) — \(suffix)", #selector(serverVersionClicked), enabled: !busy && busyProfiles.isEmpty && !checkingVersion && !starting)
        } else { add(menu, "Valheim Server Build: not installed or unavailable") }
        menu.items.last?.toolTip = "The installed Valheim server software is shared by all servers listed above."
        menu.addItem(.separator())
        if !displayed.installed || (!versionCheckFailed && serverUpdateAvailable) {
            add(menu, "Set Up / Update Native Server…", #selector(showSetup), enabled: !busy && !active)
        }
        add(menu, "New Server…", #selector(newProfile), enabled: !busy)
        menu.addItem(.separator())
        add(menu, "Open Manager at Login", #selector(toggleMonitorLogin), enabled: !busy)
        menu.items.last?.state = displayed.monitorAtLogin ? .on : .off
        menu.addItem(.separator())
        add(menu, "Refresh Status", #selector(refreshNow))
        menu.addItem(.separator())
        add(menu, "Quit Manager (Servers Keep Running)", #selector(quit))
        item.menu = menu
    }
    func perform(_ action: String, args: [String] = []) {
        guard !busy else { return }
        if action == "start" || action == "resume-after-update" {
            guard !startFeedback.pending else { return }
            startFeedback.begin()
            statusGeneration += 1
        }
        busy = true; rebuild()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.command(action, args: args)
            DispatchQueue.main.async {
                self.busy = false
                if action == "start" || action == "resume-after-update" {
                    self.startFeedback.commandFinished(success: result.0 == 0)
                    self.statusGeneration += 1
                }
                self.rebuild()
                if result.0 != 0 {
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert(); alert.messageText = "Valheim Server Manager for Mac needs attention"
                    alert.informativeText = result.1; alert.runModal()
                }
                self.refresh()
            }
        }
    }
    func profileAction(_ action: String, id: String) {
        guard !busy, !busyProfiles.contains(id) else { return }
        busyProfiles.insert(id)
        if action == "start" { var feedback = StartFeedback(); feedback.begin(); pendingStarts[id] = feedback }
        statusGeneration += 1; rebuild()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.command(action, args: [id])
            DispatchQueue.main.async {
                self.busyProfiles.remove(id)
                if action == "start" { self.pendingStarts[id]?.commandFinished(success: result.0 == 0) }
                self.statusGeneration += 1; self.rebuild(); self.refresh()
                if result.0 != 0 { let alert = NSAlert(); alert.messageText = "Server needs attention"; alert.informativeText = result.1; alert.runModal() }
            }
        }
    }
    func server(_ sender: NSMenuItem) -> ServerStatusPlaceholder? { displayed.servers.first { $0.selected == sender.representedObject as? String } }
    @objc func deleteProfile(_ sender: NSMenuItem) {
        guard let server = server(sender), !server.running else { return }
        let alert = NSAlert(); alert.messageText = "Delete \(server.profileName)?"
        alert.informativeText = "This removes the server from the manager and disables its login startup. Its world save and settings will be kept in the app's deleted-servers recovery folder. Other servers are unaffected."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Delete Server")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        profileAction("delete-server", id: server.selected)
    }
    @objc func startProfile(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { profileAction("start", id: id) } }
    @objc func stopProfile(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { profileAction("stop", id: id) } }
    @objc func profileAutostart(_ sender: NSMenuItem) { if let server = server(sender) { profileAction(server.autostart ? "autostart-off" : "autostart-on", id: server.selected) } }
    @objc func profileSettings(_ sender: NSMenuItem) {
        if let server = server(sender) { showEditor("get-profile", profileID: server.selected, readOnly: server.running || pendingStarts[server.selected]?.pending == true) }
    }
    @objc func copyServerCode(_ sender: NSMenuItem) {
        if let server = server(sender) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(server.code, forType: .string) }
    }
    func pathsForServer(_ sender: NSMenuItem) -> Paths? {
        guard let id = sender.representedObject as? String else { return nil }
        return try? Store(paths: engine.paths).servicePaths(id)
    }
    @objc func profileLog(_ sender: NSMenuItem) {
        guard let paths = pathsForServer(sender) else { return }
        if let log = try? String(contentsOf: paths.file("latest-log"), encoding: .utf8), FileManager.default.fileExists(atPath: log) { NSWorkspace.shared.open(URL(fileURLWithPath: log)) }
        else { try? paths.prepare(); NSWorkspace.shared.open(paths.logs) }
    }
    @objc func profileFolder(_ sender: NSMenuItem) { if let paths = pathsForServer(sender) { try? paths.prepare(); NSWorkspace.shared.open(paths.logs) } }
    @objc func profileError(_ sender: NSMenuItem) { if let server = server(sender) { let alert = NSAlert(); alert.messageText = server.profileName; alert.informativeText = server.detail; alert.runModal() } }
    @objc func selectProfile(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { perform("select-profile", args: [id]) } }
    func checkServerVersion(force: Bool = false) {
        guard !checkingVersion, !busy, force || lastVersionCheck == nil || Date().timeIntervalSince(lastVersionCheck!) >= 900 else { return }
        installedBuild = ServerVersion.installed(paths: engine.paths)
        lastVersionCheck = Date()
        guard installedBuild != nil else { return }
        checkingVersion = true
        DispatchQueue.global(qos: .utility).async {
            let build = try? ServerVersion.check(paths: self.engine.paths)
            DispatchQueue.main.async {
                self.checkingVersion = false; self.latestBuild = build ?? self.latestBuild; self.versionCheckFailed = build == nil
                self.installedBuild = ServerVersion.installed(paths: self.engine.paths)
                self.rebuild()
            }
        }
    }
    @objc func serverVersionClicked() {
        guard !busy, busyProfiles.isEmpty, !checkingVersion, !pendingStarts.values.contains(where: { $0.pending }) else { return }
        guard let installedBuild, let latestBuild, !versionCheckFailed,
              ServerVersion.updateAvailable(installed: installedBuild, latest: latestBuild) else {
            checkServerVersion(force: true); rebuild(); return
        }
        let alert = NSAlert(); alert.messageText = "Update the Valheim server?"
        alert.informativeText = "Install Valve’s latest stable server build (currently \(latestBuild)). All running servers will save and stop, disconnecting players, then restart after a successful update. Your profiles and worlds are preserved."
        alert.addButton(withTitle: "Update Server"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        busy = true; rebuild()
        serverUpdate = ServerUpdateWindow(engine: engine) { [weak self] in
            guard let self else { return }
            self.busy = false; self.serverUpdate = nil
            self.statusGeneration += 1
            self.checkServerVersion(force: true); self.refresh()
        }
    }
    func showEditor(_ action: String, profileID: String? = nil, readOnly: Bool = false) {
        let result = command(action, args: profileID.map { [$0] } ?? [])
        guard result.0 == 0, let profile = try? JSONSerialization.jsonObject(with: Data(result.1.utf8)) as? [String:Any] else { return }
        editor?.window.close()
        editor = ProfileEditor(profile: profile, readOnly: readOnly) { values in
            guard let data = try? JSONSerialization.data(withJSONObject: values) else { return }
            guard !self.busy else { return }
            self.busy = true; self.editor?.setSaving(true)
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.command("save-profile", input: data)
                DispatchQueue.main.async {
                    self.busy = false; self.editor?.setSaving(false)
                    if result.0 == 0 { self.editor?.window.close(); self.refresh() }
                    else { let alert = NSAlert(); alert.messageText = "Profile could not be saved"; alert.informativeText = result.1; alert.runModal() }
                }
            }
        }
    }
    @objc func newProfile() { showEditor("default-profile") }
    @objc func editProfile() { showEditor("get-profile") }
    @objc func toggleAutostart() { perform(displayed.autostart ? "autostart-off" : "autostart-on") }
    @objc func startServer() { perform("start") }
    @objc func stopServer() { perform("stop") }
    @objc func refreshNow() { refresh() }
    @objc func copyCode() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(displayed.code, forType: .string) }
    @objc func openLog() {
        if let path = try? String(contentsOf: engine.paths.file("latest-log"), encoding: .utf8), FileManager.default.fileExists(atPath: path) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        else { openFolder() }
    }
    @objc func openFolder() { NSWorkspace.shared.open(engine.paths.logs) }
    @objc func toggleMonitorLogin() { perform(displayed.monitorAtLogin ? "monitor-login-off" : "monitor-login-on") }
    @objc func showError() { let alert = NSAlert(); alert.messageText = "Last server error"; alert.informativeText = displayed.detail; alert.runModal() }
    @objc func showSetup() {
        if let setup { setup.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        setup = SetupWindow(engine: engine, onCreate: { [weak self] in self?.newProfile() }, onChange: { [weak self] in self?.lastVersionCheck = nil; self?.refresh() }, onClose: { [weak self] in self?.setup = nil })
    }
    @objc func quit() { NSApp.terminate(nil) }
}
umask(0o077)
if CommandLine.arguments.contains("--service") {
    let base = Paths()
    var paths = base
    do {
        let store = try Store(paths: base), db = try store.load()
        let index = CommandLine.arguments.firstIndex(of: "--service")!
        let id = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : (db.legacyProfile ?? db.selected)
        guard db.profiles.contains(where: { $0.id == id }) else { throw MonitorError("Profile not found.") }
        paths = store.servicePaths(id, database: db)
        try Lifecycle(paths: paths).runService(); exit(0)
    }
    catch {
        try? atomicWrite(Data(error.localizedDescription.utf8), to: paths.file("last-error.txt"))
        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1)
    }
}
if let index = CommandLine.arguments.firstIndex(of: "--control"), CommandLine.arguments.count > index + 1 {
    let action = CommandLine.arguments[index + 1]
    do {
        let input = action == "save-profile" ? FileHandle.standardInput.readDataToEndOfFile() : nil
        print(try Engine().execute(action, arguments: Array(CommandLine.arguments.dropFirst(index + 2)), input: input)); exit(0)
    } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
