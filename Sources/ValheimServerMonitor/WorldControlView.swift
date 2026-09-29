import AppKit
import ServerCore

private struct WorldReading: Decodable {
    let day: Int
    let seconds: Double
    let dayFraction: Double
    let raid: String
    let raidsPausedSeconds: Double
    let raidPauseAvailable: Bool
    let events: [String]
    let players: [OnlinePlayer]
    let saveInProgress: Bool
    let lastSaveSecondsAgo: Double?
}
final class WorldControlView: NSView {
    let tabs = NSTabView()
    let backupView = NSView(frame:NSRect(x:0,y:0,width:580,height:565))
    private let backupFeedback = NSTextField(wrappingLabelWithString:"")
    private var feedbackText: String {
        get { feedback.stringValue }
        set { feedback.stringValue = newValue; backupFeedback.stringValue = newValue }
    }
    private let paths: Paths
    private let busy: () -> Bool
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private let message = NSTextField(), welcome = NSTextField(), backupName = NSTextField()
    private let backups = NSPopUpButton(), advance = NSPopUpButton(), pause = NSPopUpButton(), raids = NSPopUpButton(), players = NSPopUpButton()
    private let timeStatus = NSTextField(wrappingLabelWithString:"Start the server for world controls.")
    private let raidStatus = NSTextField(wrappingLabelWithString:"Start the server for raid controls.")
    private let saveStatus = NSTextField(wrappingLabelWithString:"Stop this server before creating or restoring a named backup.")
    private var buttons: [(NSButton, String)] = []
    private var settings = WorldMessageSettings()
    private var snapshots: [WorldBackup] = []
    private var running = false, management = false, changing = false, polling = false, pauseAvailable = false, ready = false
    private var lastBackupCheck = Date.distantPast
    init(paths: Paths, busy: @escaping () -> Bool) {
        self.paths = paths; self.busy = busy
        super.init(frame:NSRect(x:0,y:0,width:580,height:565))
        tabs.frame = NSRect(x:0,y:38,width:580,height:527); tabs.autoresizingMask = [.width,.height]; addSubview(tabs)
        feedback.frame = NSRect(x:20,y:0,width:540,height:35); feedback.font = .systemFont(ofSize:11); addSubview(feedback)
        func tab(_ title:String) -> NSView {
            let item = NSTabViewItem(identifier:title); item.label = title
            let view = NSView(frame:NSRect(x:0,y:0,width:552,height:487)); item.view = view; tabs.addTabViewItem(item); return view
        }
        func label(_ text:String, _ view:NSView, _ y:Double, height:Double = 45) {
            let v = NSTextField(wrappingLabelWithString:text); v.frame = NSRect(x:20,y:y,width:512,height:height); v.font = .systemFont(ofSize:12); view.addSubview(v)
        }
        func field(_ v:NSView,_ view:NSView,_ y:Double) { v.frame = NSRect(x:20,y:y,width:512,height:28); view.addSubview(v) }
        func button(_ title:String,_ view:NSView,_ x:Double,_ y:Double,_ width:Double,_ category:String,_ action:@escaping () -> Void) {
            let b = WorldActionButton(title:title,action:action); b.frame = NSRect(x:x,y:y,width:width,height:30); view.addSubview(b); buttons.append((b,category))
        }
        let messages = tab("Messages")
        label("Broadcasts appear in chat and at the center of every connected player's screen. Use one line, up to 500 characters.",messages,420)
        message.placeholderString = "Message to everyone"; field(message,messages,385)
        button("Send to Everyone",messages,340,346,192,"message") { [weak self] in self?.broadcast() }
        label("Welcome message",messages,289,height:22)
        label("Sent privately when a player joins. Leave empty to turn it off.",messages,254,height:30)
        welcome.placeholderString = "Welcome message (optional)"; field(welcome,messages,215)
        button("Save Welcome Message",messages,300,173,232,"local") { [weak self] in self?.saveWelcome() }
        backupFeedback.frame = NSRect(x:20,y:0,width:540,height:35); backupFeedback.font = .systemFont(ofSize:11); backupView.addSubview(backupFeedback)
        saveStatus.frame = NSRect(x:20,y:399,width:512,height:66); saveStatus.font = .systemFont(ofSize:12); backupView.addSubview(saveStatus)
        button("Save World Now",backupView,20,357,180,"live") { [weak self] in self?.command("worldSave") }
        label("Named backups include this server's world files. Stop the server first so no save can change while it is copied.",backupView,285,height:54)
        backupName.placeholderString = "Backup name"; field(backupName,backupView,250)
        button("Create Backup",backupView,330,210,202,"stopped") { [weak self] in self?.createBackup() }
        field(backups,backupView,160)
        button("Restore Selected…",backupView,20,115,202,"restore") { [weak self] in self?.restoreBackup() }
        button("Open Backups Folder",backupView,240,115,292,"local") { [weak self] in
            guard let self else { return }; let folder = WorldBackups(paths:self.paths).directory
            do { try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true); NSWorkspace.shared.open(folder) }
            catch { self.feedbackText = error.localizedDescription }
        }
        label("Restore requires a stopped server and creates a recovery backup first.",backupView,45,height:50)
        let time = tab("Time")
        timeStatus.frame = NSRect(x:20,y:405,width:512,height:60); time.addSubview(timeStatus)
        label("Time changes affect everyone and can advance world timers. They do not change your configured world modifiers.",time,326,height:60)
        button("Skip to Next Morning…",time,20,267,260,"live") { [weak self] in self?.command("worldMorning",confirm:"Skip to the next morning?",detail:"World time advances for everyone. Timers may advance too.") }
        advance.addItems(withTitles:["3 in-game hours","6 in-game hours","12 in-game hours"]); field(advance,time,200)
        button("Skip Ahead…",time,20,153,260,"live") { [weak self] in
            guard let self else { return }; let hours = [3,6,12][max(0,self.advance.indexOfSelectedItem)]
            self.command("worldAdvance \(hours * 60)",confirm:"Skip ahead \(hours) in-game hours?",detail:"This affects the entire world, including world timers.")
        }
        let raid = tab("Raids")
        raidStatus.frame = NSRect(x:20,y:400,width:512,height:65); raid.addSubview(raidStatus)
        button("Stop Current Raid…",raid,20,357,235,"live") { [weak self] in self?.command("worldRaidStop",confirm:"Stop the current raid?",detail:"The raid ends for everyone. Creatures already spawned remain in the world.") }
        label("Trigger a raid near a connected player. This can bypass normal progression and biome requirements. Choose carefully.",raid,287,height:60)
        field(raids,raid,250); field(players,raid,213)
        button("Start Selected Raid…",raid,20,171,235,"raid") { [weak self] in self?.startRaid() }
        pause.addItems(withTitles:["15 real minutes","30 real minutes","60 real minutes","120 real minutes"]); field(pause,raid,121)
        button("Pause New Raids…",raid,20,77,235,"pause") { [weak self] in
            guard let self else { return }; let amount = [15,30,60,120][max(0,self.pause.indexOfSelectedItem)]
            self.command("worldRaidPause \(amount)",confirm:"Pause new raids for \(amount) minutes?",detail:"An active raid continues. New raids resume automatically when time expires or the server restarts.")
        }
        button("Resume Raids…",raid,270,77,262,"pause") { [weak self] in self?.command("worldRaidResume",confirm:"Resume normal raids now?",detail:"This ends the temporary pause without changing your saved raid settings.") }
        do { settings = try WorldMessageSettings.load(paths:paths); welcome.stringValue = settings.welcome }
        catch { feedbackText = error.localizedDescription }
        updateButtons()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func saveWelcome() {
        var next = settings; next.welcome = welcome.stringValue
        do { try next.save(paths:paths); settings = next; feedbackText = "Welcome message saved. Existing players will not receive it again." }
        catch { feedbackText = error.localizedDescription }
    }
    private func confirm(_ title:String,_ detail:String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail; alert.addButton(withTitle:"Cancel"); alert.addButton(withTitle:"Continue")
        return alert.runModal() == .alertSecondButtonReturn
    }
    private func work(_ action: @escaping () throws -> String) {
        guard !changing, !busy() else { return }; changing = true; feedbackText = "Working…"; updateButtons()
        DispatchQueue.global(qos:.utility).async {
            let result: String
            do { result = try action() } catch { result = error.localizedDescription }
            DispatchQueue.main.async { self.changing = false; self.feedbackText = result; self.lastBackupCheck = .distantPast; self.updateButtons() }
        }
    }
    private func command(_ command:String,confirm title:String? = nil,detail:String = "") {
        if let title, !confirm(title,detail) { return }
        work { try ManagedServer(paths:self.paths).connection().send(command) }
    }
    private func broadcast() { let text = message.stringValue; work { try ManagedServer(paths:self.paths).broadcast(text); return "Message sent to everyone." } }
    private func createBackup() { let name = backupName.stringValue; work { let item = try WorldBackups(paths:self.paths).create(name:name); return "Backup created: " + item.name } }
    private func restoreBackup() {
        guard snapshots.indices.contains(backups.indexOfSelectedItem) else { return }
        let backup = snapshots[backups.indexOfSelectedItem]
        guard confirm("Restore \(backup.name)?","This replaces this server's saved world with the backup. A recovery copy of the current world is kept. The server stays stopped.") else { return }
        work { try WorldBackups(paths:self.paths).restore(id:backup.id); return "World restored. Recovery backup preserved; server remains stopped." }
    }
    static func raidDisplayName(_ id: String) -> String {
        let names = ["charredspawners": "Charred Spawners", "goblin": "Fulings", "goblins": "Fulings",
                     "goblinshaman": "Fuling Shamans", "goblinbrute": "Fuling Berserkers",
                     "foresttrolls": "Trolls", "forest": "Greydwarfs", "eikthyr": "Boars and Necks",
                     "bonemass": "Draugr and Skeletons", "moder": "Drakes", "gjall": "Gjall",
                     "skeletons": "Skeletons", "wolves": "Wolves", "bats": "Bats",
                     "blobs": "Blobs and Oozers", "serpents": "Serpents", "seekers": "Seekers"]
        let key = id.hasPrefix("army_") ? String(id.dropFirst(5)) : id
        if let name = names[key.lowercased()] { return name }
        return key.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
    }
    private func startRaid() {
        guard let raid = raids.selectedItem?.representedObject as? String, let player = players.selectedItem?.representedObject as? String else { return }
        guard confirm("Start \(Self.raidDisplayName(raid)) near \(players.titleOfSelectedItem ?? "player")?","This starts a raid for everyone nearby and may bypass normal world progression. It can damage structures or kill players.") else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject:["raid":raid,"player":player])
            command("worldRaidStart " + String(decoding:data,as:UTF8.self))
        } catch { feedbackText = error.localizedDescription }
    }
    private func updateButtons() {
        for (button,category) in buttons {
            let active = running && management && ready
            button.isEnabled = !changing && !busy() && (category == "local" || category == "message" && running && management || category == "live" && active || category == "stopped" && !running || category == "restore" && !running && !snapshots.isEmpty || category == "pause" && active && pauseAvailable || category == "raid" && active && players.numberOfItems > 0 && raids.numberOfItems > 0)
        }
    }
    func refresh(running:Bool,management:Bool) {
        self.running = running; self.management = management
        if !running || !management { ready = false; timeStatus.stringValue = "Start with management tools enabled to control world time."; raidStatus.stringValue = "Start with management tools enabled to control raids." }
        updateButtons()
        guard !polling, !changing else { return }; polling = true
        let checkBackups = Date().timeIntervalSince(lastBackupCheck) > 5
        if checkBackups { lastBackupCheck = Date() }
        DispatchQueue.global(qos:.utility).async {
            var reading: WorldReading?; var error: String?
            if running && management {
                do { reading = try JSONDecoder().decode(WorldReading.self,from:Data(ManagedServer(paths:self.paths).connection().send("worldInfo").utf8)) }
                catch let e { error = e.localizedDescription }
            }
            let snapshots = checkBackups ? try? WorldBackups(paths:self.paths).list() : nil
            DispatchQueue.main.async {
                self.polling = false
                if let snapshots {
                    let selected = self.snapshots.indices.contains(self.backups.indexOfSelectedItem) ? self.snapshots[self.backups.indexOfSelectedItem].id : nil
                    self.snapshots = snapshots; self.backups.removeAllItems()
                    let formatter = DateFormatter(); formatter.dateStyle = .short; formatter.timeStyle = .short
                    self.backups.addItems(withTitles:snapshots.map { $0.name + " · " + formatter.string(from:$0.date) })
                    if let index = snapshots.firstIndex(where:{$0.id == selected}) { self.backups.selectItem(at:index) }
                }
                self.ready = reading != nil
                if let reading {
                    let minutes = Int(reading.dayFraction * 1440)
                    self.timeStatus.stringValue = String(format:"Day %d · %02d:%02d",reading.day,minutes/60,minutes%60)
                    self.saveStatus.stringValue = (reading.saveInProgress ? "World save is in progress." : reading.lastSaveSecondsAgo.map { "Last completed save: \(Int(max(0,$0))/60)m ago." } ?? "No completed save reported this session.") + "\nStop the server before creating or restoring a named backup."
                    self.raidStatus.stringValue = "Active raid: " + (reading.raid.isEmpty ? "None" : Self.raidDisplayName(reading.raid)) + (reading.raidsPausedSeconds > 0 ? "\nNew raids paused for \(Int(ceil(reading.raidsPausedSeconds/60)))m." : "\nNormal raid scheduling enabled.")
                    self.pauseAvailable = reading.raidPauseAvailable
                    func fill(_ popup:NSPopUpButton,_ items:[(String,String)]) {
                        let selected = popup.selectedItem?.representedObject as? String
                        popup.removeAllItems()
                        for (title,id) in items { popup.addItem(withTitle:title); popup.lastItem?.representedObject = id }
                        if let index = items.firstIndex(where:{$0.1 == selected}) { popup.selectItem(at:index) }
                    }
                    fill(self.raids,reading.events.map { (Self.raidDisplayName($0),$0) }.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }); fill(self.players,reading.players.map { ($0.name + " · " + $0.id,$0.id) })
                } else {
                    if let error { self.timeStatus.stringValue = "World controls unavailable. Restart with updated management tools.\n" + error; self.raidStatus.stringValue = self.timeStatus.stringValue }
                    self.saveStatus.stringValue = "Stop the server before creating or restoring a named backup. Save World Now requires updated management tools."
                }
                self.updateButtons()
            }
        }
    }
}
private final class WorldActionButton: NSButton {
    let invoke: () -> Void
    init(title:String,action:@escaping () -> Void) { invoke = action; super.init(frame:.zero); self.title = title; bezelStyle = .rounded; target = self; self.action = #selector(clicked) }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func clicked() { invoke() }
}
