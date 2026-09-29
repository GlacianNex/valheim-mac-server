import AppKit
import ServerCore

struct ServerStatusPlaceholder: Decodable {
    var state = "Checking…", players = "", code = "", profileName = "No profile", selected = "", detail = ""
    var running = false, autostart = false, monitorAtLogin = false, installed = false
    var crossplay: Bool?
    var port: Int?
    var managementEnabled: Bool?
    var automaticServerUpdates: Bool?
    var profiles: [Summary] = []
    var servers: [ServerStatusPlaceholder] = []
    struct Summary: Decodable { var id: String; var label: String }
}
class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var editor: ProfileEditor?
    var managementWindow: ServerManagementWindow?
    var scheduleWindow: RestartScheduleWindow?
    var scheduleChecking = false
    var lastScheduleCheck = Date.distantPast
    var timer: Timer?
    var lastManagementMigration = Date.distantPast
    var busy = false
    var refreshing = false
    var pendingAutomaticServerUpdates: Bool?
    var startFeedback = StartFeedback()
    var pendingStarts: [String: StartFeedback] = [:]
    var busyProfiles: Set<String> = []
    var statusGeneration = 0
    var installedBuild: String?
    var latestBuild: String?
    var checkingVersion = false
    var versionCheckFailed = false
    var lastVersionCheck: Date?
    var managerRelease: ManagerRelease?
    var managerCheckDate: Date?
    var checkingManager = false
    var managerCheckFailed = false
    var installingManager = false
    var managerProgress: NSWindow?
    var serverUpdateProgress: ServerUpdateProgress?
    var serverUpdate: ServerUpdateWindow?
    var logViewers: [String:ServerLogsWindow] = [:]
    var setup: SetupWindow?
    let engine = Engine()
    let performanceRecorder = PerformanceRecorder()
    var displayed = ServerStatusPlaceholder()
    var publicJoinIP: String?
    var checkingJoinIP = false
    var lastJoinIPCheck = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLocation.prepare { ready in
            guard ready else { NSApp.terminate(nil); return }
            self.finishLaunching()
        }
    }
    private func finishLaunching() {
        performanceRecorder.start(paths:engine.paths)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rebuild()
        refresh()
        if CommandLine.arguments.contains("--new-profile") { newProfile() }
        else if (try? Store(paths: engine.paths).load().profiles.isEmpty) != false || !FileManager.default.isExecutableFile(atPath: engine.paths.executable.path) { showSetup() }
        let statusTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(statusTimer, forMode: .common)
        timer = statusTimer
        let resume = CommandLine.arguments.firstIndex(of:"--resume-after-update").map { Array(CommandLine.arguments.dropFirst($0+1)) }
        prepareManagementDefaults(force:true) { [weak self] in
            if let resume { self?.perform("resume-after-update",args:resume) }
        }
    }
    func prepareManagementDefaults(force: Bool = false, completion: (() -> Void)? = nil) {
        guard !busy, busyProfiles.isEmpty, serverUpdate == nil,
              force || Date().timeIntervalSince(lastManagementMigration) >= 30 else { completion?(); return }
        lastManagementMigration = Date()
        guard let store = try? Store(paths:engine.paths), let db = try? store.load(),
              FileManager.default.isExecutableFile(atPath:engine.paths.executable.path) else { completion?(); return }
        let candidates = db.profiles.filter { db.managedServers?[$0.id] == nil }
        guard !candidates.isEmpty else { completion?(); return }
        busy = true; rebuild()
        DispatchQueue.global(qos:.utility).async {
            for profile in candidates {
                let paths = store.servicePaths(profile.id,database:db)
                do {
                    if try ManagementDefaults.installWhileStopped(paths:paths) {
                        if (try? String(contentsOf:paths.file("last-error.txt"),encoding:.utf8))?.hasPrefix("Management tools installation failed:") == true {
                            try? FileManager.default.removeItem(at:paths.file("last-error.txt"))
                        }
                    }
                } catch {
                    try? atomicWrite(Data(("Management tools installation failed: " + error.localizedDescription).utf8),to:paths.file("last-error.txt"))
                }
            }
            DispatchQueue.main.async {
                self.busy = false; self.statusGeneration += 1
                completion?(); self.refresh()
            }
        }
    }
    func command(_ action: String, args: [String] = [], input: Data? = nil) -> (Int32, String) {
        do { return (0, try engine.execute(action, arguments: args, input: input)) }
        catch { return (1, error.localizedDescription) }
    }
    func refresh() {
        checkServerVersion()
        checkManagerVersion()
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
                self.checkJoinAddress()
                if self.serverUpdate == nil, parsed != nil { self.serverUpdateProgress = nil }
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
                self.prepareManagementDefaults()
                self.maybeAutomaticallyUpdateServer()
                self.checkSchedules()
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
        let updateTitle = serverUpdateProgress?.title ?? (displayed.state == "Updating" ? "Updating…" : nil)
        let state = updateTitle ?? (stopping ? "Stopping…" : (starting ? "Starting…" : displayed.state))
        let online = serverUpdateProgress == nil && displayed.state == "Online" && !starting && !stopping
        let color: NSColor = online ? .systemGreen : (active || updateTitle != nil ? .systemOrange : .systemRed)
        let updateBadge = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            NSColor.systemYellow.setFill()
            NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
            NSAttributedString(string: "!", attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.black])
                .draw(at: NSPoint(x: 5.5, y: 0))
            return true
        }
        updateBadge.isTemplate = false
        let branding = NSImage(named: NSImage.applicationIconName)
        let light = NSImage(size: NSSize(width: 34, height: 18), flipped: false) { rect in
            branding?.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 22, y: 4, width: 10, height: 10)).fill()
            return true
        }
        light.isTemplate = false
        item.button?.image = light
        item.button?.imagePosition = .imageLeading
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        item.button?.title = " Valheim · " + (updateTitle ?? (stopping ? "Stopping…" : (starting ? "Starting…" : (displayed.players.isEmpty ? "—" : displayed.players))))
        if serverUpdateAvailable, let button = item.button {
            let title = NSMutableAttributedString(string: button.title + " ", attributes: [.font: button.font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
            let badge = NSTextAttachment()
            badge.image = updateBadge
            badge.bounds = NSRect(x: 0, y: -3, width: 16, height: 16)
            title.append(NSAttributedString(attachment: badge))
            button.attributedTitle = title
        }
        item.button?.toolTip = "Valheim Server Manager for Mac — \(displayed.profileName) — \(state), \(displayed.players.isEmpty ? "unknown" : displayed.players) players. Refreshes every second; shows the latest player count reported in server logs."
        if let update = serverUpdateProgress { item.button?.toolTip = update.message }
        if serverUpdateAvailable { item.button?.toolTip?.append(" A Valheim server update is available. Open the menu to update.") }
        let menu = NSMenu(); menu.autoenablesItems = false
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let experimental = AppInstallation.isExperimental()
        let managerAvailable = !experimental && managerRelease?.isNewer(than: appVersion) == true
        let managerState = installingManager ? "Updating…" : managerAvailable ? "Update Available" : checkingManager ? "Checking…" : managerCheckFailed ? "Check unavailable" : managerCheckDate == nil ? "Checking…" : "Up to date"
        add(menu, experimental ? "Valheim Manager · Experimental" : "Valheim Manager · \(appVersion) · \(managerState)",
            managerAvailable ? #selector(managerVersionClicked) : nil,
            enabled: !busy && busyProfiles.isEmpty && !checkingManager && !installingManager && !starting && !stopping)
        if managerAvailable { menu.items.last?.image = updateBadge }
        menu.items.last?.toolTip = experimental ? "Experimental build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"). Public manager updates are disabled. Install a new experimental download to replace this build." : managerAvailable
            ? "Update manager to \(managerRelease!.version). Clicking downloads, verifies, and installs it automatically. Running servers save and stop, then restart after the update. Worlds and settings are preserved."
            : "Valheim Server Manager for Mac. Checks for manager updates on launch and every six hours."
        menu.addItem(.separator())
        if serverUpdateAvailable {
            add(menu, serverUpdateProgress?.title ?? "Update Valheim Server…", #selector(serverVersionClicked), enabled: !busy && busyProfiles.isEmpty && !checkingVersion && !starting && !stopping)
            menu.items.last?.image = updateBadge
            menu.items.last?.toolTip = serverUpdateProgress?.message ?? "A newer server build is available. Click to review the update before any servers are stopped."
            menu.addItem(.separator())
        }
        if serverUpdate != nil {
            add(menu, "Show Restart / Update Progress…", #selector(showMaintenanceProgress))
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
            if server.crossplay == false, let port = server.port {
                if let address = JoinAddress.endpoint(ip: publicJoinIP, port: port) {
                    action("Join address: \(address) · Copy", #selector(copyServerAddress(_:)))
                } else {
                    action(checkingJoinIP ? "Join address: checking…" : "Join address unavailable · Retry", #selector(retryJoinAddress), enabled: !checkingJoinIP)
                }
                serverMenu.items.last?.toolTip = "For friends outside your network. Steam players only. Forward UDP ports \(port)–\(port + 1) to this Mac. This is your public IPv4 address; VPNs or shared ISP addresses can prevent connections. Port forwarding has not been verified."
            } else if !serverStarting && !server.code.isEmpty { action("Join code: \(server.code) · Copy", #selector(copyServerCode(_:))) }
            else { add(serverMenu, "Join code: unavailable") }
            serverMenu.addItem(.separator())
            action(serverStarting ? "Starting Server…" : "Start Server", #selector(startProfile(_:)), enabled: !serverBusy && !serverActive && server.installed)
            action("Stop Server (Save & Stop)", #selector(stopProfile(_:)), enabled: !serverBusy && server.running)
            action("Start Server at Login", #selector(profileAutostart(_:)), enabled: !serverBusy)
            serverMenu.items.last?.state = server.autostart ? .on : .off
            serverMenu.items.last?.toolTip = "Start this server when you log in to this Mac. Also configurable in Server Management → Automation."
            action("Server Management…", #selector(openManagement(_:)))
            let row = NSMenuItem(title: "\(server.profileName) — \(pending ? "Starting…" : server.state) · \(playerSummary)", action: nil, keyEquivalent: "")
            row.submenu = serverMenu; row.isEnabled = true
            row.toolTip = "Player count is the last count reported in this server's log."
            menu.addItem(row)
        }
        menu.addItem(.separator())
        if let installedBuild, serverUpdateAvailable {
            add(menu, "Valheim Server Build \(installedBuild)")
        } else if let installedBuild {
            let suffix: String
            if checkingVersion { suffix = "Checking for updates…" }
            else if versionCheckFailed { suffix = "Update check unavailable" }
            else if latestBuild != nil { suffix = "Up to date" }
            else { suffix = "Update check pending" }
            add(menu, "Valheim Server Build \(installedBuild) — \(suffix)")
        } else { add(menu, "Valheim Server Build: not installed or unavailable") }
        menu.items.last?.toolTip = "The installed Valheim server software is shared by all servers listed above."
        add(menu, "Automatically Update All Valheim Servers", #selector(toggleAutomaticServerUpdates(_:)), enabled: !busy)
        menu.items.last?.state = (pendingAutomaticServerUpdates ?? displayed.automaticServerUpdates ?? false) ? .on : .off
        menu.items.last?.toolTip = ManagementHelp.automaticUpdates
        menu.addItem(.separator())
        if !displayed.installed {
            add(menu, "Set Up Native Server…", #selector(showSetup), enabled: !busy && !active)
        }
        add(menu, "New Server…", #selector(newProfile), enabled: !busy)
        menu.addItem(.separator())
        add(menu, "Open Manager at Login", #selector(toggleMonitorLogin), enabled: !busy)
        menu.items.last?.state = displayed.monitorAtLogin ? .on : .off
        menu.addItem(.separator())
        add(menu, "Quit Manager (Servers Keep Running)", #selector(quit), enabled: !busy)
        item.menu = menu
    }
    func perform(_ action: String, args: [String] = [], completion: ((Bool) -> Void)? = nil) {
        guard !busy else { return }
        if action == "start" || action == "resume-after-update" {
            guard !startFeedback.pending else { return }
            startFeedback.begin()
            statusGeneration += 1
        }
        if action == "stop" { self.startFeedback.cancel(); self.pendingStarts.removeAll(); statusGeneration += 1 }
        busy = true; rebuild()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.command(action, args: args)
            DispatchQueue.main.async {
                self.busy = false
                completion?(result.0 == 0)
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
    func cancelStartupFeedback(for id: String) {
        startFeedback.cancel()
        pendingStarts.removeValue(forKey: id)
    }
    func profileAction(_ action: String, id: String) {
        guard !busy, !busyProfiles.contains(id) else { return }
        busyProfiles.insert(id)
        if action == "stop" { cancelStartupFeedback(for: id) }
        if action == "start" { var feedback = StartFeedback(); feedback.begin(); pendingStarts[id] = feedback }
        statusGeneration += 1; rebuild()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.command(action, args: [id])
            DispatchQueue.main.async {
                self.busyProfiles.remove(id)
                if action == "delete-server", result.0 == 0, self.managementWindow?.window.identifier?.rawValue == id { self.managementWindow?.window.close() }
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
    func checkJoinAddress(force: Bool = false) {
        guard displayed.servers.contains(where: { $0.crossplay == false }), !checkingJoinIP,
              force || Date().timeIntervalSince(lastJoinIPCheck) >= 300 else { return }
        checkingJoinIP = true; lastJoinIPCheck = Date()
        var request = URLRequest(url: URL(string: "https://api.ipify.org")!)
        request.timeoutInterval = 10; request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let ip = (response as? HTTPURLResponse)?.statusCode == 200
                ? data.flatMap { String(data: $0, encoding: .utf8) }.flatMap(JoinAddress.ipv4) : nil
            DispatchQueue.main.async {
                self.publicJoinIP = ip; self.checkingJoinIP = false; self.rebuild()
            }
        }.resume()
    }
    @objc func retryJoinAddress() { checkJoinAddress(force: true); rebuild() }
    @objc func copyServerAddress(_ sender: NSMenuItem) {
        guard let server = server(sender), let port = server.port,
              let address = JoinAddress.endpoint(ip: publicJoinIP, port: port) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(address, forType: .string)
    }
    @objc func copyServerCode(_ sender: NSMenuItem) {
        if let server = server(sender) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(server.code, forType: .string) }
    }
    func pathsForServer(_ sender: NSMenuItem) -> Paths? {
        guard let id = sender.representedObject as? String else { return nil }
        return try? Store(paths: engine.paths).servicePaths(id)
    }
    @objc func openManagement(_ sender: NSMenuItem) {
        guard let paths = pathsForServer(sender), let server = server(sender) else { return }
        managementWindow?.window.close()
        managementWindow = ServerManagementWindow(paths:paths, name:server.profileName, recorder:performanceRecorder,
            isBusy: { [weak self] in self?.busy == true || self?.busyProfiles.contains(server.selected) == true || self?.pendingStarts[server.selected]?.pending == true },
            changed: { [weak self] in self?.statusGeneration += 1; self?.lastScheduleCheck = .distantPast; self?.refresh() },
            settings: { [weak self] in
                guard let self, !self.busy, !self.busyProfiles.contains(server.selected) else { return }
                self.showEditor("get-profile", profileID:server.selected, readOnly:Lifecycle(paths:paths).isActive || self.pendingStarts[server.selected]?.pending == true)
            },
            delete: { [weak self] in
                guard let self, !self.busy, !self.busyProfiles.contains(server.selected), !Lifecycle(paths:paths).isActive, self.pendingStarts[server.selected]?.pending != true else { return }
                self.deleteProfile(sender)
            }, serverAction: { [weak self] action in self?.profileAction(action,id:server.selected) })
    }
    @objc func disableManagement(_ sender: NSMenuItem) {
        guard let server = server(sender) else { return }
        profileAction("disable-management", id:server.selected)
    }
    @objc func enableManagement(_ sender: NSMenuItem) {
        guard let server = server(sender), !server.running else { return }
        profileAction("enable-management", id: server.selected)
    }
    func showLogs(paths:Paths,name:String) {
        let key = paths.stateRoot.path
        if logViewers[key] == nil { logViewers[key] = ServerLogsWindow(paths:paths,name:name) }
        logViewers[key]?.show()
    }
    @objc func profileLog(_ sender: NSMenuItem) {
        guard let paths = pathsForServer(sender) else { return }
        showLogs(paths:paths,name:server(sender)?.profileName ?? "Valheim")
    }
    @objc func profileFolder(_ sender: NSMenuItem) { if let paths = pathsForServer(sender) { try? paths.prepare(); NSWorkspace.shared.open(paths.logs) } }
    @objc func profileError(_ sender: NSMenuItem) { if let server = server(sender) { let alert = NSAlert(); alert.messageText = server.profileName; alert.informativeText = server.detail; alert.runModal() } }
    @objc func selectProfile(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { perform("select-profile", args: [id]) } }
    func checkManagerVersion(force: Bool = false) {
        guard !AppInstallation.isExperimental(), !checkingManager, !installingManager,
              force || managerCheckDate == nil || Date().timeIntervalSince(managerCheckDate!) >= 6 * 3600 else { return }
        checkingManager = true
        managerCheckDate = Date()
        Task { @MainActor in
            do { managerRelease = try await ManagerUpdater.latest(); managerCheckFailed = false }
            catch { managerCheckFailed = true }
            checkingManager = false
            rebuild()
        }
    }
    @objc func managerVersionClicked() {
        guard !AppInstallation.isExperimental(), !busy, serverUpdate == nil, busyProfiles.isEmpty, !installingManager,
              !pendingStarts.values.contains(where: { $0.pending }),
              !displayed.servers.contains(where: { $0.state == "Starting" || $0.state == "Stopping" }) else { return }
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard let release = managerRelease, release.isNewer(than: current) else {
            checkManagerVersion(force: true); rebuild(); return
        }
        guard !engine.paths.isDevelopment else {
            let alert = NSAlert(); alert.messageText = "Use the installed app to update"
            alert.informativeText = "Automatic installation is disabled in development mode."; alert.runModal(); return
        }
        installingManager = true; busy = true; rebuild()
        let progress = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        progress.title = "Updating Valheim Manager"; progress.isReleasedWhenClosed = false
        let label = NSTextField(wrappingLabelWithString: "Downloading and verifying version \(release.version)… Your servers keep running during the download.")
        label.frame = NSRect(x: 20, y: 20, width: 380, height: 60)
        progress.contentView?.addSubview(label)
        managerProgress = progress; progress.center(); progress.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            do {
                let app = try await ManagerUpdater.download(release)
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true
                configuration.allowsRunningApplicationSubstitution = false
                configuration.arguments = ["--install-approved-update"]
                NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
                    DispatchQueue.main.async { self.finishManagerDownload(error) }
                }
            } catch { finishManagerDownload(error) }
        }
    }
    private func finishManagerDownload(_ error: Error?) {
        managerProgress?.close(); managerProgress = nil
        installingManager = false; busy = false; rebuild()
        if let error {
            let alert = NSAlert(); alert.messageText = "Manager update could not finish"
            alert.informativeText = error.localizedDescription; alert.runModal()
        }
    }
    func checkServerVersion(force: Bool = false) {
        guard !checkingVersion, !busy, force || lastVersionCheck == nil || Date().timeIntervalSince(lastVersionCheck!) >= ServerUpdatePolicy.checkInterval else { return }
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
                self.maybeAutomaticallyUpdateServer()
            }
        }
    }
    @objc func toggleAutomaticServerUpdates(_ sender: NSMenuItem) {
        guard !busy else { return }
        let previous = displayed.automaticServerUpdates ?? false
        let enabled = !previous
        pendingAutomaticServerUpdates = enabled; sender.state = enabled ? .on : .off; statusGeneration += 1
        perform(enabled ? "automatic-server-updates-on" : "automatic-server-updates-off") { success in
            self.statusGeneration += 1
            self.pendingAutomaticServerUpdates = nil
            self.displayed.automaticServerUpdates = success ? enabled : previous
            sender.state = self.displayed.automaticServerUpdates == true ? .on : .off
        }
    }
    func maybeAutomaticallyUpdateServer() {
        guard !busy, busyProfiles.isEmpty,
              !startFeedback.pending, !pendingStarts.values.contains(where: { $0.pending }),
              displayed.state != "Starting", displayed.state != "Stopping", serverUpdateProgress == nil,
              let installedBuild,
              let store = try? Store(paths: engine.paths), let db = try? store.load() else { return }
        let updateRuntime = db.automaticServerUpdates == true && !versionCheckFailed && !checkingVersion && latestBuild.map { ServerVersion.updateAvailable(installed: installedBuild, latest: $0) } == true
        let updateManagement = db.profiles.contains { ManagedServer(paths: store.servicePaths($0.id, database: db)).needsUpdate }
        guard updateRuntime || updateManagement else { return }
        let attempt = (updateRuntime ? latestBuild! : installedBuild) + ":" + (ManagedServer.availableVersion ?? "none")
        guard db.lastAutomaticServerUpdateAttempt != attempt else { return }
        beginServerUpdate(automaticBuild: attempt, managementOnly: !updateRuntime)
    }
    @objc func serverVersionClicked() {
        guard !busy, busyProfiles.isEmpty, !checkingVersion, !pendingStarts.values.contains(where: { $0.pending }) else { return }
        guard let installedBuild, let latestBuild, !versionCheckFailed,
              ServerVersion.updateAvailable(installed: installedBuild, latest: latestBuild) else {
            checkServerVersion(force: true); rebuild(); return
        }
        let alert = NSAlert(); alert.messageText = "Update the Valheim server?"
        alert.informativeText = "Install Valve’s latest stable server build (currently \(latestBuild)). Managed servers will receive a 15-minute countdown with warnings at 15, 10, 5 and 1 minute, then save, stop and restart after a successful update. Servers without working management must be empty. Your profiles and worlds are preserved."
        alert.addButton(withTitle: "Update Server"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        beginServerUpdate()
    }
    @objc func showMaintenanceProgress() {
        serverUpdate?.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func beginServerUpdate(automaticBuild: String? = nil, managementOnly: Bool = false, scheduledID: String? = nil, scheduledDeadline: Date? = nil) {
        guard serverUpdate == nil else { showMaintenanceProgress(); return }
        serverUpdateProgress = ServerUpdateProgress(.preparing, message: scheduledID == nil ? "Preparing the server update…" : "Preparing the scheduled restart…")
        rebuild()
        serverUpdate = ServerUpdateWindow(engine: engine, automaticBuild: automaticBuild, managementOnly: managementOnly, scheduledID: scheduledID, scheduledDeadline: scheduledDeadline, onProgress: { [weak self] progress in
            guard progress.phase != .preparing else { return }
            self?.serverUpdateProgress = progress
            self?.rebuild()
        }) { [weak self] in
            guard let self else { return }
            self.serverUpdate = nil
            if self.serverUpdateProgress?.phase == .starting {
                self.startFeedback.begin()
                self.startFeedback.commandFinished(success: true)
            }
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
    @objc func refreshNow() { checkManagerVersion(force: true); refresh() }
    @objc func copyCode() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(displayed.code, forType: .string) }
    @objc func openLog() {
        let paths = (try? Store(paths:engine.paths).servicePaths(displayed.selected)) ?? engine.paths
        showLogs(paths:paths,name:displayed.profileName)
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
