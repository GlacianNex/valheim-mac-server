import AppKit
import ServerCore

struct ServerStatusPlaceholder: Decodable {
    var state = "Checking…", players = "", code = "", profileName = "No profile", selected = "", detail = ""
    var running = false, autostart = false, monitorAtLogin = false, installed = false
    var profiles: [Summary] = []
    struct Summary: Decodable { var id: String; var label: String }
}
class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var editor: ProfileEditor?
    var timer: Timer?
    var busy = false
    var refreshing = false
    var startFeedback = StartFeedback()
    var statusGeneration = 0
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
    }
    func command(_ action: String, args: [String] = [], input: Data? = nil) -> (Int32, String) {
        do { return (0, try engine.execute(action, arguments: args, input: input)) }
        catch { return (1, error.localizedDescription) }
    }
    func refresh() {
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
        let starting = startFeedback.pending || displayed.state == "Starting"
        let active = displayed.running || startFeedback.pending
        let state = startFeedback.pending ? "Starting…" : displayed.state
        let online = displayed.state == "Online" && !startFeedback.pending
        let color: NSColor = online ? .systemGreen : (active ? .systemOrange : .systemRed)
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
        item.button?.title = " Valhiem · " + (starting ? "Starting…" : (displayed.players.isEmpty ? "—" : displayed.players))
        item.button?.toolTip = "Valhiem Server Manager for Mac — \(displayed.profileName) — \(state), \(displayed.players.isEmpty ? "unknown" : displayed.players) players"
        let menu = NSMenu(); menu.autoenablesItems = false
        add(menu, "Valhiem Server Manager for Mac")
        menu.addItem(.separator())
        add(menu, "\(displayed.profileName) — \(state)")
        if starting { add(menu, startFeedback.pending ? "Waiting for the background service to start…" : "Preparing the world and connecting to the network…") }
        add(menu, starting || displayed.players.isEmpty ? "Players: —" : "Players: \(displayed.players) (last reported)")
        if !starting && !displayed.code.isEmpty { add(menu, "Join code: \(displayed.code) · Copy", #selector(copyCode)) }
        menu.addItem(.separator())
        let profilesMenu = NSMenu(); profilesMenu.autoenablesItems = false
        for profile in displayed.profiles {
            let row = NSMenuItem(title: profile.label, action: #selector(selectProfile(_:)), keyEquivalent: "")
            row.target = self; row.representedObject = profile.id; row.state = profile.id == displayed.selected ? .on : .off
            row.isEnabled = !busy && !active
            profilesMenu.addItem(row)
        }
        let profilesRow = NSMenuItem(title: "Selected Server", action: nil, keyEquivalent: ""); profilesRow.submenu = profilesMenu; profilesRow.isEnabled = true; menu.addItem(profilesRow)
        add(menu, "Set Up / Update Native Server…", #selector(showSetup), enabled: !busy && !active)
        add(menu, "New Server Profile…", #selector(newProfile), enabled: !busy)
        add(menu, "Edit Selected Profile…", #selector(editProfile), enabled: !busy && !active && !displayed.selected.isEmpty)
        if active { add(menu, "Stop server to switch or edit profiles") }
        menu.addItem(.separator())
        add(menu, starting ? "Starting Server…" : (busy ? "Please wait…" : "Start Server"), #selector(startServer), enabled: !busy && !active && displayed.installed && !displayed.selected.isEmpty)
        add(menu, "Stop Server (Save & Stop)", #selector(stopServer), enabled: !busy && displayed.running && displayed.state != "Installing")
        menu.addItem(.separator())
        add(menu, "Automatically Start Server at Login", #selector(toggleAutostart), enabled: !busy)
        menu.items.last?.state = displayed.autostart ? .on : .off
        add(menu, "Open Manager at Login", #selector(toggleMonitorLogin), enabled: !busy)
        menu.items.last?.state = displayed.monitorAtLogin ? .on : .off
        menu.addItem(.separator())
        if !displayed.detail.isEmpty { add(menu, "Show Last Server Error…", #selector(showError)) }
        add(menu, "Open Server Log", #selector(openLog))
        add(menu, "Open Logs Folder", #selector(openFolder))
        add(menu, "Refresh Status", #selector(refreshNow))
        menu.addItem(.separator())
        add(menu, "Quit Manager (Server Keeps Running)", #selector(quit))
        item.menu = menu
    }
    func perform(_ action: String, args: [String] = []) {
        guard !busy else { return }
        if action == "start" {
            guard !startFeedback.pending else { return }
            startFeedback.begin()
            statusGeneration += 1
        }
        busy = true; rebuild()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.command(action, args: args)
            DispatchQueue.main.async {
                self.busy = false
                if action == "start" {
                    self.startFeedback.commandFinished(success: result.0 == 0)
                    self.statusGeneration += 1
                }
                self.rebuild()
                if result.0 != 0 {
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert(); alert.messageText = "Valhiem Server Manager for Mac needs attention"
                    alert.informativeText = result.1; alert.runModal()
                }
                self.refresh()
            }
        }
    }
    @objc func selectProfile(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { perform("select-profile", args: [id]) } }
    func showEditor(_ action: String) {
        let result = command(action)
        guard result.0 == 0, let profile = try? JSONSerialization.jsonObject(with: Data(result.1.utf8)) as? [String:Any] else { return }
        editor?.window.close()
        editor = ProfileEditor(profile: profile) { values in
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
        setup = SetupWindow(engine: engine, onCreate: { [weak self] in self?.newProfile() }, onChange: { [weak self] in self?.refresh() }, onClose: { [weak self] in self?.setup = nil })
    }
    @objc func quit() { NSApp.terminate(nil) }
}
umask(0o077)
if CommandLine.arguments.contains("--service") {
    let paths = Paths()
    do { try Lifecycle(paths: paths).runService(); exit(0) }
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
