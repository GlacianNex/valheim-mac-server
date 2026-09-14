import AppKit

class ProfileFormStack: NSStackView { override var isFlipped: Bool { true } }

// Recompute hover from the pointer and clipped geometry, including during scrolling.
class HelpLabel: NSTextField {
    private var hovered = false

    func configureHelp(_ text: String) {
        toolTip = text
        wantsLayer = true
        layer?.cornerRadius = 4
        refreshAppearance()
    }
    func updateHover() {
        let inside: Bool
        if let window = window, window.isKeyWindow, window.isVisible, !isHiddenOrHasHiddenAncestor {
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            inside = !visibleRect.isEmpty && NSMouseInRect(point, visibleRect, isFlipped)
        } else {
            inside = false
        }
        guard inside != hovered else { return }
        hovered = inside
        refreshAppearance()
    }
    func clearHover() {
        hovered = false
        refreshAppearance()
    }
    private func refreshAppearance() {
        let color: NSColor = hovered ? .controlAccentColor : .labelColor
        attributedStringValue = NSAttributedString(string: stringValue, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: color,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: hovered ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
        ])
        layer?.backgroundColor = (hovered ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.clear).cgColor
        needsDisplay = true
    }
}

class ProfileEditor: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    var window: NSWindow!
    var saveButton: NSButton?
    private var helpLabels: [HelpLabel] = []
    private var hoverTimer: Timer?
    var fields: [String:NSControl] = [:]
    var original: [String:Any]
    var onSave: ([String:Any])->Void
    private var inheritedFlags: [String: Bool] = [:]
    let readOnly: Bool
    var selectedImport = ""
    let importLabel = NSTextField(labelWithString: "Fresh world (created on first start)")
    init(profile: [String:Any], readOnly: Bool = false, onSave: @escaping ([String:Any])->Void) {
        original=profile; self.onSave=onSave; self.readOnly=readOnly
        super.init()
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:650,height:720),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title = readOnly ? "Server Settings (Read Only)" : (profile["id"] as? String ?? "").isEmpty ? "New Server" : "Edit Server"
        window.isReleasedWhenClosed=false; window.delegate=self
        let content=window.contentView!
        let scroll=NSScrollView(frame:NSRect(x:0,y:65,width:650,height:655))
        scroll.autoresizingMask=[.width,.height];scroll.hasVerticalScroller=true
        let stack=ProfileFormStack();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=12
        stack.edgeInsets=NSEdgeInsets(top:20,left:20,bottom:20,right:20)
        scroll.documentView=stack;stack.translatesAutoresizingMaskIntoConstraints=false
        stack.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor).isActive=true
        content.addSubview(scroll)
        func section(_ title:String) {let label=NSTextField(labelWithString:title);label.font = .boldSystemFont(ofSize:14);stack.addArrangedSubview(label)}
        func row(_ key:String,_ title:String,_ choices:[String]? = nil,_ check:Bool=false,_ secret:Bool=false) {
            let line=NSStackView();line.orientation = .horizontal;line.spacing=12
            let label=HelpLabel(labelWithString:title);label.widthAnchor.constraint(equalToConstant:210).isActive=true
            line.addArrangedSubview(label)
            let control:NSControl
            if check {
                let saved = (profile["_savedFlags"] as? [String: Bool])?[key]
                let explicit = profile[key] as? Bool ?? false
                let b=NSButton(checkboxWithTitle: !explicit && saved != nil ? "Saved world: \(saved! ? "Enabled" : "Disabled")" : "Enabled",target:nil,action:nil)
                b.state=(explicit || saved == true) ? .on:.off;control=b
                if !explicit, let saved { inheritedFlags[key] = saved }
            } else if let choices=choices {
                let popup=NSPopUpButton()
                for raw in choices {
                    var title = SettingsHelp.title(key,raw)
                    if raw.isEmpty, let saved = profile["_savedModifiers"] as? [String: String] {
                        if let value = saved[key] { title = "Saved world: " + SettingsHelp.savedTitle(key, value) }
                        else if key == "preset" { title = "Saved world: " + (saved.values.allSatisfy { $0 == "default" } ? "Normal modifiers" : "Custom modifiers") }
                    }
                    popup.addItem(withTitle:title)
                    popup.lastItem?.representedObject=raw
                    popup.lastItem?.toolTip=SettingsHelp.optionHelp(key,raw)
                }
                let value=profile[key] as? String ?? "";popup.selectItem(at:choices.firstIndex(of:value) ?? 0);control=popup
            } else {
                let t:NSTextField=secret ? NSSecureTextField():NSTextField()
                t.stringValue=profile[key].map{String(describing:$0)} ?? "";control=t
                if key == "password" { t.delegate = self }
                if key=="world" {
                    if !(profile["id"] as? String ?? "").isEmpty {t.isEditable=false}
                    else {t.placeholderString="Automatic from profile name"}
                }
            }
            control.toolTip=SettingsHelp.fieldHelp(key)
            label.configureHelp(SettingsHelp.fieldHelp(key))
            helpLabels.append(label)
            line.toolTip=SettingsHelp.fieldHelp(key)
            control.widthAnchor.constraint(equalToConstant:365).isActive=true
            fields[key]=control;line.addArrangedSubview(control);stack.addArrangedSubview(line)
        }
        func note(_ text:String) {let n=NSTextField(wrappingLabelWithString:text);n.textColor = .secondaryLabelColor;n.font = .systemFont(ofSize:11);n.widthAnchor.constraint(equalToConstant:590).isActive=true;stack.addArrangedSubview(n)}
        note("Hover over underlined labels for help with each setting and its options.")
        section("Identity & World")
        row("label","Server name");row("name","Public server name");row("world","World filename")
        if (profile["id"] as? String ?? "").isEmpty {
            let b=NSButton(title:"Import World…",target:self,action:#selector(chooseImport));b.toolTip="Copy a saved world into this new profile. Accepts one-world ZIPs, world folders, or a .db with its matching .fwl. The source is never moved or modified.";stack.addArrangedSubview(b)
            importLabel.lineBreakMode = .byTruncatingMiddle;importLabel.widthAnchor.constraint(equalToConstant:590).isActive=true;stack.addArrangedSubview(importLabel)
            note("For a fresh world, leave World filename blank to generate it from your profile name. To import, choose one world ZIP, a world folder, or a .db with its .fwl; the filename must match the saved world. Originals are copied and preserved. For a custom seed, create the world in Valheim and import it.")
        }
        section("Connection")
        row("public","Server listing",nil,true)
        if let listed = fields["public"] as? NSButton {
            listed.title = "List my server"; listed.target = self; listed.action = #selector(listingChanged)
        }
        row("password","Password",nil,false,true)
        note("Listed servers require a password of at least five characters. Unlisted servers remain accessible by address or join code; any existing password is preserved.")
        row("port","Port");row("crossplay","Crossplay",nil,true);row("instanceid","Instance ID (optional)")
        note("Without crossplay, remote connections require router forwarding for the selected UDP port and the next port.")
        section("Saving & Backups")
        row("saveinterval","Save interval (seconds)");row("backups","Backup count");row("backupshort","Short backup (seconds)");row("backuplong","Long backup (seconds)")
        section("World Modifiers")
        if let savedNote = profile["_savedSettingsNote"] as? String { note(savedNote) }
        note("Blank means preserve saved world settings. Presets overwrite modifiers. Checkboxes apply enabled world keys; unchecking does not undo keys already stored in a world. Configure those in Valheim itself.")
        row("preset","Preset",["","Normal","Casual","Easy","Hard","Hardcore","Immersive","Hammer"])
        row("Combat","Combat",["","veryeasy","easy","hard","veryhard"])
        row("DeathPenalty","Death penalty",["","casual","veryeasy","easy","hard","hardcore"])
        row("Resources","Resources",["","muchless","less","more","muchmore","most"])
        row("Raids","Raids",["","none","muchless","less","more","muchmore"])
        row("Portals","Portals",["","casual","hard","veryhard"])
        row("nobuildcost","No build cost",nil,true);row("playerevents","Player-based raids",nil,true);row("passivemobs","Passive enemies",nil,true);row("nomap","No map",nil,true);row("fire","Spreading fire hazards",nil,true)
        section("Access Lists")
        note("Enter platform IDs separated by commas or newlines. A nonempty permitted list excludes everyone else.")
        row("admins","Admin IDs");row("banned","Banned IDs");row("permitted","Permitted IDs")
        section("Advanced")
        row("extra","Additional arguments")
        note("Space-separated arguments; quote values containing spaces. Do not duplicate fields above. Save and log paths are managed by the app. Changes apply on the next start.")
        let cancel=NSButton(title:"Cancel",target:self,action:#selector(close));cancel.frame=NSRect(x:425,y:18,width:90,height:30);cancel.autoresizingMask=[.minXMargin,.maxYMargin];content.addSubview(cancel)
        let save=NSButton(title:"Save Server",target:self,action:#selector(save));save.frame=NSRect(x:525,y:18,width:110,height:30);save.autoresizingMask=[.minXMargin,.maxYMargin];save.keyEquivalent="\r";content.addSubview(save)
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.helpLabels.forEach { $0.updateHover() }
        }
        hoverTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        saveButton = save
        updatePasswordVisibility()
        if readOnly {
            window.title = "Server Settings (Read Only)"
            save.isHidden = true; cancel.title = "Close"
            for control in fields.values {
                if let text = control as? NSTextField { text.isEditable = false; text.isSelectable = true }
                else { control.isEnabled = false }
            }
        }
        window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        content.layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to:NSPoint(x:0,y:stack.isFlipped ? 0 : max(0,stack.bounds.height-scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        DispatchQueue.main.async {
            content.layoutSubtreeIfNeeded()
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
    func windowDidResignKey(_ notification: Notification) {
        helpLabels.forEach { $0.clearHover() }
    }
    func windowWillClose(_ notification: Notification) {
        hoverTimer?.invalidate()
        hoverTimer = nil
        helpLabels.forEach { $0.clearHover() }
    }
    deinit { hoverTimer?.invalidate() }

    func controlTextDidChange(_ notification: Notification) {}
    @objc private func listingChanged() { updatePasswordVisibility() }
    private func updatePasswordVisibility() {
        guard !readOnly, let password = fields["password"] as? NSTextField, let listed = fields["public"] as? NSButton else { return }
        password.isEnabled = listed.state == .on
        password.placeholderString = listed.state == .on ? "Required — at least 5 characters" : "No password"
        listed.isEnabled = true
    }
    func setSaving(_ saving: Bool) {
        saveButton?.isEnabled = !saving
        saveButton?.title = saving ? "Saving…" : "Save Server"
        window.standardWindowButton(.closeButton)?.isEnabled = !saving
    }
    @objc func chooseImport() {
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=true;panel.allowsMultipleSelection=false
        if panel.runModal() == .OK, let url=panel.url {
            selectedImport=url.path;importLabel.stringValue=url.lastPathComponent
            if let f=fields["world"] as? NSTextField, f.stringValue.isEmpty {f.stringValue=url.deletingPathExtension().lastPathComponent}
        }
    }
    @objc func save() {
        guard !readOnly else { return }
        var p=original
        for (key,c) in fields {
            if let b=c as? NSButton {p[key]=b.state == .on}
            else if let popup=c as? NSPopUpButton {p[key]=popup.selectedItem?.representedObject as? String ?? ""}
            else if let t=c as? NSTextField {p[key]=t.stringValue}
        }
        // NSPopUpButton is an NSButton subclass; capture its selected text explicitly.
        for (key,c) in fields {if let popup=c as? NSPopUpButton {p[key]=popup.selectedItem?.representedObject as? String ?? ""}}
        for (key, saved) in inheritedFlags {
            if let button = fields[key] as? NSButton, (button.state == .on) == saved { p[key] = original[key] }
        }
        for key in ["admins","banned","permitted"] {p[key]=(p[key] as? String ?? "").replacingOccurrences(of:",",with:"\n")}
        p["import"]=selectedImport;onSave(p)
    }
    @objc func close(){window.close()}
}
