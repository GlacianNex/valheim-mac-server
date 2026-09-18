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
        print("PASS: real menu-bar button changes immediately through Stopping → Updating → Starting → player count, despite stale polled state.")
    }
}
