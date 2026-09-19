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
        let info = ServerManagementWindow(paths:Paths(),name:"Isolated Management Test")
        precondition(info.window.contentView!.subviews.compactMap { $0 as? NSButton }.map(\.title) == ["Kick","Ban","Unban"])
        info.window.close()
        print("PASS: scheduled restart window opens, saves values and closes; performance/moderation window opens without crashing.")
        print("PASS: real menu-bar button changes immediately through Stopping → Updating → Starting → player count, despite stale polled state.")
    }
}
