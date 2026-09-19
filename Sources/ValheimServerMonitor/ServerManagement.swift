import AppKit
import ServerCore

final class ServerManagementWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let paths: Paths
    private let summary = NSTextField(wrappingLabelWithString: "Connecting to server management…")
    private let target = NSTextField()
    private let result = NSTextField(wrappingLabelWithString: "")
    private var timer: Timer?
    private var checking = false
    init(paths: Paths, name: String) {
        self.paths = paths
        window = NSWindow(contentRect: NSRect(x:0,y:0,width:530,height:340), styleMask:[.titled,.closable], backing:.buffered, defer:false)
        super.init()
        window.title = name + " — Server Management"; window.isReleasedWhenClosed = false; window.delegate = self
        summary.frame = NSRect(x:24,y:140,width:482,height:170)
        target.frame = NSRect(x:24,y:105,width:482,height:25); target.placeholderString = "Player name or platform ID"
        for (index,title) in ["Kick", "Ban", "Unban"].enumerated() {
            let button = NSButton(title:title, target:self, action:#selector(moderate(_:))); button.identifier = NSUserInterfaceItemIdentifier(title.lowercased())
            button.frame = NSRect(x:24+index*115,y:65,width:105,height:30); window.contentView?.addSubview(button)
        }
        result.frame = NSRect(x:24,y:15,width:482,height:45)
        window.contentView?.addSubview(summary); window.contentView?.addSubview(target); window.contentView?.addSubview(result)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        timer = Timer.scheduledTimer(withTimeInterval:5,repeats:true) { [weak self] _ in self?.refresh() }; refresh()
    }
    func windowWillClose(_ notification: Notification) { timer?.invalidate(); timer = nil }
    private func refresh() {
        guard !checking else { return }; checking = true
        DispatchQueue.global(qos:.utility).async {
            let text: String
            do {
                let response = try ManagedServer(paths:self.paths).connection().send("serverInfo")
                guard let values = try JSONSerialization.jsonObject(with:Data(response.utf8)) as? [String:Any] else { throw MonitorError("Invalid server information") }
                let fps = (values["fps"] as? NSNumber)?.doubleValue ?? 0
                let memory = ((values["managedMemoryBytes"] as? NSNumber)?.doubleValue ?? 0) / 1048576
                let uptime = Int((values["uptimeSeconds"] as? NSNumber)?.doubleValue ?? 0)
                text = "Valheim \(values["version"] as? String ?? "Unknown")\nPlayers: \(values["players"] as? Int ?? 0)\nSmoothed server FPS: \(String(format:"%.1f",fps))\nManaged memory: \(String(format:"%.0f",memory)) MB\nUptime: \(uptime/60)m \(uptime%60)s\n\nRefreshes every 5 seconds. Memory excludes native allocations."
            } catch { text = error.localizedDescription }
            DispatchQueue.main.async { self.checking = false; self.summary.stringValue = text }
        }
    }
    @objc private func moderate(_ sender: NSButton) {
        guard let action = sender.identifier?.rawValue else { return }
        let player = target.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !player.isEmpty, !player.contains("\n") else { result.stringValue = "Enter a player name or platform ID."; return }
        let alert = NSAlert(); alert.messageText = "\(sender.title) \(player)?"; alert.informativeText = "This applies only to \(window.title)."; alert.addButton(withTitle:"Cancel"); alert.addButton(withTitle:sender.title)
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        sender.isEnabled = false
        DispatchQueue.global(qos:.userInitiated).async {
            let text: String
            do { text = try ManagedServer(paths:self.paths).moderate(action:action,target:player) }
            catch { text = error.localizedDescription }
            DispatchQueue.main.async { sender.isEnabled = true; self.result.stringValue = text; self.refresh() }
        }
    }
}
