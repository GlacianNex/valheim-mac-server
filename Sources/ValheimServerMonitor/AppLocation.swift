import AppKit
import ServerCore

enum AppLocation {
    static func prepare() -> Bool {
        guard !Paths().isDevelopment, Bundle.main.bundleURL.pathExtension == "app" else { return true }
        let current = Bundle.main.bundleURL.standardizedFileURL
        let destination = URL(fileURLWithPath: "/Applications/Valheim Server Monitor.app")
        guard current != destination else { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "Keep Valheim Server Monitor in Applications"
        alert.informativeText = "Background startup needs a stable app location. Copy this app to Applications before setup. Your downloaded copy and all server data are preserved."
        alert.addButton(withTitle: "Copy to Applications & Open"); alert.addButton(withTitle: "Quit")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        do {
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw MonitorError("Valheim Server Monitor is already in Applications. Open that copy, or replace it in Finder to update the app. Server data is stored separately.")
            }
            try FileManager.default.copyItem(at: current, to: destination)
            NSWorkspace.shared.openApplication(at: destination, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        } catch {
            let errorAlert = NSAlert(); errorAlert.messageText = "Move the app using Finder"; errorAlert.informativeText = error.localizedDescription; errorAlert.runModal()
        }
        return false
    }
}
