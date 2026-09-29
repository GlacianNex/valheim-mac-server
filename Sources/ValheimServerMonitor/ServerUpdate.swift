import AppKit
import ServerCore

final class ServerUpdateWindow {
    let window: NSWindow
    private let status = NSTextField(wrappingLabelWithString: "Preparing the server update…")
    private let progress = NSProgressIndicator()
    private var timer: Timer?
    private var downloading = false
    private let cancellationLock = NSLock()
    private enum Cancelled: Error { case byUser }
    private let cancel = NSButton(title: "Cancel", target: nil, action: nil)
    private let restartNowButton = NSButton(title: "Restart Now", target: nil, action: nil)
    private var cancelled = false
    private var immediateRestart = false
    private var shouldRestartNow: Bool { cancellationLock.lock(); defer { cancellationLock.unlock() }; return immediateRestart }
    private var isCancelled: Bool { cancellationLock.lock(); defer { cancellationLock.unlock() }; return cancelled }
    @objc private func cancelCountdown() {
        cancellationLock.lock(); cancelled = true; cancellationLock.unlock()
        cancel.isEnabled = false; restartNowButton.isEnabled = false
        status.stringValue = "Cancelling restart…"
    }
    @objc private func restartImmediately() {
        cancellationLock.lock(); immediateRestart = true; cancellationLock.unlock()
        restartNowButton.isEnabled = false
    }

    @objc private func hideCountdown() { window.close() }

    private var current = ServerUpdateProgress(.preparing, message: "Preparing the server update…")
    private var stageStarted = Date()
    private let onProgress: (ServerUpdateProgress) -> Void
    private func report(_ value: ServerUpdateProgress) {
        if value.phase != current.phase { stageStarted = Date() }
        current = value
        let canCancel = value.phase == .preparing || value.phase == .countdown
        cancel.isEnabled = canCancel && !isCancelled
        restartNowButton.isEnabled = value.phase == .countdown && !isCancelled && !shouldRestartNow
        let elapsed = Int(Date().timeIntervalSince(stageStarted))
        status.stringValue = value.message + (elapsed >= 5 ? "\nThis stage: \(elapsed)s" : "")
        progress.isIndeterminate = value.percent == nil
        if let percent = value.percent { progress.doubleValue = percent } else { progress.startAnimation(nil) }
        onProgress(value)
    }
    init(engine: Engine, automaticBuild: String? = nil, managementOnly: Bool = false, scheduledID: String? = nil, scheduledDeadline: Date? = nil, restartServers: (([String]) throws -> Void)? = nil, onProgress: @escaping (ServerUpdateProgress) -> Void, completion: @escaping () -> Void) {
        self.onProgress = onProgress
        current = ServerUpdateProgress(.preparing,message:scheduledID == nil ? "Preparing the server update…" : "Preparing the scheduled restart…")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 150), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = scheduledID == nil ? "Updating Valheim Server" : "Scheduled Server Restart"; window.isReleasedWhenClosed = false
        status.frame = NSRect(x: 24, y: 68, width: 552, height: 55)
        progress.frame = NSRect(x: 24, y: 35, width: 235, height: 20)
        progress.style = .bar; progress.isIndeterminate = true; progress.startAnimation(nil)
        cancel.target = self; cancel.action = #selector(cancelCountdown)
        cancel.frame = NSRect(x: 270, y: 28, width: 90, height: 32)
        restartNowButton.target = self; restartNowButton.action = #selector(restartImmediately)
        restartNowButton.frame = NSRect(x: 365, y: 28, width: 135, height: 32)
        restartNowButton.isEnabled = false
        let close = NSButton(title: "Close", target: self, action: #selector(hideCountdown))
        close.frame = NSRect(x: 505, y: 28, width: 75, height: 32)
        close.toolTip = "Hide this window. The countdown continues; reopen it from the menu bar."
        window.contentView?.addSubview(close)
        window.contentView?.addSubview(cancel)
        window.contentView?.addSubview(restartNowButton)
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
                let store = try Store(paths: engine.paths)
                var lease: MaintenanceLease?
                defer { lease?.release() }
                let active = try fleet.lifecycles().filter { $0.isActive && (scheduledID == nil || $0.paths.profileID == scheduledID) }
                if scheduledID != nil && active.isEmpty { throw MonitorError("The server was stopped. Scheduled restart cancelled.") }
                let bridges = active.map { ManagedServer(paths:$0.paths) }
                let allManaged = bridges.allSatisfy { bridge in
                    guard bridge.enabled, let connection = try? bridge.connection() else { return false }
                    return (try? connection.send("health"))?.hasPrefix("OK ManagerRcon") == true
                }
                let empty = try active.allSatisfy { let s = try $0.status(); return s.state == "Online" && s.players == "0" }
                if !allManaged && !empty {
                    if automaticBuild != nil { DispatchQueue.main.async { self.timer?.invalidate(); self.window.close(); completion() }; return }
                    throw MonitorError("Players are connected or their count is unavailable. This restart must wait until servers are empty because player warnings are unavailable.")
                }
                let generations = active.map { $0.manualStopGeneration }
                let records = active.map { $0.record?.started }
                let restart = active.compactMap { $0.paths.profileID }
                if let automaticBuild { try store.update { $0.lastAutomaticServerUpdateAttempt = automaticBuild } }
                let deadline = scheduledID != nil ? scheduledDeadline : (allManaged && !active.isEmpty ? Date().addingTimeInterval(UpdateCountdown.duration) : nil)
                var workflow = RestartWorkflow(validate: {
                    guard !self.isCancelled else { throw Cancelled.byUser }
                    if try automaticBuild != nil && !managementOnly && store.load().automaticServerUpdates != true {
                        throw MonitorError("Automatic updates were turned off. Servers were left running.")
                    }
                    for (i, server) in active.enumerated() {
                        guard server.isActive, !server.requested("stop-request"), server.record?.started == records[i], server.manualStopGeneration == generations[i] else {
                            throw MonitorError("A server was stopped or restarted during the countdown. Maintenance cancelled.")
                        }
                    }
                    if !allManaged || deadline == nil {
                        guard try active.allSatisfy({ let s = try $0.status(); return s.state == "Online" && s.players == "0" }) else {
                            throw MonitorError("A player joined or the player count is unavailable. Restart cancelled.")
                        }
                    }
                }, warn: { minutes in
                    for bridge in bridges { try bridge.warn(minutes:minutes, managementOnly:managementOnly, scheduled:scheduledID != nil) }
                }, stop: {
                    // Keep controls usable during the countdown; lock only the actual maintenance.
                    lease = try MaintenanceLease(paths: engine.paths)
                    let currentActive = try fleet.lifecycles().filter { $0.isActive && (scheduledID == nil || $0.paths.profileID == scheduledID) }
                    guard Set(currentActive.compactMap { $0.paths.profileID }) == Set(restart) else {
                        throw MonitorError("The running servers changed during the countdown. Restart cancelled; start it again to include the current servers.")
                    }
                    for (i, server) in active.enumerated() {
                        guard !server.requested("stop-request"), server.record?.started == records[i], server.manualStopGeneration == generations[i] else {
                            throw MonitorError("A server was stopped or restarted during the countdown. Maintenance cancelled.")
                        }
                    }
                    if deadline != nil {
                        for bridge in bridges { guard try bridge.connection().send("health").hasPrefix("OK ManagerRcon") else { throw MonitorError("Warning connection was lost. Restart cancelled.") } }
                    }
                    // Serialize the last cancellation check with button actions before stopping.
                    try DispatchQueue.main.sync {
                        guard !self.isCancelled else { throw Cancelled.byUser }
                        self.cancel.isEnabled = false; self.restartNowButton.isEnabled = false
                    }
                    for server in active { try server.requestStop(wait:false, manual:false) }
                    for server in active { try server.requestStop(manual:false) }
                }, install: {
                    guard scheduledID == nil else { return }
                    if !managementOnly { try Installer(paths:engine.paths).install { DispatchQueue.main.async { self.downloading = true } } }
                    let runtimeLease = try RuntimeLease(paths:engine.paths,exclusive:true)
                    defer { withExtendedLifetime(runtimeLease) {} }
                    for server in try fleet.lifecycles() {
                        let bridge = ManagedServer(paths:server.paths)
                        if bridge.enabled { try bridge.prepare() }
                    }
                    DispatchQueue.main.async { self.downloading = false }
                }, start: {
                    // A manual stop issued while saving must win over automatic restart.
                    let resume = restart.enumerated().filter { active[$0.offset].manualStopGeneration == generations[$0.offset] }.map { $0.element }
                    lease?.release()
                    if let restartServers { try restartServers(resume) } else { try fleet.start(resume) }
                    let expires = Date().addingTimeInterval(600)
                    var pending = Set(resume)
                    while !pending.isEmpty && Date() < expires {
                        for server in active where pending.contains(server.paths.profileID ?? "") {
                            let status = try server.status()
                            let managedReady = !ManagedServer(paths:server.paths).enabled || (try? ManagedServer(paths:server.paths).connection().send("health"))?.hasPrefix("OK ManagerRcon") == true
                            if status.state == "Online" && managedReady {
                                pending.remove(status.selected)
                                try MaintenanceLog.write(paths:engine.paths,server:status.selected,message:"reason=\(scheduledID == nil ? "update" : "scheduled") restarted; join code=\(status.code.isEmpty ? "not available (Steam networking)" : status.code)")
                            }
                        }
                        if !pending.isEmpty { Thread.sleep(forTimeInterval:1) }
                    }
                    if !pending.isEmpty { throw MonitorError("Startup is not yet confirmed. Check the affected server logs; the manager will keep showing their current status.") }
                }, progress: { value in DispatchQueue.main.async { self.report(value) } })
                workflow.restartNow = { self.shouldRestartNow }
                if let scheduledID { try MaintenanceLog.write(paths:engine.paths,server:scheduledID,message:"reason=scheduled restart requested") }
                try workflow.run(deadline:deadline,updating:scheduledID == nil)

            } catch is Cancelled {
                try? MaintenanceLog.write(paths:engine.paths,server:scheduledID ?? "fleet",message:"Restart cancelled by user; servers left running.")
            } catch {
                failure = error.localizedDescription
                try? MaintenanceLog.write(paths:engine.paths,server:scheduledID ?? "fleet",message:"reason=\(scheduledID == nil ? "update" : "scheduled") incomplete: " + error.localizedDescription)
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
