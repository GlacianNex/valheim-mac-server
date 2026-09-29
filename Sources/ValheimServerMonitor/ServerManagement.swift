import AppKit
import ServerCore

final class ServerManagementWindow: NSObject, NSWindowDelegate, NSTabViewDelegate {
    let window: NSWindow
    let tabs = NSTabView()
    let modsList = ManagementModsList()
    var modCatalog: ModsWindow?
    var logViewer: ServerLogsWindow?
    let modsSummary = NSTextField(wrappingLabelWithString: "")
    private let paths: Paths
    let summary = NSTextField(wrappingLabelWithString: "Checking server…")
    private let tools = NSButton(checkboxWithTitle: "Server Management Mods", target:nil, action:nil)
    private let login = NSButton(checkboxWithTitle: "Start this server at login", target:nil, action:nil)
    private let networking = NSButton(checkboxWithTitle: "Network Optimization Mods", target:nil, action:nil)
    private let toolsHelp = NSTextField(wrappingLabelWithString: "")
    let worldControl: WorldControlView
    private let onlineList = ManagementPlayerList()
    private let bannedList = ManagementPlayerList(banned:true)
    private let fpsChart = LiveMetricChart()
    private let memoryChart = LiveMetricChart()
    let performanceTabs = NSTabView()
    let worldTab = PingTabItem(identifier: "World Control")
    let moderationTab = PingTabItem(identifier: "Moderation")
    let pingTab = PingTabItem(identifier: "Ping")
    let pingGraphs = PlayerPingGraphs()
    func setPingEnabled(_ enabled: Bool) {
        pingTab.available = enabled
        if !enabled && performanceTabs.selectedTabViewItem === pingTab { performanceTabs.selectTabViewItem(at: 0) }
        performanceTabs.needsDisplay = true
    }
    func tabView(_ tabView: NSTabView, shouldSelect tabViewItem: NSTabViewItem?) -> Bool {
        guard let item = tabViewItem as? PingTabItem else { return true }
        return item.available
    }
    func renderMods(management: Bool, networking: Bool) {
        modsList.update(management:management, networking:networking, runtime:ManagedServer(paths:paths).runtime, customLoader:ManagedServer(paths:paths).loaderEnabled, running:latestStatus.running)
        modsSummary.stringValue = ""
    }

    func setManagementEnabled(_ enabled: Bool) {
        worldTab.available = enabled
        moderationTab.available = enabled
        if !enabled && (tabs.selectedTabViewItem === worldTab || tabs.selectedTabViewItem === moderationTab) {
            tabs.selectTabViewItem(at: 0)
        }
        tabs.toolTip = enabled ? nil : "Enable Server Management Mods above the tabs to use Moderation and World Control. Automation remains available; in-game warnings require management tools."
        tabs.needsDisplay = true
    }
    private let recorder: PerformanceRecorder
    private var managementConnected = false
    private let result = NSTextField(wrappingLabelWithString: "")
    private let playerHelp = NSTextField(wrappingLabelWithString: "Start a server with management tools enabled to use moderation.")
    private let nextRestart = NSTextField(wrappingLabelWithString: "")
    let statusLight = NSTextField(labelWithString: "●")
    let firstStartHint = NSTextField(labelWithString: "Starting this server for the first time may take a few minutes.")
    let startStopButton = NSButton(title:"Start Server",target:nil,action:nil)
    private let serverAction: ((String) -> Void)?
    private var latestStatus = ServerStatus()
    private var pendingServerAction: String?
    private var settingsButton: NSButton?
    private var deleteButton: NSButton?
    private var moderationButtons: [NSButton] = []
    private var scheduleEditor: RestartScheduleEditor!
    private var timer: Timer?
    private var checking = false
    private var changing = false
    private var generation = 0
    private let isBusy: () -> Bool
    private let changed: () -> Void

    init(paths: Paths, name: String, recorder: PerformanceRecorder = PerformanceRecorder(), isBusy: @escaping () -> Bool = { false }, changed: @escaping () -> Void = {}, settings: (() -> Void)? = nil, delete: (() -> Void)? = nil, serverAction: ((String) -> Void)? = nil) {
        self.serverAction = serverAction; self.paths = paths; self.recorder = recorder; self.worldControl = WorldControlView(paths:paths,busy:isBusy); self.isBusy = isBusy; self.changed = changed
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:640,height:860), styleMask:[.titled,.closable], backing:.buffered,defer:false)
        super.init()
        window.identifier = NSUserInterfaceItemIdentifier(paths.profileID ?? ""); window.title = name + " — Server Management"; window.isReleasedWhenClosed = false; window.delegate = self
        tabs.frame = NSRect(x:16,y:70,width:608,height:605); window.contentView?.addSubview(tabs)
        func tab(_ name: String) -> NSView {
            let item: NSTabViewItem = name == "World Control" ? worldTab : name == "Moderation" ? moderationTab : NSTabViewItem(identifier:name); item.label = name
            let view = NSView(frame:NSRect(x:0,y:0,width:580,height:565)); item.view = view; tabs.addTabViewItem(item); return view
        }
        tabs.delegate = self
        let performance = tab("Performance")
        performanceTabs.frame = NSRect(x:0,y:0,width:580,height:565)
        performanceTabs.autoresizingMask = [.width, .height]
        performance.addSubview(performanceTabs)
        let serverTab = NSTabViewItem(identifier:"Server"); serverTab.label = "Server"
        let overview = NSView(frame:NSRect(x:0,y:0,width:552,height:525))
        serverTab.view = overview; performanceTabs.addTabViewItem(serverTab)
        summary.frame = NSRect(x:46,y:805,width:570,height:41); summary.isSelectable = true; window.contentView?.addSubview(summary)
        statusLight.frame = NSRect(x:24,y:825,width:20,height:21)
        statusLight.font = .systemFont(ofSize:17); window.contentView?.addSubview(statusLight)
        firstStartHint.frame = NSRect(x:24,y:779,width:592,height:20)
        firstStartHint.font = .systemFont(ofSize:12); firstStartHint.textColor = .secondaryLabelColor
        firstStartHint.isHidden = true; window.contentView?.addSubview(firstStartHint)
        fpsChart.title = "Server Gameplay Loop Update Frequency"; fpsChart.unit = "updates/s"
        fpsChart.toolTip = "Sampled once per second. Server game-loop updates per second, calculated from an exponential average of frame times (5% new, 95% previous). This is not client graphics FPS or network latency."
        memoryChart.title = "Managed memory"; memoryChart.unit = "MB"; memoryChart.toolTip = "Memory used by managed game code; excludes native allocations."
        for (chart,y) in [(fpsChart,282.0),(memoryChart,40.0)] { chart.frame = NSRect(x:20,y:y,width:520,height:234); overview.addSubview(chart) }
        tools.frame = NSRect(x:24,y:749,width:280,height:26)
        tools.toolTip = "Enables performance graphs, moderation, world controls and player warnings through RCON. Uses the shared BepInEx + Jötunn core. Stop the server to change this."
        tools.target = self; tools.action = #selector(toggleTools); window.contentView?.addSubview(tools)
        networking.frame = NSRect(x:320,y:749,width:296,height:26)
        networking.toolTip = "Enables NetworkPerformanceSystem 1.6.0 with BepInEx + Jötunn. Adjusts network traffic and object ownership. Players do not need to install it. Optional; test with your players before relying on it. Stop the server to change this."
        networking.target = self; networking.action = #selector(toggleNetworking); window.contentView?.addSubview(networking)
        for (text,x) in [("BepInEx, RCON, Jötunn",44.0),("NetworkPerformanceSystem",340.0)] {
            let mods = NSTextField(labelWithString:text)
            mods.frame = NSRect(x:x,y:730,width:276,height:17)
            mods.font = .systemFont(ofSize:11); mods.textColor = .secondaryLabelColor
            window.contentView?.addSubview(mods)
        }
        toolsHelp.frame = NSRect(x:24,y:704,width:592,height:17); toolsHelp.font = .systemFont(ofSize:11); window.contentView?.addSubview(toolsHelp)
        nextRestart.frame = NSRect(x:20,y:0,width:520,height:33); nextRestart.font = .systemFont(ofSize:11); overview.addSubview(nextRestart)
        let automation = tab("Automation")
        login.frame = NSRect(x:20,y:490,width:520,height:24); login.target = self; login.action = #selector(toggleLogin); automation.addSubview(login)
        let note = NSTextField(wrappingLabelWithString:"The settings here apply only to this server.\n\nAutomatic Valheim software updates apply to all servers. Change that setting beside Valheim Server Build in the menu bar.")
        note.font = .systemFont(ofSize:11); note.textColor = .secondaryLabelColor; note.frame = NSRect(x:20,y:421,width:520,height:62); automation.addSubview(note)
        let initial = (try? Store(paths:paths).load())
        scheduleEditor = RestartScheduleEditor(schedule:initial?.restartSchedules?[paths.profileID ?? ""] ?? RestartSchedule()) { [weak self] schedule in
            guard let self else { return }
            guard !self.isBusy() else { throw MonitorError("Wait for the current server operation to finish.") }
            try Store(paths:self.paths).update { db in
                guard let id = self.paths.profileID, db.profiles.contains(where:{$0.id == id}) else { throw MonitorError("Server no longer exists.") }
                if db.restartSchedules == nil { db.restartSchedules = [:] }
                db.restartSchedules?[id] = schedule; db.restartReceipts?.removeValue(forKey:id)
            }
            self.changed(); self.refresh()
        }
        scheduleEditor.view.frame.origin = NSPoint(x:0,y:-5); automation.addSubview(scheduleEditor.view)
        let players = tab("Moderation")
        playerHelp.frame = NSRect(x:20,y:477,width:520,height:36); playerHelp.font = .systemFont(ofSize:11); players.addSubview(playerHelp)
        onlineList.view.frame = NSRect(x:20,y:285,width:520,height:185); players.addSubview(onlineList.view)
        bannedList.view.frame = NSRect(x:20,y:70,width:520,height:165); players.addSubview(bannedList.view)
        for (index,title) in ["Kick", "Ban", "Unban"].enumerated() {
            let button = NSButton(title:title,target:self,action:#selector(moderate(_:))); button.identifier = NSUserInterfaceItemIdentifier(title.lowercased())
            button.frame = NSRect(x:index == 2 ? 20 : 20+index*125,y:index == 2 ? 28 : 244,width:115,height:32)
            players.addSubview(button); moderationButtons.append(button)
        }
        let access = NSButton(title:"Admins & Permitted Players…",target:self,action:#selector(editAccessLists))
        access.bezelStyle = .rounded; access.frame = NSRect(x:155,y:28,width:300,height:32)
        access.toolTip = "View admin and permitted platform IDs. Stop the server to edit. A nonempty permitted list excludes everyone else."
        players.addSubview(access)
        onlineList.changed = { [weak self] in self?.updateSelection() }; bannedList.changed = { [weak self] in self?.updateSelection() }
        let world = tab("World Control")
        worldControl.frame = world.bounds; worldControl.autoresizingMask = [.width,.height]; world.addSubview(worldControl)
        let backup = tab("Backups")
        worldControl.backupView.frame = backup.bounds; worldControl.backupView.autoresizingMask = [.width,.height]; backup.addSubview(worldControl.backupView)
        let mods = tab("Mods")
        modsList.view.translatesAutoresizingMaskIntoConstraints = false
        mods.addSubview(modsList.view)
        let installMod = NSButton(title:"Open Mod Catalog",target:self,action:#selector(openModCatalog))
        installMod.bezelStyle = .rounded; installMod.translatesAutoresizingMaskIntoConstraints = false
        mods.addSubview(installMod)
        modsList.toggle = { [weak self] entry in self?.changeMod(entry) }
        NSLayoutConstraint.activate([
            modsList.view.topAnchor.constraint(equalTo:mods.topAnchor,constant:12),
            modsList.view.leadingAnchor.constraint(equalTo:mods.leadingAnchor,constant:12),
            modsList.view.trailingAnchor.constraint(equalTo:mods.trailingAnchor,constant:-12),
            modsList.view.bottomAnchor.constraint(equalTo:installMod.topAnchor,constant:-12),
            installMod.leadingAnchor.constraint(equalTo:mods.leadingAnchor,constant:12),
            installMod.bottomAnchor.constraint(equalTo:mods.bottomAnchor,constant:-12)
        ])
        renderMods(management:initial?.managedServers?[paths.profileID ?? ""] == true,
                   networking:initial?.networkOptimizations?[paths.profileID ?? ""] == true)
        pingTab.label = "Ping"; pingTab.view = pingGraphs
        performanceTabs.addTabViewItem(pingTab); performanceTabs.delegate = self
        setManagementEnabled(initial?.managedServers?[paths.profileID ?? ""] == true)
        setPingEnabled(initial?.profiles.first { $0.id == paths.profileID }?.crossplay == false)
        performanceTabs.toolTip = "Ping is only available with CrossPlay turned off"
        startStopButton.frame = NSRect(x:16,y:34,width:94,height:30)
        startStopButton.font = .systemFont(ofSize:11)
        startStopButton.bezelStyle = .rounded; startStopButton.target = self; startStopButton.action = #selector(toggleServer)
        startStopButton.isEnabled = false
        window.contentView?.addSubview(startStopButton)
        var x: CGFloat = 116
        @discardableResult func button(_ title: String, width: CGFloat, action: @escaping () -> Void) -> NSButton {
            let b = ManagementActionButton(title:title,action:action); b.frame = NSRect(x:x,y:34,width:width,height:30); window.contentView?.addSubview(b); b.font = .systemFont(ofSize:11); x += width + 6; return b
        }
        if let settings { settingsButton = button("World Settings",width:100,action:settings) }
        button("Open Log",width:73) { [weak self] in self?.openLog() }
        button("Logs Folder",width:87) { NSWorkspace.shared.open(paths.logs) }
        button("Server Folder",width:97) {
            let managed = ManagedServer(paths:paths)
            let folder = managed.loaderEnabled && FileManager.default.fileExists(atPath:managed.runtime.path) ? managed.runtime : paths.server
            NSWorkspace.shared.open(folder)
        }
        if let delete { deleteButton = button("Delete Server…",width:117,action:delete) }
        result.frame = NSRect(x:20,y:5,width:580,height:25); result.font = .systemFont(ofSize:11); window.contentView?.addSubview(result)
        [tools,networking,login].forEach { $0.isEnabled = false }; moderationButtons.forEach { $0.isEnabled = false }; deleteButton?.isEnabled = false
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        let timer = Timer(timeInterval:1,repeats:true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer,forMode:.common); self.timer = timer
        apply(recorder.latest(for:paths.profileID ?? "")); refresh()
    }
    private func changeMod(_ entry:ModInventoryEntry) {
        guard !changing, !isBusy(), let id = entry.modID, let profile = paths.profileID else { modsList.table.reloadData(); return }
        changing = true
        DispatchQueue.global(qos:.userInitiated).async {
            let outcome = Result { try ModLibrary(paths:self.paths,profileID:profile).select(id,enabled:!entry.enabled) }
            DispatchQueue.main.async {
                self.changing = false
                switch outcome {
                case .success: self.result.stringValue = "Changes apply on the next server start. Required dependencies are enabled automatically."
                case .failure(let error):
                    self.modsList.table.reloadData()
                    let alert = NSAlert()
                    alert.messageText = "Mod Selection Unchanged"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .informational
                    let icon = NSImage(systemSymbolName:"info.circle",accessibilityDescription:"Information")
                    icon?.size = NSSize(width:64,height:64)
                    alert.icon = icon
                    alert.addButton(withTitle:"OK")
                    alert.beginSheetModal(for:self.window)
                }
                self.changed(); self.refresh()
            }
        }
    }
    @objc func openModCatalog() { showModCatalog() }
    func showModCatalog(loadCatalogs:Bool = true) {
        if let modCatalog { modCatalog.window.makeKeyAndOrderFront(nil); return }
        do {
            guard let id = paths.profileID else { throw MonitorError("Select a server first.") }
            let profile = try Store(paths:paths).selected()
            modCatalog = try ModsWindow(paths:paths,profileID:id,name:profile.label,loadCatalogs:loadCatalogs)
        } catch { result.stringValue = error.localizedDescription }
    }
    func windowWillClose(_ notification: Notification) { timer?.invalidate(); timer = nil; logViewer?.window.close(); logViewer = nil; modCatalog?.window.close(); modCatalog = nil }
    private func openLog() {
        if logViewer == nil { logViewer = ServerLogsWindow(paths:paths,name:window.title.replacingOccurrences(of:" — Server Management",with:"")) }
        logViewer?.show()
    }
    private func refresh() {
        guard !checking, !changing else { return }; checking = true
        let generation = self.generation
        let cachedReading = recorder.latest(for:paths.profileID ?? "")
        DispatchQueue.global(qos:.utility).async {
            do {
                let status = try Lifecycle(paths:self.paths).status()
                let db = try Store(paths:self.paths).load()
                let reading = status.running && status.managementEnabled == true ? cachedReading : nil
                let runtime = ManagedServer(paths:self.paths).runtime
                let liveMods = ModRuntimeStatus.read(paths:self.paths,runtime:runtime)
                let inventory = Result { try ModLibrary(paths:self.paths,profileID:self.paths.profileID ?? "").inventory(runtime:runtime,running:status.running,live:liveMods) }
                DispatchQueue.main.async {
                    self.checking = false
                    guard generation == self.generation else { self.refresh(); return }
                    self.settingsButton?.title = "World Settings"
                    self.settingsButton?.isEnabled = !self.isBusy()
                    self.deleteButton?.isEnabled = !status.running && !self.isBusy() && !self.changing
                    self.latestStatus = status
                    if !self.isBusy() { self.pendingServerAction = nil }
                    self.renderServerStatus(status, reading:reading)
                    self.worldControl.refresh(running:status.running,management:status.managementEnabled == true)
                    self.setManagementEnabled(status.managementEnabled == true)
                    self.setPingEnabled(status.crossplay == false)
                    self.tools.state = status.managementEnabled == true ? .on : .off
                    self.tools.isEnabled = !status.running && !self.isBusy() && !self.changing
                    self.networking.state = db.networkOptimizations?[self.paths.profileID ?? ""] == true ? .on : .off
                    self.networking.isEnabled = self.tools.isEnabled
                    self.renderMods(management:self.tools.state == .on, networking:self.networking.state == .on)
                    switch inventory {
                    case .success(let entries): self.modsList.appendInventory(entries,live:liveMods)
                    case .failure(let error): self.result.stringValue = "Could not read mods: " + error.localizedDescription
                    }
                    self.toolsHelp.stringValue = status.running ? "Stop the server to change these options." : "Changes apply on the next start. Custom mods are managed in the Mods tab."
                    self.login.state = status.autostart ? .on : .off
                    self.login.isEnabled = !self.isBusy() && !self.changing
                    self.apply(reading, fallbackBans:db.profiles.first { $0.id == self.paths.profileID }?.banned ?? "")
                    let schedule = db.restartSchedules?[self.paths.profileID ?? ""]
                    let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
                    self.nextRestart.stringValue = db.restartReceipts?[self.paths.profileID ?? ""]?.state == "waiting" ? "Scheduled restart: waiting for an empty server." : schedule?.next(after:Date()).map { "Next scheduled restart: " + formatter.string(from:$0) + "\n" + TimeZone.current.identifier } ?? ""
                }
            } catch {
                DispatchQueue.main.async { self.checking = false; self.result.stringValue = error.localizedDescription }
            }
        }
    }
    func renderServerStatus(_ status: ServerStatus, reading: ManagementReading?) {
        latestStatus = status
        let state = pendingServerAction.map { $0 == "start" ? "Starting" : "Stopping" } ?? status.state
        let version = reading?.version ?? "Unavailable"
        let uptime = reading.map { "\(Int($0.uptimeSeconds)/60)m" } ?? "—"
        summary.stringValue = "Status: \(state) · Players: \(status.players.isEmpty ? "Unknown" : status.players)\nValheim: \(version) · Uptime: \(uptime)"
        let lightColor: NSColor
        switch state {
        case "Online", "Running": lightColor = .systemGreen
        case "Starting", "Stopping", "Updating", "Installing": lightColor = .systemOrange
        case "Stopped": lightColor = .secondaryLabelColor
        default: lightColor = .systemRed
        }
        statusLight.textColor = lightColor; statusLight.toolTip = state
        let marker = try? String(contentsOf: paths.stateRoot.appendingPathComponent("first-start-log"), encoding: .utf8)
        let latestLog = try? String(contentsOf: paths.file("latest-log"), encoding: .utf8)
        let firstLaunch = marker.map { $0 != "previously-started" && (latestLog == nil || $0 == latestLog) } ?? (latestLog == nil)
        firstStartHint.isHidden = state != "Starting" || !firstLaunch
        summary.toolTip = reading == nil ? "Live version and uptime require a running server with Server Management Mods enabled." : nil
        if status.detail.hasPrefix("Management tools installation failed:") { result.stringValue = status.detail }
        let transitioning = ["Starting","Stopping","Updating","Installing"].contains(state)
        startStopButton.title = transitioning ? state + "…" : status.running ? "Stop Server" : "Start Server"
        startStopButton.toolTip = status.running ? "Save the world and stop this server." : "Start this server."
        startStopButton.isEnabled = serverAction != nil && status.installed && !transitioning && !isBusy() && !changing
    }
    @objc private func toggleServer() {
        guard startStopButton.isEnabled, let serverAction else { return }
        let action = latestStatus.running ? "stop" : "start"
        pendingServerAction = action; generation += 1
        renderServerStatus(latestStatus,reading:recorder.latest(for:paths.profileID ?? ""))
        serverAction(action)
        refresh()
    }
    func apply(_ reading: ManagementReading?, fallbackBans: String = "", now: Date = Date()) {
        managementConnected = reading != nil
        let samples = recorder.history(for:paths.profileID ?? "",now:now)
        onlineList.update((reading?.onlinePlayers ?? []).map { ($0.id,$0.name) })
        let bans = reading?.banned ?? fallbackBans.components(separatedBy:.newlines).filter { !$0.isEmpty }
        bannedList.update(bans.map { ($0,"") })
        playerHelp.stringValue = reading == nil ? "Server offline or management unavailable. Saved bans are shown; connect to modify them." : reading?.onlinePlayers == nil ? "Restart with the updated management tools to load player lists." : "Select a player to kick or ban. Select a banned entry to unban."
        fpsChart.points = samples.map { ($0.time,$0.fps) }; memoryChart.points = samples.map { ($0.time,$0.memory) }
        pingGraphs.update(reading: pingTab.available ? reading : nil, samples: samples)
        updateSelection()
    }
    private func updateSelection() {
        let available = managementConnected && !changing && !isBusy()
        for button in moderationButtons { button.isEnabled = available && (button.identifier?.rawValue == "unban" ? bannedList.selectedID != nil : onlineList.selectedID != nil) }
    }
    private func change(_ action: String, sender: NSButton) {
        guard !changing, !isBusy() else { refresh(); return }
        changing = true; generation += 1; sender.isEnabled = false; result.stringValue = "Saving…"
        DispatchQueue.global(qos:.userInitiated).async {
            let error: String?
            do { _ = try Engine(paths:self.paths).execute(action,arguments:[self.paths.profileID ?? ""]); error = nil }
            catch let e { error = e.localizedDescription }
            DispatchQueue.main.async {
                self.changing = false; self.generation += 1; self.result.stringValue = error ?? "Saved."
                self.changed(); self.refresh()
            }
        }
    }
    @objc private func toggleNetworking(_ sender: NSButton) { change(sender.state == .on ? "enable-networking" : "disable-networking",sender:sender) }
    @objc private func toggleTools(_ sender: NSButton) { change(sender.state == .on ? "enable-management" : "disable-management",sender:sender) }
    @objc private func toggleLogin(_ sender: NSButton) { change(sender.state == .on ? "autostart-on" : "autostart-off",sender:sender) }
    @objc private func editAccessLists() {
        guard !changing, !isBusy() else { return }
        do {
            let store = try Store(paths:paths)
            var profile = try store.selected()
            let running = Lifecycle(paths:paths).isActive
            let alert = NSAlert(); alert.messageText = "Admins & Permitted Players"
            alert.informativeText = "Enter platform IDs, one per line or separated by commas. A nonempty permitted list excludes everyone else." + (running ? "\n\nStop the server to edit these lists." : "\n\nChanges apply on the next start.")
            let container = NSView(frame:NSRect(x:0,y:0,width:440,height:260))
            func editor(_ title:String,_ value:String,_ y:CGFloat) -> NSTextView {
                let label = NSTextField(labelWithString:title); label.frame = NSRect(x:0,y:y+94,width:440,height:20); container.addSubview(label)
                let scroll = NSScrollView(frame:NSRect(x:0,y:y,width:440,height:88)); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
                let text = NSTextView(frame:scroll.bounds); text.isRichText = false; text.isEditable = !running; text.string = value; text.font = .systemFont(ofSize:13)
                text.isVerticallyResizable = true; text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
                scroll.documentView = text; container.addSubview(scroll); return text
            }
            let admins = editor("Admin IDs",profile.admins,140)
            let permitted = editor("Permitted IDs — leave empty to allow everyone",profile.permitted,10)
            alert.accessoryView = container
            alert.addButton(withTitle:running ? "Close" : "Save")
            if !running { alert.addButton(withTitle:"Cancel") }
            guard alert.runModal() == .alertFirstButtonReturn, !running else { return }
            profile.admins = admins.string.replacingOccurrences(of:",",with:"\n")
            profile.permitted = permitted.string.replacingOccurrences(of:",",with:"\n")
            try store.save(profile)
            result.stringValue = "Access lists saved. Changes apply on the next start."
            changed(); refresh()
        } catch { result.stringValue = error.localizedDescription }
    }
    @objc private func moderate(_ sender: NSButton) {
        guard !changing, !isBusy(), let action = sender.identifier?.rawValue else { return }
        guard let player = action == "unban" ? bannedList.selectedID : onlineList.selectedID else { result.stringValue = "Select a player first."; return }
        guard managementConnected else { return }
        let alert = NSAlert(); alert.messageText = "\(sender.title) \(player)?"; alert.informativeText = "This applies only to \(window.title)."; alert.addButton(withTitle:"Cancel"); alert.addButton(withTitle:sender.title)
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        changing = true; moderationButtons.forEach { $0.isEnabled = false }
        DispatchQueue.global(qos:.userInitiated).async {
            let text: String
            do { text = try ManagedServer(paths:self.paths).moderate(action:action,target:player) }
            catch { text = error.localizedDescription }
            DispatchQueue.main.async { self.changing = false; self.result.stringValue = text; self.refresh() }
        }
    }
}

private final class ManagementActionButton: NSButton {
    private let invoke: () -> Void
    init(title:String, action:@escaping () -> Void) { invoke = action; super.init(frame:.zero); self.title = title; bezelStyle = .rounded; target = self; self.action = #selector(clicked) }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func clicked() { invoke() }
}

/// Bundled rows are read-only; installed packages can be selected for dependency-aware changes.
final class ManagementModsList: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let view = NSScrollView()
    let table = NSTableView()
    var rows: [(name:String, enabled:Bool, version:String)] = []
    var extra: [ModInventoryEntry] = []
    var toggle: ((ModInventoryEntry) -> Void)?
    var selectionChanged: (() -> Void)?
    var selectedMod: ModInventoryEntry? {
        let index = table.selectedRow - rows.count
        return extra.indices.contains(index) ? extra[index] : nil
    }
    private func reloadPreservingSelection() {
        let id = selectedMod?.modID
        table.reloadData()
        if let id, let index = extra.firstIndex(where: { $0.modID == id }) {
            table.selectRowIndexes(IndexSet(integer:rows.count + index),byExtendingSelection:false)
        } else { table.deselectAll(nil) }
        selectionChanged?()
    }
    func tableViewSelectionDidChange(_ notification:Notification) { selectionChanged?() }
    var serverRunning = false
    var liveMods: [ModRuntimeStatus.Entry] = []
    override init() {
        super.init()
        for (id,title,width) in [("enabled","",32.0),("status","Status",130.0),("name","Name",225.0),("version","Version",85.0),("players","Client",85.0)] {
            let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier(id))
            column.title = title; column.width = width; column.isEditable = false
            table.addTableColumn(column)
        }
        table.dataSource = self; table.delegate = self
        table.rowHeight = 30; table.usesAlternatingRowBackgroundColors = true
        table.selectionHighlightStyle = .regular

        view.documentView = table; view.hasVerticalScroller = true; view.borderType = .bezelBorder
    }
    func update(management:Bool, networking:Bool, runtime:URL, customLoader:Bool = false, running:Bool = false) {
        serverRunning = running
        let file = runtime.appendingPathComponent("mod-versions.json")
        var versions = (try? JSONDecoder().decode([String:String].self,from:Data(contentsOf:file))) ?? [:]
        // Older installations have package metadata for these dependencies.
        for (name,directory) in [("Jötunn","Jotunn"),("NetworkPerformanceSystem","NetworkPerformanceSystem")] where versions[name] == nil {
            if let data = try? Data(contentsOf:runtime.appendingPathComponent("licenses/" + directory + "/manifest.json")),
               let json = try? JSONSerialization.jsonObject(with:data) as? [String:Any] {
                versions[name] = json["version_number"] as? String
            }
        }
        rows = [("BepInEx",management || networking || customLoader,versions["BepInEx"] ?? "Unknown"),
                ("Jötunn",management || networking || customLoader,versions["Jötunn"] ?? "Unknown"),
                ("Manager RCON",management,versions["Manager RCON"] ?? "Unknown"),
                ("NetworkPerformanceSystem",networking,versions["NetworkPerformanceSystem"] ?? "Unknown")]
        reloadPreservingSelection()
    }
    func appendInventory(_ entries:[ModInventoryEntry], live:ModRuntimeStatus?) {
        let selectedID = selectedMod?.modID
        extra = entries; liveMods = live?.mods ?? []; table.reloadData()
        if let selectedID, let index = extra.firstIndex(where: { $0.modID == selectedID }) {
            table.selectRowIndexes(IndexSet(integer:rows.count + index),byExtendingSelection:false)
        } else { table.deselectAll(nil) }
        selectionChanged?()
    }
    func numberOfRows(in tableView:NSTableView) -> Int { rows.count + extra.count }
    func tableView(_ tableView:NSTableView, shouldSelectRow row:Int) -> Bool { extra.indices.contains(row - rows.count) && extra[row - rows.count].modID != nil }
    private func bundledHint(_ row:Int) -> String {
        guard rows.indices.contains(row) else { return "" }
        let name = rows[row].name
        let control = name == "NetworkPerformanceSystem" ? "Network Optimization Mods" : name == "Manager RCON" ? "Server Management Mods" : "Server Management Mods or Network Optimization Mods"
        return "Controlled by " + control + " at the top of this window. Stop the server to change it."
    }
    func tableView(_ tableView:NSTableView, toolTipFor cell:NSCell, rect:NSRectPointer, tableColumn:NSTableColumn?, row:Int, mouseLocation:NSPoint) -> String {
        if rows.indices.contains(row) { return bundledHint(row) }
        let index = row - rows.count
        return extra.indices.contains(index) ? extra[index].detail : ""
    }
    private func centeredCell(_ field:NSTextField) -> NSView {
        let cell = NSTableCellView()
        field.alignment = .center
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field); cell.textField = field; cell.toolTip = field.toolTip
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:3),
            field.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-3),
            field.centerYAnchor.constraint(equalTo:cell.centerYAnchor)
        ])
        return cell
    }
    func tableView(_ tableView:NSTableView, viewFor column:NSTableColumn?, row:Int) -> NSView? {
        if column?.identifier.rawValue == "enabled" {
            let index = row - rows.count
            let entry = extra.indices.contains(index) ? extra[index] : nil
            let checkbox = ManagementModCheckbox { [weak self] in
                guard let entry else { return }; self?.toggle?(entry)
            }
            checkbox.state = (entry?.enabled ?? (rows.indices.contains(row) && rows[row].enabled)) ? .on : .off
            checkbox.isEnabled = entry?.modID != nil
            checkbox.toolTip = entry?.modID != nil ? "Enable or disable this mod for the next server start. Dependencies are checked automatically." : bundledHint(row)
            let cell = NSTableCellView(); checkbox.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(checkbox)
            NSLayoutConstraint.activate([checkbox.centerXAnchor.constraint(equalTo:cell.centerXAnchor),checkbox.centerYAnchor.constraint(equalTo:cell.centerYAnchor)])
            return cell
        }
        if row >= rows.count, extra.indices.contains(row - rows.count) {
            let entry = extra[row - rows.count]
            let value = column?.identifier.rawValue == "status" ? entry.status : column?.identifier.rawValue == "version" ? entry.version : column?.identifier.rawValue == "players" ? (entry.playersRequired ? "Yes" : "No") : entry.name
            let field = NSTextField(labelWithString:value); field.toolTip = entry.detail
            if column?.identifier.rawValue == "players", !entry.playersRequired { field.toolTip = "No client-install requirement detected. Unknown requirements are not verified as server-only.\n" + entry.detail }
            field.textColor = entry.status.contains("Failed") || entry.status.contains("Errors") ? .systemRed : .labelColor
            field.lineBreakMode = .byTruncatingTail
            return centeredCell(field)
        }
        guard rows.indices.contains(row) else { return nil }
        let entry = rows[row]
        let value: String
        switch column?.identifier.rawValue {
        case "status":
            if !serverRunning { value = entry.enabled ? "Enabled" : "Disabled" }
            else if let state = liveMods.first(where:{ $0.name == entry.name || (entry.name == "Jötunn" && $0.name == "Jotunn") }) { value = state.status == "Loaded" ? "Running" : "Failed" }
            else if entry.name == "BepInEx" && !liveMods.isEmpty { value = "Running" }
            else { value = entry.enabled ? "Checking…" : "Disabled" }
        case "version": value = entry.version
        case "players": value = "No"
        default: value = entry.name
        }
        let field = NSTextField(labelWithString:value)
        field.textColor = value == "Failed" ? .systemRed : .disabledControlTextColor
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = bundledHint(row)
        return centeredCell(field)
    }
}

private final class ManagementModCheckbox: NSButton {
    private let invoke: () -> Void
    init(action:@escaping () -> Void) {
        invoke = action; super.init(frame:.zero)
        setButtonType(.switch); title = ""; target = self; self.action = #selector(clicked)
        setAccessibilityLabel("Enable mod")
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func clicked() { invoke() }
}
