import AppKit
import ServerCore

enum AppLocation {
    static func prepare(completion: @escaping (Bool) -> Void) {
        guard !Paths().isDevelopment, Bundle.main.bundleURL.pathExtension == "app" else { completion(true); return }
        let current = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        // Existing launch agents refer to this path. Keep it stable for upgraded installs.
        let legacy = URL(fileURLWithPath: "/Applications/Valheim Server Monitor.app")
        let preferred = URL(fileURLWithPath: "/Applications/Valhiem Server Manager for Mac.app")
        let destination = (FileManager.default.fileExists(atPath: legacy.path) && !FileManager.default.fileExists(atPath: preferred.path) ? legacy : preferred).resolvingSymlinksInPath().standardizedFileURL
        guard current != destination else { completion(true); return }
        let paths = Paths()
        let updating = FileManager.default.fileExists(atPath: destination.path)
        var versionSummary = ""
        do {
            if updating {
                let incoming = try AppInstallation.version(at: current)
                let installed = try AppInstallation.version(at: destination)
                versionSummary = "Update version \(installed) to \(incoming). "
                guard incoming.compare(installed, options: .numeric) == .orderedDescending else {
                    showError(MonitorError("Version \(installed) is already installed. Open it from Applications. This download does not contain a newer version."))
                    completion(false); return
                }
            }
            try paths.prepare()
        } catch { showError(error); completion(false); return }
        let running = Lifecycle(paths: paths).isActive
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = updating ? "Update Valhiem Server Manager for Mac?" : "Keep Valhiem Server Manager for Mac in Applications"
        alert.informativeText = updating
            ? versionSummary + "Profiles, worlds, settings, and login preferences are preserved. The old manager will close."
            : "Background startup needs a stable app location. Copy this app to Applications before setup. Your downloaded copy and all server data are preserved."
        if running { alert.informativeText += " The server must save and stop first. Players will disconnect; start the server again after the update." }
        alert.addButton(withTitle: running ? "Save, Stop & Update" : (updating ? "Update & Open" : "Copy to Applications & Open"))
        alert.addButton(withTitle: "Quit")
        guard alert.runModal() == .alertFirstButtonReturn else { completion(false); return }
        let progressWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        progressWindow.title = updating ? "Updating Valhiem Server Manager for Mac" : "Installing Valhiem Server Manager for Mac"
        progressWindow.isReleasedWhenClosed = false
        let progressText = NSTextField(wrappingLabelWithString: running ? "Saving and stopping the server, then updating… This can take up to two minutes." : "Preparing the app and opening it from Applications…")
        progressText.frame = NSRect(x: 20, y: 28, width: 400, height: 50)
        progressWindow.contentView?.addSubview(progressText)
        progressWindow.center(); progressWindow.makeKeyAndOrderFront(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            var backup: URL?
            do {
                // Serialize updates, then hold the server lock through the replacement.
                try withLock(paths.file("app-update.lock")) {
                    let lifecycle = Lifecycle(paths: paths)
                    if running { try lifecycle.requestStop() }
                    let fd = open(paths.file("service.lock").path, O_CREAT | O_RDWR, 0o600)
                    guard fd >= 0 else { throw MonitorError("Could not check the server. Please retry the update.") }
                    defer { close(fd) }
                    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                        throw MonitorError("The server or its installer is still running. Wait for it to finish, then open this download again.")
                    }
                    defer { flock(fd, LOCK_UN) }
                    if let record = lifecycle.record, lifecycle.owns(record) {
                        throw MonitorError("The server is still running. Save and stop it before updating.")
                    }
                    if updating {
                        backup = try AppInstallation.update(from: current, to: destination) {
                            try closeInstalledMonitor(at: destination)
                        }
                    } else { try AppInstallation.copy(from: current, to: destination) }
                }
                let savedBackup = backup
                DispatchQueue.main.async {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.createsNewApplicationInstance = true
                    configuration.allowsRunningApplicationSubstitution = false
                    NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { application, error in
                        DispatchQueue.main.async {
                            progressWindow.close()
                            if let error { showError(error, backup: savedBackup) }
                            else if application == nil { showError(MonitorError("The installed app did not open. Open it from Applications."), backup: savedBackup) }
                            else if let savedBackup { try? FileManager.default.removeItem(at: savedBackup) }
                            completion(false)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async { progressWindow.close(); showError(error, backup: backup); completion(false) }
            }
        }
    }

    private static func closeInstalledMonitor(at destination: URL) throws {
        var applications: [NSRunningApplication] = []
        DispatchQueue.main.sync {
            applications = NSRunningApplication.runningApplications(withBundleIdentifier: AppInstallation.bundleIdentifier)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        }
        // Only request a normal quit for this exact installed app. Never force-kill it.
        for application in applications {
            guard application.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == destination else {
                throw MonitorError("Quit other copies of Valhiem Server Manager for Mac, then open this download again.")
            }
            var accepted = false
            DispatchQueue.main.sync { accepted = application.terminate() }
            guard accepted else { throw MonitorError("Quit the installed manager, then try the update again.") }
        }
        let deadline = Date().addingTimeInterval(10)
        while applications.contains(where: { !$0.isTerminated }), Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        guard applications.allSatisfy({ $0.isTerminated }) else {
            throw MonitorError("The installed manager has not closed yet. Quit it and try again.")
        }
    }

    private static func showError(_ error: Error, backup: URL? = nil) {
        let alert = NSAlert(); alert.messageText = "Open the app using Finder"
        alert.informativeText = error.localizedDescription
        if let backup { alert.informativeText += " Your previous app is preserved at " + backup.appendingPathComponent("Previous.app").path }
        alert.runModal()
    }
}
