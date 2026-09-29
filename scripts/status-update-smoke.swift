import AppKit
import ServerCore

@main struct StatusUpdateSmoke {
    static func main() {
        precondition(ProcessInfo.processInfo.environment["VSM_HOME"] != nil, "Test must use isolated storage")
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        if ProcessInfo.processInfo.environment["VSM_UI_PREVIEW_IMAGE"] != nil { app.appearance = NSAppearance(named:.aqua) }
        let delegate = AppDelegate()
        delegate.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(delegate.item) }
        // Simulate stale polled state throughout the operation. Progress must win immediately.
        delegate.displayed.state = "Stopping"; delegate.displayed.running = true
        for (phase, percent, expected) in [(ServerUpdateProgress.Phase.stopping, nil as Double?, "Stopping…"), (.installing, nil, "Updating…"), (.installing, 42, "Updating 42%"), (.starting, nil, "Starting…")] {
            delegate.serverUpdateProgress = ServerUpdateProgress(phase, message: "Progress detail", percent: percent)
            delegate.rebuild()
            precondition(delegate.item.button!.title == " Valheim · " + expected)
        }
        if ProcessInfo.processInfo.environment["VSM_TEST_EXPERIMENTAL"] == "1" {
            let future = Data(#"{"tag_name":"v999.0.0","draft":false,"prerelease":false,"assets":[]}"#.utf8)
            delegate.managerRelease = try! JSONDecoder().decode(ManagerRelease.self,from:future)
            delegate.rebuild()
            let heading = delegate.item.menu!.items[0]
            precondition(heading.title == "Valheim Manager · Experimental" && heading.action == nil && !heading.isEnabled)
            delegate.checkManagerVersion(force:true)
            precondition(!delegate.checkingManager && delegate.managerCheckDate == nil)
            delegate.managerVersionClicked()
            precondition(!delegate.installingManager)
            print("PASS: Experimental heading and no public update checks or installation, even with a newer release cached.")
        }
        delegate.serverUpdateProgress = nil
        delegate.displayed.state = "Online"; delegate.displayed.players = "2"
        delegate.rebuild()
        precondition(delegate.item.button!.title == " Valheim · 2")
        // A manual stop clears stale startup feedback without changing login preferences.
        delegate.startFeedback.begin()
        var staleStart = StartFeedback(); staleStart.begin()
        delegate.pendingStarts["stopped-test"] = staleStart
        delegate.displayed.state = "Stopped"; delegate.displayed.running = false
        delegate.displayed.autostart = true
        delegate.cancelStartupFeedback(for: "stopped-test")
        delegate.rebuild()
        precondition(!delegate.startFeedback.pending && delegate.pendingStarts["stopped-test"] == nil)
        precondition(delegate.displayed.autostart)
        precondition(!delegate.item.button!.title.contains("Starting"))
        delegate.displayed.state = "Online"; delegate.displayed.running = true
        var steamServer = ServerStatusPlaceholder()
        steamServer.selected = "steam-test"; steamServer.profileName = "Steam World"
        steamServer.crossplay = false; steamServer.port = 2466
        delegate.displayed.servers = [steamServer]; delegate.publicJoinIP = "203.0.113.10"
        delegate.rebuild()
        var join = delegate.item.menu!.items.first { $0.submenu != nil }!.submenu!.items[0]
        precondition(join.title == "Join address: 203.0.113.10:2466 · Copy" && join.isEnabled)
        precondition(join.toolTip!.contains("2466–2467"))
        delegate.publicJoinIP = nil; delegate.rebuild()
        join = delegate.item.menu!.items.first { $0.submenu != nil }!.submenu!.items[0]
        precondition(join.title == "Join address unavailable · Retry")
        steamServer.crossplay = true; steamServer.code = "123456"
        delegate.displayed.servers = [steamServer]; delegate.rebuild()
        join = delegate.item.menu!.items.first { $0.submenu != nil }!.submenu!.items[0]
        precondition(join.title == "Join code: 123456 · Copy")
        delegate.displayed.servers = []
        var saved: RestartSchedule?
        var schedule = RestartSchedule(); schedule.enabled = true
        let editor = RestartScheduleWindow(name:"Isolated Schedule Test",schedule:schedule) { saved = $0 }
        let buttons = editor.window.contentView!.subviews.compactMap { $0 as? NSButton }
        precondition(buttons.filter { ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"].contains($0.title) }.count == 7)
        let save = buttons.first { $0.title == "Save" }!
        save.performClick(nil)
        precondition(saved?.enabled == true && saved?.hour == 3)
        let store = try! Store()
        var profile = Profile(); profile.label = "Isolated UI Server"; profile.name = "UI Server"; profile.world = "UITest"; profile.password = "testing123"
        let id = try! store.save(profile)
        let paths = store.servicePaths(id)
        let info = ServerManagementWindow(paths:paths,name:"Isolated Management Test",settings:{},delete:{},serverAction:{ _ in })
        let logPane = LogTextScrollView(frame:NSRect(x:0,y:0,width:320,height:160))
        let rawLog = "First line " + String(repeating:"wrapped content ",count:30) + "\nSecond line\n"
        logPane.update(text:rawLog,wrap:true,follow:false)
        logPane.logText.setSelectedRange(NSRange(location:0,length:(rawLog as NSString).length))
        let copyBoard = NSPasteboard.withUniqueName()
        copyBoard.declareTypes(logPane.logText.writablePasteboardTypes,owner:nil)
        precondition(logPane.logText.writeSelection(to:copyBoard,types:logPane.logText.writablePasteboardTypes))
        precondition(copyBoard.string(forType:.string) == rawLog)
        logPane.update(text:rawLog,wrap:false,follow:false)
        precondition(logPane.logText.string == rawLog)
        precondition(logPane.logText.selectedRange().length == (rawLog as NSString).length)
        copyBoard.releaseGlobally()
        print("PASS: native log selection copies original lines without gutter numbers or visual wraps")
        let logPreview = ServerLogsWindow(paths:paths,name:"Isolated Test")
        logPreview.show()
        precondition(logPreview.window.isVisible)
        logPreview.window.close()
        precondition(!logPreview.window.isVisible)
        logPreview.show(); precondition(logPreview.window.isVisible); logPreview.window.close()
        print("PASS: integrated log viewer opens, closes and reopens in isolated storage")

        precondition(info.tabs.tabViewItems[2].view!.subviews.compactMap { $0 as? NSButton }.contains { $0.title == "Admins & Permitted Players…" })
        var preservedAccess:[String:Any] = [:]
        var accessForm = profile.form; accessForm["admins"] = "Steam_1"; accessForm["banned"] = "Steam_2"; accessForm["permitted"] = "Steam_3"
        let accessEditor = ProfileEditor(profile:accessForm) { preservedAccess = $0 }
        accessEditor.save(); accessEditor.window.close()
        precondition(preservedAccess["admins"] as? String == "Steam_1" && preservedAccess["banned"] as? String == "Steam_2" && preservedAccess["permitted"] as? String == "Steam_3")
        precondition(info.tabs.tabViewItems.map(\.label) == ["Performance", "Automation", "Moderation", "World Control", "Backups", "Mods"])
        info.tabs.selectTabViewItem(at:5)
        precondition(info.tabs.selectedTabViewItem?.label == "Mods")
        let modsView = info.tabs.tabViewItems[5].view!
        precondition(!modsView.subviews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Mods for this server" })
        precondition(modsView.subviews.compactMap { $0 as? NSButton }.contains { $0.title == "Open Mod Catalog" && $0.action == #selector(ServerManagementWindow.openModCatalog) })
        modsView.layoutSubtreeIfNeeded()
        precondition(info.modsList.view.frame.height > modsView.bounds.height * 0.75)
        info.showModCatalog(loadCatalogs:false)
        precondition(info.modCatalog?.window.title == "Mod Catalog")
        precondition(info.modCatalog?.library.directory.lastPathComponent == id)
        info.modCatalog?.window.close(); info.modCatalog = nil
        let settingsEditor = ProfileEditor(profile:profile.form) { _ in }
        precondition(settingsEditor.fields["admins"] == nil && settingsEditor.fields["banned"] == nil && settingsEditor.fields["permitted"] == nil)
        let limit = settingsEditor.fields["maxPlayers"] as! NSPopUpButton
        precondition(limit.titleOfSelectedItem == "Default (10 players)")
        settingsEditor.window.close()
        info.renderMods(management:false,networking:true)
        precondition(info.modsList.rows.first { $0.name == "Manager RCON" }?.enabled == false)
        precondition(info.modsList.rows.first { $0.name == "NetworkPerformanceSystem" }?.enabled == true)
        precondition(info.modsList.table.tableColumns.map(\.title) == ["","Status","Name","Version","Client"])
        precondition(info.modsList.table.tableColumns.allSatisfy { !$0.isEditable })
        precondition(info.modsList.rows.count == 4)
        for row in 0..<4 {
            for column in info.modsList.table.tableColumns {
                let container = info.modsList.tableView(info.modsList.table,viewFor:column,row:row) as! NSTableCellView
                if column.identifier.rawValue == "enabled" {
                    let checkbox = container.subviews.first as! NSButton
                    precondition(!checkbox.isEnabled)
                    continue
                }
                let cell = container.textField!
                precondition(cell.alignment == .center)
                precondition(container.constraints.contains { $0.firstAttribute == .centerY && $0.secondAttribute == .centerY })
                precondition(cell.textColor == .disabledControlTextColor)
                precondition(cell.toolTip?.contains("at the top of this window") == true)
                precondition(cell.toolTip?.contains("Controlled by") == true)
            }
        }
        let library = try! ModLibrary(paths:paths,profileID:id)
        let modFixture = paths.root.appendingPathComponent("selection-test")
        try! FileManager.default.createDirectory(at:modFixture,withIntermediateDirectories:true)
        try! Data("fixture".utf8).write(to:modFixture.appendingPathComponent("SelectionTest.dll"))
        let imported = try! library.prepareImport(modFixture).record
        try! library.add([imported])
        let runtime = ManagedServer(paths:paths).runtime
        info.modsList.appendInventory(try! library.inventory(runtime:runtime,running:false),live:nil)
        precondition(!info.modsList.tableView(info.modsList.table,shouldSelectRow:0))
        precondition(info.modsList.tableView(info.modsList.table,shouldSelectRow:4))
        info.modsList.table.selectRowIndexes(IndexSet(integer:4),byExtendingSelection:false)
        precondition(info.modsList.selectedMod?.modID == imported.id)
        let enabledColumn = info.modsList.table.tableColumns.first { $0.identifier.rawValue == "enabled" }!
        let enabledCell = info.modsList.tableView(info.modsList.table,viewFor:enabledColumn,row:4) as! NSTableCellView
        let checkbox = enabledCell.subviews.first as! NSButton
        precondition(checkbox.isEnabled && checkbox.state == .off)
        var toggledID:String?
        let originalToggle = info.modsList.toggle
        info.modsList.toggle = { toggledID = $0.modID }
        checkbox.performClick(nil)
        precondition(toggledID == imported.id)
        info.modsList.toggle = originalToggle
        try! library.select(imported.id,enabled:true)
        info.modsList.appendInventory(try! library.inventory(runtime:runtime,running:false),live:nil)
        precondition(info.modsList.selectedMod?.modID == imported.id)
        info.renderMods(management:false,networking:true)
        precondition(info.modsList.selectedMod?.modID == imported.id)
        precondition(!info.modsSummary.stringValue.contains("Network optimization"))
        info.tabs.selectTabViewItem(at:0)
        precondition(info.performanceTabs.tabViewItems.map(\.label) == ["Server", "Ping"])
        precondition(info.performanceTabs.toolTip == "Ping is only available with CrossPlay turned off")
        // Crossplay tab is visibly disabled and cannot be selected, even programmatically.
        info.setPingEnabled(false); info.performanceTabs.selectTabViewItem(info.pingTab)
        precondition(info.performanceTabs.selectedTabViewItem !== info.pingTab)
        info.setPingEnabled(true); info.performanceTabs.selectTabViewItem(info.pingTab)
        precondition(info.performanceTabs.selectedTabViewItem === info.pingTab)
        let pingRecorder = PerformanceRecorder()
        let pingNow = Date()
        func pingReading(_ values: [Double?], supported: Bool = true, uptime: Double = 100) -> ManagementReading {
            ManagementReading(version:"test",players:values.count,fps:30,managedMemoryBytes:100,uptimeSeconds:uptime,
                onlinePlayers:values.enumerated().map { OnlinePlayer(name:"Same name",id:"Steam_\($0.offset)",pingMs:$0.element) },banned:[],pingSupported:supported)
        }
        pingRecorder.record(pingReading([45,120]),for:id,now:pingNow.addingTimeInterval(-1200))
        pingRecorder.record(pingReading([nil,0]),for:id,now:pingNow.addingTimeInterval(-2))
        pingRecorder.record(nil,for:id,now:pingNow.addingTimeInterval(-1))
        pingRecorder.record(pingReading([50,125]),for:id,now:pingNow)
        let pingHistory = pingRecorder.history(for:id,now:pingNow)
        precondition(pingHistory.first!.pings["Steam_0"] == 45)
        precondition(pingHistory[1].pings["Steam_0"] == nil && pingHistory[1].pings["Steam_1"] == 0)
        precondition(pingHistory[2].pings.isEmpty)
        info.pingGraphs.update(reading:pingReading([50,125]),samples:pingHistory)
        if let path = ProcessInfo.processInfo.environment["VSM_PING_SCREENSHOT"] {
            let demo = (0...3600).map { second in
                LiveMetricSample(time:pingNow.addingTimeInterval(Double(second-3600)),fps:nil,memory:nil,
                    pings:["Steam_0":45+sin(Double(second)/80)*9,"Steam_1":120+sin(Double(second)/90)*20])
            }
            info.pingGraphs.update(reading:pingReading([50,125]),samples:demo)
            let view = info.window.contentView!; view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds)!
            view.cacheDisplay(in:view.bounds,to:bitmap)
            try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))
            info.pingGraphs.update(reading:pingReading([50,125]),samples:pingHistory)
        }
        precondition(info.pingGraphs.charts.count == 2) // Same names remain distinct by platform ID.
        precondition(info.pingGraphs.charts["Steam_0"]!.points.first!.1 == 45)
        pingRecorder.record(pingReading([99],supported:false),for:id,now:pingNow.addingTimeInterval(1))
        precondition(pingRecorder.history(for:id,now:pingNow.addingTimeInterval(1)).last!.pings.isEmpty)
        let legacy = Data(#"{"version":"old","players":1,"fps":30,"managedMemoryBytes":100,"uptimeSeconds":1,"onlinePlayers":[{"name":"Old","id":"Steam_old"}]}"#.utf8)
        let legacyReading = try! JSONDecoder().decode(ManagementReading.self,from:legacy)
        precondition(legacyReading.pingSupported == nil && legacyReading.onlinePlayers!.first!.pingMs == nil)
        info.pingGraphs.update(reading:legacyReading,samples:pingHistory)
        precondition(info.pingGraphs.charts.isEmpty)
        info.setPingEnabled(false); precondition(info.performanceTabs.selectedTabViewItem !== info.pingTab)
        print("PASS: Steam ping tab gating, per-ID charts, unavailable gaps, real zero, background history, crossplay exclusion, and older plugin decoding.")
        let automation = info.tabs.tabViewItems[1].view!
        func wait(_ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(5)
            while !condition() && Date() < deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.01)) }
            precondition(condition(), "Timed out waiting for management UI")
        }
        delegate.managerCheckDate = Date()
        delegate.displayed.automaticServerUpdates = false; delegate.rebuild()
        var toggle = delegate.item.menu!.items.first { $0.title == "Automatically Update All Valheim Servers" }!
        precondition(app.sendAction(toggle.action!,to:toggle.target,from:toggle)); precondition(toggle.state == .on)
        wait { !delegate.busy }; precondition((try! store.load()).automaticServerUpdates == true)
        toggle = delegate.item.menu!.items.first { $0.title == "Automatically Update All Valheim Servers" }!
        precondition(app.sendAction(toggle.action!,to:toggle.target,from:toggle)); precondition(toggle.state == .off)
        wait { !delegate.busy }; precondition((try! store.load()).automaticServerUpdates == false)
        precondition(toggle.toolTip!.contains("official Valheim dedicated server") && toggle.toolTip!.contains("\n\n"))
        precondition(!automation.subviews.compactMap { $0 as? NSButton }.contains { $0.title.contains("Update") })
        precondition(info.summary.superview === info.window.contentView)
        precondition(info.summary.frame.minY > info.tabs.frame.maxY)
        let lightPaths = Paths(root: paths.root.appendingPathComponent("first-start-ui"), profileID: UUID().uuidString)
        try! lightPaths.prepare()
        let lights = ServerManagementWindow(paths: lightPaths, name: "Status indicators")
        var lightStatus = ServerStatus()
        lights.renderServerStatus(lightStatus, reading: nil)
        precondition(lights.statusLight.textColor == .secondaryLabelColor && lights.firstStartHint.isHidden)
        lightStatus.state = "Starting"
        lights.renderServerStatus(lightStatus, reading: nil)
        precondition(lights.statusLight.textColor == .systemOrange && !lights.firstStartHint.isHidden)
        lightStatus.state = "Online"
        lights.renderServerStatus(lightStatus, reading: nil)
        precondition(lights.statusLight.textColor == .systemGreen && lights.firstStartHint.isHidden)
        try! Data("first-session".utf8).write(to: lightPaths.stateRoot.appendingPathComponent("first-start-log"))
        try! Data("second-session".utf8).write(to: lightPaths.file("latest-log"))
        lightStatus.state = "Starting"
        lights.renderServerStatus(lightStatus, reading: nil)
        precondition(lights.firstStartHint.isHidden)
        lights.window.close()
        print("PASS: status colors and first-start-only guidance")
        var actionBusy = false
        var requestedActions: [String] = []
        let actionWindow = ServerManagementWindow(paths:paths,name:"Lifecycle controls",isBusy:{actionBusy},serverAction:{ requestedActions.append($0); actionBusy = true })
        var stopped = ServerStatus(); stopped.installed = true
        actionWindow.renderServerStatus(stopped,reading:nil)
        precondition(actionWindow.startStopButton.title == "Start Server" && actionWindow.startStopButton.isEnabled)
        actionWindow.startStopButton.performClick(nil)
        precondition(requestedActions == ["start"] && !actionWindow.startStopButton.isEnabled && actionWindow.summary.stringValue.contains("Starting"))
        actionWindow.window.close()
        actionBusy = false
        let stopWindow = ServerManagementWindow(paths:paths,name:"Stop control",isBusy:{actionBusy},serverAction:{ requestedActions.append($0); actionBusy = true })
        var online = stopped; online.running = true; online.state = "Online"; online.players = "2"
        stopWindow.renderServerStatus(online,reading:nil)
        precondition(stopWindow.startStopButton.title == "Stop Server" && stopWindow.startStopButton.isEnabled)
        stopWindow.startStopButton.performClick(nil)
        precondition(requestedActions == ["start","stop"] && stopWindow.summary.stringValue.contains("Stopping"))
        stopWindow.window.close()
        let modLabels = info.window.contentView!.subviews.compactMap { $0 as? NSTextField }.map { $0.stringValue }
        precondition(modLabels.contains("BepInEx, RCON, Jötunn") && modLabels.contains("NetworkPerformanceSystem"))
        let overview = info.performanceTabs.tabViewItems[0].view!
        precondition(!overview.subviews.compactMap { $0 as? NSButton }.contains { $0.title == "Server Management Mods" })
        let tools = info.window.contentView!.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Server Management Mods" }!
        let networking = info.window.contentView!.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Network Optimization Mods" }!
        precondition(tools.frame.minY > info.tabs.frame.maxY && networking.frame.minY > info.tabs.frame.maxY)
        let footer = info.window.contentView!.subviews.compactMap { $0 as? NSButton }.filter { ["World Settings","Open Log","Logs Folder","Server Folder","Delete Server…"].contains($0.title) }
        precondition(footer.count == 5)
        precondition(footer.allSatisfy { $0.frame.minY == info.startStopButton.frame.minY })
        wait { tools.isEnabled }; precondition(tools.state == .on)
        tools.performClick(nil); wait { tools.isEnabled }
        precondition((try! store.load()).managedServers?[id] == false)
        networking.performClick(nil); wait { networking.isEnabled }
        precondition((try! store.load()).networkOptimizations?[id] == true)
        precondition((try! store.load()).managedServers?[id] == false)
        networking.performClick(nil); wait { networking.isEnabled }
        precondition((try! store.load()).networkOptimizations?[id] == false)
        tools.performClick(nil); wait { tools.isEnabled }
        precondition((try! store.load()).managedServers?[id] == true)
        let scheduleView = automation.subviews.first { !($0 is NSControl) }!
        let scheduleButtons = scheduleView.subviews.compactMap { $0 as? NSButton }
        scheduleButtons.first { $0.title == "Scheduled restart" }!.performClick(nil)
        scheduleButtons.first { $0.title == "Save" }!.performClick(nil)
        precondition((try! store.load()).restartSchedules?[id]?.enabled == true)
        precondition(info.window.isVisible, "Saving the embedded schedule must keep management open")
        let players = info.tabs.tabViewItems[2].view!
        precondition(players.subviews.compactMap { $0 as? NSButton }.filter { ["Kick","Ban","Unban"].contains($0.title) }.allSatisfy { !$0.isEnabled })
        let fixture = ManagementReading(version:"test",players:2,fps:30,managedMemoryBytes:1048576,uptimeSeconds:120,
            onlinePlayers:[OnlinePlayer(name:"Same name",id:"Steam_1"),OnlinePlayer(name:"Same name",id:"Steam_2")],banned:["Steam_3"])
        let recorder = PerformanceRecorder(read: { _ in fixture })
        let historyEnd = Date()
        for second in 0...4800 { recorder.record(fixture,for:id,now:historyEnd.addingTimeInterval(Double(second-4800))) }
        precondition(recorder.history(for:id,now:historyEnd).count == 3601)
        precondition(recorder.history(for:"different-server",now:historyEnd).isEmpty)
        precondition(recorder.latest(for:id,now:historyEnd.addingTimeInterval(4)) == nil)
        let historyWindow = ServerManagementWindow(paths:paths,name:"History test",recorder:recorder)
        let historyCharts = historyWindow.performanceTabs.tabViewItems[0].view!.subviews.compactMap { $0 as? LiveMetricChart }
        precondition(historyCharts.count == 2 && historyCharts[0].points.contains { $0.0 == historyEnd.addingTimeInterval(-1200) })
        historyWindow.window.close()
        recorder.start(paths:paths)
        wait { recorder.history(for:id).last!.time > historyEnd }
        let firstPoll = recorder.history(for:id).last!.time
        wait { recorder.history(for:id).last!.time > firstPoll }
        recorder.stop()
        let reopened = ServerManagementWindow(paths:paths,name:"Reopened history",recorder:recorder)
        let reopenedChart = reopened.performanceTabs.tabViewItems[0].view!.subviews.compactMap { $0 as? LiveMetricChart }.first!
        precondition(reopenedChart.points.contains { $0.0 == historyEnd.addingTimeInterval(-1200) })
        reopened.window.close()
        let restarted = ManagementReading(version:"test",players:0,fps:30,managedMemoryBytes:100,uptimeSeconds:1,onlinePlayers:[],banned:[])
        recorder.record(restarted,for:id)
        precondition(recorder.history(for:id).dropLast().last!.fps == nil)
        print("PASS: one-hour retention, independent background sampling with closed windows, reopening history, stale readings and restart gaps.")
        info.apply(fixture)
        let lists = players.subviews.compactMap { $0 as? NSScrollView }.compactMap { $0.documentView as? NSTableView }
        precondition(lists[0].numberOfRows == 2 && lists[1].numberOfRows == 1)
        lists[0].selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        precondition(players.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Ban" }!.isEnabled)
        lists[1].selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        precondition(players.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Unban" }!.isEnabled)
        precondition(lists[0].tableColumns.map { $0.title } == ["Player", "Platform ID"])
        precondition(info.performanceTabs.tabViewItems[0].view!.subviews.compactMap { $0 as? LiveMetricChart }.count == 2)
        precondition(info.worldControl.tabs.tabViewItems.map(\.label) == ["Messages", "Time", "Raids"])
        precondition(WorldControlView.raidDisplayName("army_charredspawners") == "Charred Spawners")
        precondition(WorldControlView.raidDisplayName("army_new_enemy") == "New Enemy")
        let timeOptions = info.worldControl.tabs.tabViewItems[1].view!.subviews.compactMap { $0 as? NSPopUpButton }.first!
        precondition(timeOptions.itemTitles == ["3 in-game hours", "6 in-game hours", "12 in-game hours"])
        info.setManagementEnabled(true)
        info.tabs.selectTabViewItem(info.worldTab)
        precondition(info.tabs.selectedTabViewItem === info.worldTab)
        info.setManagementEnabled(false)
        precondition(info.tabs.selectedTabViewItem !== info.worldTab)
        info.tabs.selectTabViewItem(at:4)
        precondition(info.tabs.selectedTabViewItem?.label == "Backups")
        info.tabs.selectTabViewItem(info.moderationTab)
        precondition(info.tabs.selectedTabViewItem !== info.moderationTab)
        info.tabs.selectTabViewItem(info.worldTab)
        precondition(info.tabs.selectedTabViewItem !== info.worldTab)
        info.tabs.selectTabViewItem(at:1)
        precondition(info.tabs.selectedTabViewItem?.label == "Automation")
        info.setManagementEnabled(true)
        info.tabs.selectTabViewItem(info.moderationTab)
        precondition(info.tabs.selectedTabViewItem === info.moderationTab)
        let messages = info.worldControl.tabs.tabViewItems[0].view!
        info.worldControl.refresh(running:true,management:true)
        precondition(messages.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Send to Everyone" }!.isEnabled)
        info.apply(nil,fallbackBans:"Steam_3")
        info.worldControl.refresh(running:false,management:false)
        precondition(!messages.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Send to Everyone" }!.isEnabled)
        precondition(lists[0].numberOfRows == 0 && lists[1].numberOfRows == 1)
        precondition(players.subviews.compactMap { $0 as? NSButton }.filter { ["Kick","Ban","Unban"].contains($0.title) }.allSatisfy { !$0.isEnabled })
        delegate.displayed = try! JSONDecoder().decode(ServerStatusPlaceholder.self,from:Data(delegate.engine.execute("status").utf8))
        delegate.rebuild()
        precondition(!delegate.item.menu!.items.contains { $0.title == "Refresh Status" })
        let submenu = delegate.item.menu!.items.first { $0.submenu != nil }!.submenu!
        precondition(submenu.items.map(\.title).filter { !$0.isEmpty } == ["Join code: unavailable", "Start Server", "Stop Server (Save & Stop)", "Start Server at Login", "Server Management…"])
        let loginItem = submenu.items.first { $0.title == "Start Server at Login" }!
        precondition(loginItem.representedObject as? String == id && loginItem.action == #selector(AppDelegate.profileAutostart(_:)))
        let loginCheckbox = automation.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Start this server at login" }!
        // Change the shared preference in isolated storage; verify both UI surfaces follow it.
        for enabled in [true,false] {
            try! store.update { $0.profileAutostart?[id] = enabled }
            delegate.displayed = try! JSONDecoder().decode(ServerStatusPlaceholder.self,from:Data(delegate.engine.execute("status").utf8))
            delegate.rebuild()
            let updated = delegate.item.menu!.items.first { $0.submenu != nil }!.submenu!.items.first { $0.title == "Start Server at Login" }!
            precondition(updated.state == (enabled ? .on : .off))
            wait { loginCheckbox.state == (enabled ? .on : .off) }
        }
        print("PASS: per-server login submenu and management checkbox reflect the same saved preference.")
        if ProcessInfo.processInfo.environment["VSM_UI_PREVIEW"] == "1" {
            info.tabs.selectTabViewItem(at:0)
            info.performanceTabs.selectTabViewItem(at:0)
            info.window.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until:Date().addingTimeInterval(2))
            if let output = ProcessInfo.processInfo.environment["VSM_UI_PREVIEW_IMAGE"], let view = info.window.contentView,
               let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) {
                view.cacheDisplay(in:view.bounds,to:bitmap)
                try! bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:output))
            } else {
                let duration = min(60,max(1,Double(ProcessInfo.processInfo.environment["VSM_UI_PREVIEW_SECONDS"] ?? "60") ?? 60))
                let closeObserver = NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:info.window,queue:.main) { _ in app.terminate(nil) }
                _ = Timer.scheduledTimer(withTimeInterval:duration,repeats:false) { _ in
                    print("PASS: preview finished; terminating isolated manager.")
                    app.terminate(nil)
                }
                defer { NotificationCenter.default.removeObserver(closeObserver) }
                app.run()
            }
        }
        info.window.close()
        print("PASS: unified management tabs, immediate persistent auto-update toggle, tools on/off, embedded schedule save, disabled offline moderation, and compact submenu.")
        print("PASS: scheduled restart window opens, saves values and closes; performance/moderation window opens without crashing.")
        print("PASS: real menu-bar button changes immediately through Stopping → Updating → Starting → player count, despite stale polled state.")
    }
}
