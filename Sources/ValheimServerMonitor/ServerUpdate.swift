import AppKit
import ServerCore

final class ServerUpdateWindow {
    let window: NSWindow
    private let status = NSTextField(wrappingLabelWithString: "Preparing the server update…")
    private let progress = NSProgressIndicator()
    private var timer: Timer?
    private var downloading = false

    init(engine: Engine, completion: @escaping () -> Void) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Updating Valheim Server"; window.isReleasedWhenClosed = false
        status.frame = NSRect(x: 24, y: 68, width: 472, height: 55)
        progress.frame = NSRect(x: 24, y: 35, width: 472, height: 20)
        progress.style = .bar; progress.isIndeterminate = true; progress.startAnimation(nil)
        window.contentView?.addSubview(status); window.contentView?.addSubview(progress)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        let log = engine.paths.logs.appendingPathComponent("installation.log")
        let poll = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.downloading, let update = InstallationProgress.latest(in: tail(log, bytes: 8000)) else { return }
            self.status.stringValue = update.message
            self.progress.isIndeterminate = update.percent == nil
            if let percent = update.percent { self.progress.doubleValue = percent } else { self.progress.startAnimation(nil) }
        }
        timer = poll; RunLoop.main.add(poll, forMode: .common)
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            do {
                let lifecycle = Lifecycle(paths: engine.paths)
                let restart = lifecycle.isActive
                let profileID = try Store(paths: engine.paths).load().selected
                if restart {
                    DispatchQueue.main.async { self.status.stringValue = "Saving the world and stopping the server…" }
                    try lifecycle.requestStop()
                }
                DispatchQueue.main.async { self.status.stringValue = "Downloading the server update…"; self.downloading = true }
                try Installer(paths: engine.paths).install()
                DispatchQueue.main.async { self.downloading = false; self.status.stringValue = "Finishing the update…" }
                if restart {
                    guard try Store(paths: engine.paths).load().selected == profileID else {
                        throw MonitorError("The server was updated, but the selected profile changed. Start your preferred world from the menu.")
                    }
                    DispatchQueue.main.async { self.status.stringValue = "Starting the updated server…" }
                    try LoginItems(paths: engine.paths).start()
                }
            } catch {
                failure = error.localizedDescription
            }
            DispatchQueue.main.async {
                self.timer?.invalidate(); self.timer = nil; self.window.close()
                if let failure {
                    let alert = NSAlert(); alert.messageText = "Server update needs attention"
                    alert.informativeText = failure + "\nYour world files have not been replaced. Check server status before starting it again."
                    alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Open Update Log")
                    if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(log) }
                }
                completion()
            }
        }
    }
}
