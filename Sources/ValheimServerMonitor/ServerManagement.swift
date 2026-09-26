import AppKit
import ServerCore

final class ServerManagementWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    let tabs = NSTabView()
    private let paths: Paths
    private let summary = NSTextField(wrappingLabelWithString: "Checking server…")
    private let tools = NSButton(checkboxWithTitle: "Enable management tools (BepInEx + RCON)", target:nil, action:nil)
    private let login = NSButton(checkboxWithTitle: "Start this server at login", target:nil, action:nil)
    private let toolsHelp = NSTextField(wrappingLabelWithString: "")
    private let message = NSTextField()
    private let sendMessage = NSButton(title:"Send to Everyone",target:nil,action:nil)
    private let onlineList = ManagementPlayerList()
    private let bannedList = ManagementPlayerList(banned:true)
    private let fpsChart = LiveMetricChart()
    private let memoryChart = LiveMetricChart()
    private let recorder: PerformanceRecorder
    private var managementConnected = false
    private let result = NSTextField(wrappingLabelWithString: "")
    private let playerHelp = NSTextField(wrappingLabelWithString: "Start a server with management tools enabled to use moderation.")
    private let nextRestart = NSTextField(wrappingLabelWithString: "")
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

    init(paths: Paths, name: String, recorder: PerformanceRecorder = PerformanceRecorder(), isBusy: @escaping () -> Bool = { false }, changed: @escaping () -> Void = {}, settings: (() -> Void)? = nil, delete: (() -> Void)? = nil) {
        self.paths = paths; self.recorder = recorder; self.isBusy = isBusy; self.changed = changed
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:620,height:650), styleMask:[.titled,.closable], backing:.buffered,defer:false)
        super.init()
        window.identifier = NSUserInterfaceItemIdentifier(paths.profileID ?? ""); window.title = name + " — Server Management"; window.isReleasedWhenClosed = false; window.delegate = self
        tabs.frame = NSRect(x:16,y:70,width:588,height:565); window.contentView?.addSubview(tabs)
        func tab(_ name: String) -> NSView {
            let item = NSTabViewItem(identifier:name); item.label = name
            let view = NSView(frame:NSRect(x:0,y:0,width:560,height:525)); item.view = view; tabs.addTabViewItem(item); return view
        }
        let overview = tab("Performance & Tools")
        summary.frame = NSRect(x:20,y:447,width:520,height:67); summary.isSelectable = true; overview.addSubview(summary)
        fpsChart.title = "Server Gameplay Loop Update Frequency"; fpsChart.unit = "updates/s"
        fpsChart.toolTip = "Sampled once per second. Server game-loop updates per second, calculated from an exponential average of frame times (5% new, 95% previous). This is not client graphics FPS or network latency."
        memoryChart.title = "Managed memory"; memoryChart.unit = "MB"; memoryChart.toolTip = "Memory used by managed game code; excludes native allocations."
        for (chart,y) in [(fpsChart,290.0),(memoryChart,140.0)] { chart.frame = NSRect(x:20,y:y,width:520,height:144); overview.addSubview(chart) }
        tools.frame = NSRect(x:20,y:106,width:520,height:26); tools.target = self; tools.action = #selector(toggleTools); overview.addSubview(tools)
        toolsHelp.frame = NSRect(x:20,y:43,width:520,height:58); toolsHelp.font = .systemFont(ofSize:11); overview.addSubview(toolsHelp)
        nextRestart.frame = NSRect(x:20,y:3,width:520,height:37); nextRestart.font = .systemFont(ofSize:11); overview.addSubview(nextRestart)
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
        let players = tab("Players & Moderation")
        playerHelp.frame = NSRect(x:20,y:477,width:520,height:36); playerHelp.font = .systemFont(ofSize:11); players.addSubview(playerHelp)
        onlineList.view.frame = NSRect(x:20,y:285,width:520,height:185); players.addSubview(onlineList.view)
        bannedList.view.frame = NSRect(x:20,y:70,width:520,height:165); players.addSubview(bannedList.view)
        for (index,title) in ["Kick", "Ban", "Unban"].enumerated() {
            let button = NSButton(title:title,target:self,action:#selector(moderate(_:))); button.identifier = NSUserInterfaceItemIdentifier(title.lowercased())
            button.frame = NSRect(x:index == 2 ? 20 : 20+index*125,y:index == 2 ? 28 : 244,width:115,height:32)
            players.addSubview(button); moderationButtons.append(button)
        }
        onlineList.changed = { [weak self] in self?.updateSelection() }; bannedList.changed = { [weak self] in self?.updateSelection() }
        let messages = tab("Messages")
        let messageHelp = NSTextField(wrappingLabelWithString:"Send a message to everyone currently connected to this server. Players see a chat message from Server and a center-screen notification.\n\nOne line, up to 500 characters. Management tools must be enabled and connected.")
        messageHelp.frame = NSRect(x:20,y:375,width:520,height:120); messages.addSubview(messageHelp)
        message.frame = NSRect(x:20,y:300,width:520,height:60); message.placeholderString = "Message to players"; message.cell?.wraps = true; messages.addSubview(message)
        sendMessage.target = self; sendMessage.action = #selector(broadcast); sendMessage.frame = NSRect(x:360,y:250,width:180,height:32); sendMessage.isEnabled = false; messages.addSubview(sendMessage)
        var x: CGFloat = 16
        @discardableResult func button(_ title: String, width: CGFloat, action: @escaping () -> Void) -> NSButton {
            let b = ManagementActionButton(title:title,action:action); b.frame = NSRect(x:x,y:34,width:width,height:30); window.contentView?.addSubview(b); x += width + 8; return b
        }
        if let settings { settingsButton = button("Server Settings…",width:145,action:settings) }
        button("Open Log",width:95) { [weak self] in self?.openLog() }
        button("Logs Folder",width:110) { NSWorkspace.shared.open(paths.logs) }
        if let delete { deleteButton = button("Delete Server…",width:135,action:delete) }
        result.frame = NSRect(x:20,y:5,width:580,height:25); result.font = .systemFont(ofSize:11); window.contentView?.addSubview(result)
        [tools,login].forEach { $0.isEnabled = false }; moderationButtons.forEach { $0.isEnabled = false }; deleteButton?.isEnabled = false
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        let timer = Timer(timeInterval:1,repeats:true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer,forMode:.common); self.timer = timer
        apply(recorder.latest(for:paths.profileID ?? "")); refresh()
    }
    func windowWillClose(_ notification: Notification) { timer?.invalidate(); timer = nil }
    private func openLog() {
        if let log = try? String(contentsOf:paths.file("latest-log")), FileManager.default.fileExists(atPath:log) { NSWorkspace.shared.open(URL(fileURLWithPath:log)) }
        else { NSWorkspace.shared.open(paths.logs) }
    }
    private func refresh() {
        guard !checking, !changing else { return }; checking = true
        let generation = self.generation
        let cachedReading = recorder.latest(for:paths.profileID ?? "")
        DispatchQueue.global(qos:.utility).async {
            do {
                let status = try Lifecycle(paths:self.paths).status()
                let db = try Store(paths:self.paths).load()
                var text = "Status: \(status.state) · Players: \(status.players.isEmpty ? "Unknown" : status.players)"
                if status.detail.hasPrefix("Management tools installation failed:") { text += "\n" + status.detail }
                var reading: ManagementReading?
                if status.running && status.managementEnabled == true {
                    reading = cachedReading
                    if let reading { text += "\nValheim \(reading.version) · Uptime: \(Int(reading.uptimeSeconds)/60)m" }
                    else { text += "\nWaiting for live performance readings…" }
                } else { text += "\nStart with management tools enabled for live performance." }
                DispatchQueue.main.async {
                    self.checking = false
                    guard generation == self.generation else { self.refresh(); return }
                    self.settingsButton?.title = status.running ? "View Settings…" : "Server Settings…"
                    self.settingsButton?.isEnabled = !self.isBusy()
                    self.deleteButton?.isEnabled = !status.running && !self.isBusy() && !self.changing
                    self.summary.stringValue = text
                    self.tools.state = status.managementEnabled == true ? .on : .off
                    self.tools.isEnabled = !status.running && !self.isBusy() && !self.changing
                    self.toolsHelp.stringValue = status.running ? "Stop the server before enabling or disabling tools. Tools provide player warnings, performance and moderation." : "Tools provide player warnings, performance and moderation. Components are installed on the next start. Disabling tools preserves your world and settings."
                    self.login.state = status.autostart ? .on : .off
                    self.login.isEnabled = !self.isBusy() && !self.changing
                    self.apply(reading, fallbackBans:db.profiles.first { $0.id == self.paths.profileID }?.banned ?? "")
                    let schedule = db.restartSchedules?[self.paths.profileID ?? ""]
                    let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
                    self.nextRestart.stringValue = db.restartReceipts?[self.paths.profileID ?? ""]?.state == "waiting" ? "Scheduled restart: waiting for an empty server." : schedule?.next(after:Date()).map { "Next scheduled restart: " + formatter.string(from:$0) + "\n" + TimeZone.current.identifier } ?? "Scheduled restarts are off. Configure them in Automation."
                }
            } catch {
                DispatchQueue.main.async { self.checking = false; self.result.stringValue = error.localizedDescription }
            }
        }
    }
    func apply(_ reading: ManagementReading?, fallbackBans: String = "", now: Date = Date()) {
        managementConnected = reading != nil
        let samples = recorder.history(for:paths.profileID ?? "",now:now)
        onlineList.update((reading?.onlinePlayers ?? []).map { ($0.id,$0.name) })
        let bans = reading?.banned ?? fallbackBans.components(separatedBy:.newlines).filter { !$0.isEmpty }
        bannedList.update(bans.map { ($0,"") })
        playerHelp.stringValue = reading == nil ? "Server offline or management unavailable. Saved bans are shown; connect to modify them." : reading?.onlinePlayers == nil ? "Restart with the updated management tools to load player lists." : "Select a player to kick or ban. Select a banned entry to unban."
        fpsChart.points = samples.map { ($0.time,$0.fps) }; memoryChart.points = samples.map { ($0.time,$0.memory) }
        updateSelection()
    }
    private func updateSelection() {
        let available = managementConnected && !changing && !isBusy()
        sendMessage.isEnabled = available
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
    @objc private func toggleTools(_ sender: NSButton) { change(sender.state == .on ? "enable-management" : "disable-management",sender:sender) }
    @objc private func toggleLogin(_ sender: NSButton) { change(sender.state == .on ? "autostart-on" : "autostart-off",sender:sender) }
    @objc private func broadcast() {
        guard managementConnected, !changing, !isBusy() else { return }
        let text = message.stringValue
        changing = true; updateSelection(); result.stringValue = "Sending…"
        DispatchQueue.global(qos:.userInitiated).async {
            let error: String?
            do { try ManagedServer(paths:self.paths).broadcast(text); error = nil }
            catch let e { error = e.localizedDescription }
            DispatchQueue.main.async {
                self.changing = false
                self.result.stringValue = error ?? "Message sent to all connected players."
                if error == nil { self.message.stringValue = "" }
                self.updateSelection()
            }
        }
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
