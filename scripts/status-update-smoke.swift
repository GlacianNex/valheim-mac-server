import AppKit
import ServerCore

@main struct StatusUpdateSmoke {
    static func main() {
        precondition(ProcessInfo.processInfo.environment["VSM_HOME"] != nil, "Test must use isolated storage")
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
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
        delegate.serverUpdateProgress = nil
        delegate.displayed.state = "Online"; delegate.displayed.players = "2"
        delegate.rebuild()
        precondition(delegate.item.button!.title == " Valheim · 2")
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
        let info = ServerManagementWindow(paths:paths,name:"Isolated Management Test")
        precondition(info.tabs.tabViewItems.map(\.label) == ["Performance & Tools", "Automation", "Players & Moderation", "Messages"])
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
        let overview = info.tabs.tabViewItems[0].view!
        let tools = overview.subviews.compactMap { $0 as? NSButton }.first!
        wait { tools.isEnabled }; precondition(tools.state == .on)
        tools.performClick(nil); wait { tools.isEnabled }
        precondition((try! store.load()).managedServers?[id] == false)
        tools.performClick(nil); wait { tools.isEnabled }
        precondition((try! store.load()).managedServers?[id] == true)
        let scheduleView = automation.subviews.first { !($0 is NSControl) }!
        let scheduleButtons = scheduleView.subviews.compactMap { $0 as? NSButton }
        scheduleButtons.first { $0.title == "Scheduled restart" }!.performClick(nil)
        scheduleButtons.first { $0.title == "Save" }!.performClick(nil)
        precondition((try! store.load()).restartSchedules?[id]?.enabled == true)
        precondition(info.window.isVisible, "Saving the embedded schedule must keep management open")
        let players = info.tabs.tabViewItems[2].view!
        precondition(players.subviews.compactMap { $0 as? NSButton }.allSatisfy { !$0.isEnabled })
        let fixture = ManagementReading(version:"test",players:2,fps:30,managedMemoryBytes:1048576,uptimeSeconds:120,
            onlinePlayers:[OnlinePlayer(name:"Same name",id:"Steam_1"),OnlinePlayer(name:"Same name",id:"Steam_2")],banned:["Steam_3"])
        let recorder = PerformanceRecorder(read: { _ in fixture })
        let historyEnd = Date()
        for second in 0...4800 { recorder.record(fixture,for:id,now:historyEnd.addingTimeInterval(Double(second-4800))) }
        precondition(recorder.history(for:id,now:historyEnd).count == 3601)
        precondition(recorder.history(for:"different-server",now:historyEnd).isEmpty)
        precondition(recorder.latest(for:id,now:historyEnd.addingTimeInterval(4)) == nil)
        let historyWindow = ServerManagementWindow(paths:paths,name:"History test",recorder:recorder)
        let historyCharts = historyWindow.tabs.tabViewItems[0].view!.subviews.compactMap { $0 as? LiveMetricChart }
        precondition(historyCharts.count == 2 && historyCharts[0].points.contains { $0.0 == historyEnd.addingTimeInterval(-1200) })
        historyWindow.window.close()
        recorder.start(paths:paths)
        wait { recorder.history(for:id).last!.time > historyEnd }
        let firstPoll = recorder.history(for:id).last!.time
        wait { recorder.history(for:id).last!.time > firstPoll }
        recorder.stop()
        let reopened = ServerManagementWindow(paths:paths,name:"Reopened history",recorder:recorder)
        let reopenedChart = reopened.tabs.tabViewItems[0].view!.subviews.compactMap { $0 as? LiveMetricChart }.first!
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
        precondition(info.tabs.tabViewItems[0].view!.subviews.compactMap { $0 as? LiveMetricChart }.count == 2)
        let messages = info.tabs.tabViewItems[3].view!
        precondition(messages.subviews.compactMap { $0 as? NSButton }.first!.isEnabled)
        info.apply(nil,fallbackBans:"Steam_3")
        precondition(!messages.subviews.compactMap { $0 as? NSButton }.first!.isEnabled)
        precondition(lists[0].numberOfRows == 0 && lists[1].numberOfRows == 1)
        precondition(players.subviews.compactMap { $0 as? NSButton }.allSatisfy { !$0.isEnabled })
        delegate.displayed = try! JSONDecoder().decode(ServerStatusPlaceholder.self,from:Data(delegate.engine.execute("status").utf8))
        delegate.rebuild()
        precondition(!delegate.item.menu!.items.contains { $0.title == "Refresh Status" })
        let submenu = delegate.item.menu!.items.first { $0.submenu != nil }!.submenu!
        precondition(submenu.items.map(\.title).filter { !$0.isEmpty } == ["Join code: unavailable", "Start Server", "Stop Server (Save & Stop)", "Server Management…"])
        if ProcessInfo.processInfo.environment["VSM_UI_PREVIEW"] == "1" {
            info.tabs.selectTabViewItem(at:1)
            RunLoop.current.run(until:Date().addingTimeInterval(60))
        }
        info.window.close()
        print("PASS: unified management tabs, immediate persistent auto-update toggle, tools on/off, embedded schedule save, disabled offline moderation, and compact submenu.")
        print("PASS: scheduled restart window opens, saves values and closes; performance/moderation window opens without crashing.")
        print("PASS: real menu-bar button changes immediately through Stopping → Updating → Starting → player count, despite stale polled state.")
    }
}
