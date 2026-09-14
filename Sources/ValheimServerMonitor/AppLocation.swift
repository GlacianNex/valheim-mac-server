import AppKit
import ServerCore

enum AppLocation {
    static func prepare(completion: @escaping (Bool) -> Void) {
        guard !Paths().isDevelopment, Bundle.main.bundleURL.pathExtension == "app" else { completion(true); return }
        let current = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let destination = URL(fileURLWithPath: "/Applications/Valheim Server Monitor.app").resolvingSymlinksInPath().standardizedFileURL
        guard current != destination else { completion(true); return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = "Keep Valheim Server Monitor in Applications"
        alert.informativeText = "Background startup needs a stable app location. Copy this app to Applications before setup. Your downloaded copy and all server data are preserved."
        alert.addButton(withTitle: "Copy to Applications & Open"); alert.addButton(withTitle: "Quit")
        guard alert.runModal() == .alertFirstButtonReturn else { completion(false); return }
        do {
            try AppInstallation.copy(from: current, to: destination)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.allowsRunningApplicationSubstitution = false
            NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { application, error in
                DispatchQueue.main.async {
                    if let error { showError(error) }
                    else if application == nil { showError(MonitorError("The installed app did not open. Open it from Applications.")) }
                    completion(false)
                }
            }
        } catch {
            showError(error)
            completion(false)
        }
    }

    private static func showError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "Open the app using Finder"
        alert.informativeText = error.localizedDescription; alert.runModal()
    }
}
