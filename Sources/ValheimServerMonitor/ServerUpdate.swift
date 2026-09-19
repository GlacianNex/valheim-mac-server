import AppKit
import ServerCore

final class ServerUpdateWindow {
    let window: NSWindow
    private let status = NSTextField(wrappingLabelWithString: "Preparing the server update…")
    private let progress = NSProgressIndicator()
    private var timer: Timer?
    private var downloading = false

    private var current = ServerUpdateProgress(.preparing, message: "Preparing the server update…")
    private var stageStarted = Date()
    private let onProgress: (ServerUpdateProgress) -> Void
    private func report(_ value: ServerUpdateProgress) {
        if value.phase != current.phase { stageStarted = Date() }
        current = value
        let elapsed = Int(Date().timeIntervalSince(stageStarted))
        status.stringValue = value.message + (elapsed >= 5 ? "\nThis stage: \(elapsed)s" : "")
        progress.isIndeterminate = value.percent == nil
        if let percent = value.percent { progress.doubleValue = percent } else { progress.startAnimation(nil) }
        onProgress(value)
    }
    init(engine: Engine, automaticBuild: String? = nil, onProgress: @escaping (ServerUpdateProgress) -> Void, completion: @escaping () -> Void) {
        self.onProgress = onProgress
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Updating Valheim Server"; window.isReleasedWhenClosed = false
        status.frame = NSRect(x: 24, y: 68, width: 472, height: 55)
        progress.frame = NSRect(x: 24, y: 35, width: 472, height: 20)
        progress.style = .bar; progress.isIndeterminate = true; progress.startAnimation(nil)
        window.contentView?.addSubview(status); window.contentView?.addSubview(progress)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        let log = engine.paths.logs.appendingPathComponent("installation.log")
        let poll = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.downloading, let update = InstallationProgress.latest(in: tail(log, bytes: 8000)) {
                self.report(ServerUpdateProgress(.installing, message: update.message, percent: update.percent))
            } else { self.report(self.current) }
        }
        timer = poll; RunLoop.main.add(poll, forMode: .common)
        report(current)
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            do {
                let fleet = Fleet(paths: engine.paths)
                if let automaticBuild {
                    let store = try Store(paths: engine.paths)
                    guard try store.load().automaticServerUpdates == true,
                          ServerUpdatePolicy.serversAreEmpty(try fleet.statuses()) else {
                        DispatchQueue.main.async { self.timer?.invalidate(); self.timer = nil; self.window.close(); completion() }
                        return
                    }
                    try store.update { $0.lastAutomaticServerUpdateAttempt = automaticBuild }
                }
                let restart = try fleet.runningIDs()
                if !restart.isEmpty {
                    DispatchQueue.main.async { self.report(ServerUpdateProgress(.stopping, message: "Saving worlds and stopping servers…")) }
                    try fleet.stopAll()
                }
                DispatchQueue.main.async { self.report(ServerUpdateProgress(.installing, message: "Preparing the server update…")) }
                try Installer(paths: engine.paths).install {
                    DispatchQueue.main.async { self.downloading = true }
                }
                DispatchQueue.main.async { self.downloading = false; self.report(ServerUpdateProgress(.installing, message: "Finishing the update…")) }
                if !restart.isEmpty {
                    DispatchQueue.main.async { self.report(ServerUpdateProgress(.starting, message: "Starting the updated servers…")) }
                    try fleet.start(restart)
                }
            } catch {
                failure = error.localizedDescription
            }
            DispatchQueue.main.async {
                self.timer?.invalidate(); self.timer = nil; self.window.close()
                completion()
                if let failure {
                    let alert = NSAlert(); alert.messageText = "Server update needs attention"
                    alert.informativeText = failure + "\nYour world files have not been replaced. Check server status before starting it again."
                    alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Open Update Log")
                    if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(log) }
                }
            }
        }
    }
}
