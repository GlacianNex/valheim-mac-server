import AppKit
import ServerCore

final class SetupWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    let engine: Engine
    let onCreate: () -> Void, onChange: () -> Void, onClose: () -> Void
    let status = NSTextField(wrappingLabelWithString: "")
    let progress = NSProgressIndicator()
    let install = NSButton(title: "Install Native Server", target: nil, action: nil)
    let create = NSButton(title: "Create or Import a World…", target: nil, action: nil)
    let login = NSButton(checkboxWithTitle: "Open the monitor when I log in", target: nil, action: nil)
    var working = false
    var timer: Timer?
    init(engine: Engine, onCreate: @escaping () -> Void, onChange: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.engine = engine; self.onCreate = onCreate; self.onChange = onChange; self.onClose = onClose
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Set Up Valheim Server Monitor"; window.delegate = self; window.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)])
        let heading = NSTextField(labelWithString: "Your world, always ready."); heading.font = .boldSystemFont(ofSize: 22); stack.addArrangedSubview(heading)
        let intro = NSTextField(wrappingLabelWithString: "Install the native Valheim server directly from Valve, then create a world or import a copy of an existing save. No Steam sign-in or CrossOver is needed. Allow about 2 GB for the download and 6 GB of free space for installation and updates.")
        intro.preferredMaxLayoutWidth = 530; stack.addArrangedSubview(intro)
        let rosetta = NSTextField(wrappingLabelWithString: "On Apple Silicon, Valve’s download tool uses Rosetta. If it is missing, we’ll ask before installing it. The game server itself runs natively.")
        rosetta.textColor = .secondaryLabelColor; rosetta.font = .systemFont(ofSize: 12); rosetta.preferredMaxLayoutWidth = 530; stack.addArrangedSubview(rosetta)
        install.target = self; install.action = #selector(installServer); stack.addArrangedSubview(install)
        progress.style = .bar; progress.isIndeterminate = true; progress.widthAnchor.constraint(equalToConstant: 530).isActive = true; progress.isHidden = true; stack.addArrangedSubview(progress)
        status.preferredMaxLayoutWidth = 530; status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor; stack.addArrangedSubview(status)
        login.state = .on; stack.addArrangedSubview(login)
        create.target = self; create.action = #selector(createWorld); stack.addArrangedSubview(create)
        let note = NSTextField(wrappingLabelWithString: "Start the server from the menu bar after saving your profile. Server autostart is a separate, optional menu setting. Your Mac must stay awake and logged in to host.")
        note.preferredMaxLayoutWidth = 530; note.font = .systemFont(ofSize: 12); stack.addArrangedSubview(note)
        refresh(); window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func refresh() {
        let installed = FileManager.default.isExecutableFile(atPath: engine.paths.executable.path)
        create.isEnabled = installed && !working; install.isEnabled = !working
        install.title = installed ? "Check / Install Server Update" : "Install Native Server"
        status.stringValue = installed ? "Native server installed. Ready to create or import a world." : "Step 1 of 2: install the native server."
    }
    @objc func installServer() {
        guard !working else { return }
        if Installer.needsRosetta {
            let alert = NSAlert(); alert.messageText = "Install Apple Rosetta?"
            alert.informativeText = "Valve’s download tool requires Rosetta on this Mac. Continuing runs Apple’s Rosetta installer and accepts its license terms. You can read the terms at apple.com/legal/sla/. The native Valheim server does not require Rosetta."
            alert.addButton(withTitle: "Install Rosetta & Continue"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        working = true; refresh(); progress.isHidden = false; progress.startAnimation(nil)
        window.standardWindowButton(.closeButton)?.isEnabled = false
        status.stringValue = "Preparing download…"
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let lines = tail(self.engine.paths.logs.appendingPathComponent("installation.log"), bytes: 1600).split(whereSeparator: \.isNewline)
            if let line = lines.last { self.status.stringValue = String(line.suffix(200)) }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            do {
                if Installer.needsRosetta { try Installer.installRosetta() }
                try Installer(paths: self.engine.paths).install()
            } catch { failure = error.localizedDescription }
            DispatchQueue.main.async {
                self.working = false; self.timer?.invalidate(); self.timer = nil
                self.progress.stopAnimation(nil); self.progress.isHidden = true
                self.window.standardWindowButton(.closeButton)?.isEnabled = true
                self.refresh(); self.onChange()
                if let failure {
                    self.status.stringValue = failure
                    let alert = NSAlert(); alert.messageText = "Installation needs attention"; alert.informativeText = failure; alert.runModal()
                }
            }
        }
    }
    @objc func createWorld() {
        if !engine.paths.isDevelopment, login.state == .on {
            do { try LoginItems(paths: engine.paths).monitorAtLogin(true) }
            catch { let alert = NSAlert(); alert.messageText = "Login startup could not be enabled"; alert.informativeText = error.localizedDescription; alert.runModal() }
        }
        onCreate(); window.close()
    }
    func windowWillClose(_ notification: Notification) { timer?.invalidate(); onClose() }
}
