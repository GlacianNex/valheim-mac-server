import AppKit
import ServerCore

/// Development browser: prepares per-server packages; loader deployment is gated separately.
final class ModsWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextViewDelegate {
    let window: NSWindow
    let library: ModLibrary
    let serverPaths: Paths
    let source = NSPopUpButton()
    let search = NSSearchField()
    let sort = NSPopUpButton()
    let versions = NSPopUpButton()
    let table = NSTableView()
    let detail = NSTextView()
    let metrics = NSTextField(wrappingLabelWithString: "")
    let requirements = NSTextField(wrappingLabelWithString: "")
    let dependencies = NSTextView()
    let tabs = NSTabView()
    let installInstructions = NSTextView()
    let installationNotice = NSTextField(wrappingLabelWithString: "")
    var readmeTask: Task<Void, Never>?
    var readmes: [String: String] = [:]
    let status = NSTextField(labelWithString: "")
    let downloadButton = NSButton(title: "Install Mod", target: nil, action: nil)
    let importButton = NSButton(title: "Install from File…", target: nil, action: nil)
    let selectionButton = NSButton(title: "Enable Mod", target: nil, action: nil)
    let hostButton = NSButton(title: "Open Mod Website", target: nil, action: nil)
    var packages: [ModPackage] = []
    var rows: [ModPackage] = []
    var stored: [StoredMod] = []
    var catalogs: [ModSource: [ModPackage]] = [:]
    var loading = false
    var isLibrary: Bool { source.indexOfSelectedItem == 3 }
    var currentSource: ModSource? { source.indexOfSelectedItem == 1 ? .thunderstore : source.indexOfSelectedItem == 2 ? .hexium : nil }
    func provider(for mod: ModPackage) -> ModSource { catalogs[.hexium]?.contains(where: { $0.package_url == mod.package_url }) == true ? .hexium : .thunderstore }
    init(paths: Paths, profileID: String, name: String, loadCatalogs: Bool = true) throws {
        serverPaths = Paths(root:paths.root,profileID:profileID)
        library = try ModLibrary(paths: paths, profileID: profileID)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 660), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Mod Catalog"; window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 850, height: 600)
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 12; stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20), stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20)])
        stack.addArrangedSubview(NSTextField(labelWithString:"Installing to: " + name))
        let note = NSTextField(wrappingLabelWithString: "Known incompatible and client-only packages are hidden. Installing also enables the mod and its dependencies for the next start.")
        note.textColor = .secondaryLabelColor; stack.addArrangedSubview(note)
        let toolbar = NSStackView(); toolbar.orientation = .horizontal; toolbar.spacing = 10
        source.addItems(withTitles: ["All Sources", "Thunderstore", "Hexium", "This Server"]); source.target = self; source.action = #selector(sourceChanged)
        search.placeholderString = "Search names, descriptions, authors…"; search.delegate = self
        search.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        sort.addItems(withTitles: ["Most downloaded", "Highest rated", "Name"]); sort.target = self; sort.action = #selector(filterRows)
        for view in [source, search, sort] { toolbar.addArrangedSubview(view) }
        stack.addArrangedSubview(toolbar)
        let split = NSStackView(); split.orientation = .horizontal; split.spacing = 16; split.alignment = .top
        let list = NSScrollView(); list.hasVerticalScroller = true; list.borderType = .bezelBorder
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")); column.title = "Mods"; column.width = 350
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 44; table.delegate = self; table.dataSource = self
        list.documentView = table; list.widthAnchor.constraint(equalToConstant: 360).isActive = true
        let right = NSStackView(); right.orientation = .vertical; right.alignment = .leading; right.spacing = 10
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        detail.delegate = self; detail.isEditable = false; detail.isSelectable = true; detail.font = .systemFont(ofSize: 13)
        detail.textContainerInset = NSSize(width: 12, height: 12)
        detail.isHorizontallyResizable = false; detail.autoresizingMask = [.width]; detail.textContainer?.widthTracksTextView = true
        scroll.documentView = detail
        let dependencyScroll = NSScrollView(); dependencyScroll.hasVerticalScroller = true
        dependencies.isEditable = false; dependencies.isSelectable = true
        dependencies.font = .systemFont(ofSize: 13); dependencies.textContainerInset = NSSize(width: 12, height: 12)
        dependencies.isHorizontallyResizable = false; dependencies.autoresizingMask = [.width]
        dependencies.textContainer?.widthTracksTextView = true; dependencyScroll.documentView = dependencies
        let installScroll = NSScrollView(); installScroll.hasVerticalScroller = true
        installInstructions.isEditable = false; installInstructions.isSelectable = true
        installInstructions.font = .systemFont(ofSize: 13); installInstructions.textContainerInset = NSSize(width: 12, height: 12)
        installInstructions.isHorizontallyResizable = false; installInstructions.autoresizingMask = [.width]
        installInstructions.textContainer?.widthTracksTextView = true; installScroll.documentView = installInstructions
        for (name, view) in [("Description", scroll as NSView), ("Dependencies", dependencyScroll as NSView), ("Install Instructions", installScroll as NSView)] {
            let tab = NSTabViewItem(identifier: name); tab.label = name; tab.view = view; tabs.addTabViewItem(tab)
        }
        right.addArrangedSubview(versions); right.addArrangedSubview(requirements); right.addArrangedSubview(installationNotice); right.addArrangedSubview(tabs)
        installationNotice.textColor = .systemOrange
        installationNotice.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
        tabs.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
        versions.target = self; versions.action = #selector(showDetails)
        split.addArrangedSubview(list); split.addArrangedSubview(right)
        // Cross-column constraints require both views to share an ancestor first.
        right.heightAnchor.constraint(equalTo: list.heightAnchor).isActive = true
        stack.addArrangedSubview(split)
        split.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        right.trailingAnchor.constraint(equalTo: split.trailingAnchor).isActive = true
        split.heightAnchor.constraint(greaterThanOrEqualToConstant: 340).isActive = true
        list.heightAnchor.constraint(equalTo: split.heightAnchor).isActive = true
        let actions = NSStackView(); actions.spacing = 8
        for button in [downloadButton, importButton, selectionButton, hostButton] { button.target = self; actions.addArrangedSubview(button) }
        downloadButton.action = #selector(downloadSelected); importButton.action = #selector(importMod)
        selectionButton.action = #selector(toggleSelection); hostButton.action = #selector(openHost)
        stack.addArrangedSubview(actions); stack.addArrangedSubview(status)
        try reloadStored(); filterRows()
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if loadCatalogs { loadAllCatalogs() }
    }
    func catalogInstallation(_ mod:ModPackage) -> String {
        if let bundled = ModCompatibility.bundled[mod.full_name] {
            let runtime = ManagedServer(paths:serverPaths).runtime
            let values = (try? JSONDecoder().decode([String:String].self,from:Data(contentsOf:runtime.appendingPathComponent("mod-versions.json")))) ?? [:]
            let installed:Bool
            if bundled.name == "BepInEx" { installed = FileManager.default.fileExists(atPath:runtime.appendingPathComponent("BepInEx/core/BepInEx.dll").path) }
            else { let directory = bundled.name == "Jötunn" ? "Jotunn" : bundled.name; installed = FileManager.default.fileExists(atPath:runtime.appendingPathComponent("BepInEx/plugins/" + directory + "/" + directory + ".dll").path) }
            return installed ? " · Installed " + (values[bundled.name] ?? bundled.version) : " · Included with Manager"
        }
        let receipt = try? JSONDecoder().decode(ModDeploymentReceipt.self,from:Data(contentsOf:ManagedServer(paths:serverPaths).runtime.appendingPathComponent("BepInEx/vsm-mod-receipt.json")))
        if let installed = receipt?.mods.first(where:{$0.package == mod.full_name}) { return " · Installed " + (installed.version ?? "") }
        if (try? library.load().mods.contains(where:{$0.package == mod.full_name})) == true { return " · Downloaded" }
        return ""
    }
    func numberOfRows(in tableView: NSTableView) -> Int { isLibrary ? stored.count : rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text: String
        if isLibrary { let mod = stored[row]; text = mod.name + " · " + (mod.version ?? "Version unknown") + (mod.selected ? "\nEnabled · Next start" : "\nDownloaded · " + mod.source.title) }
        else { let mod = rows[row]; text = mod.name + catalogInstallation(mod) + "\n" + "Score \(mod.rating_score) · \(mod.totalDownloads.formatted()) downloads" }
        let label = NSTextField(wrappingLabelWithString: text); label.font = .systemFont(ofSize: 12); label.maximumNumberOfLines = 2
        return label
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        versions.removeAllItems()
        if !isLibrary, rows.indices.contains(table.selectedRow) {
            versions.addItems(withTitles: rows[table.selectedRow].versions.filter(\.is_active).map(\.version_number))
        }
        showDetails()
    }
    func controlTextDidChange(_ notification: Notification) { filterRows() }
    private func reloadStored() throws { stored = try library.load().mods }
    @objc func sourceChanged() { filterRows() }
    func loadAllCatalogs() {
        setLoading(true, "Loading Thunderstore and Hexium…")
        Task { @MainActor in
            var failures: [String] = []
            await withTaskGroup(of: (ModSource, [ModPackage]?, String?).self) { group in
                for provider in [ModSource.thunderstore, .hexium] {
                    group.addTask {
                        do { return (provider, try await ModCatalog.fetch(provider), nil) }
                        catch { return (provider, nil, error.localizedDescription) }
                    }
                }
                for await (provider, result, failure) in group {
                    if let result { catalogs[provider] = result }
                    if let failure { failures.append(failure) }
                }
            }
            packages = [ModSource.thunderstore, .hexium].flatMap { catalogs[$0] ?? [] }
            setLoading(false, failures.isEmpty ? "\(packages.count.formatted()) packages from Thunderstore and Hexium" : failures.joined(separator: " "))
            filterRows()
        }
    }
    @objc func filterRows() {
        if isLibrary {
            do { try reloadStored() } catch { showError(error) }
            stored = stored.filter { search.stringValue.isEmpty || ($0.name + " " + $0.description).localizedCaseInsensitiveContains(search.stringValue) }
        } else {
            rows = (currentSource.map { catalogs[$0] ?? [] } ?? packages).filter {
                !$0.is_deprecated && $0.latest != nil && ModCompatibility.catalogEligible($0) && $0.matches(search.stringValue)
            }
            rows.sort {
                switch sort.indexOfSelectedItem {
                case 1: return $0.rating_score == $1.rating_score ? $0.name < $1.name : $0.rating_score > $1.rating_score
                case 2: return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                default: return $0.totalDownloads == $1.totalDownloads ? $0.rating_score > $1.rating_score : $0.totalDownloads > $1.totalDownloads
                }
            }
        }
        table.deselectAll(nil); table.reloadData(); versions.removeAllItems(); showDetails()
    }
    @objc func showDetails() {
        readmeTask?.cancel()
        installInstructions.string = "Select a mod to review author installation instructions."
        installationNotice.stringValue = ""; installationNotice.isHidden = true
        selectionButton.isHidden = !isLibrary
        downloadButton.isHidden = isLibrary
        versions.isHidden = isLibrary
        downloadButton.isEnabled = false; selectionButton.isEnabled = false; hostButton.isEnabled = false
        metrics.stringValue = ""; requirements.stringValue = ""; dependencies.string = ""
        let row = table.selectedRow
        if isLibrary, stored.indices.contains(row) {
            let mod = stored[row]
            metrics.stringValue = "\(mod.name) · \(mod.version ?? "Unknown version") · \(mod.source.title)"
            requirements.stringValue = mod.requirement.title
            dependencies.string = mod.requirement.title + "\n\nDependencies: " + (mod.dependencies.isEmpty ? "None declared" : mod.dependencies.joined(separator: ", "))
            renderDescription((try? library.readme(for: mod)) ?? mod.description)
            selectionButton.title = mod.selected ? "Disable Mod" : "Enable Mod"
            selectionButton.isEnabled = !loading && mod.requirement != .clientOnly
            hostButton.isEnabled = mod.page?.scheme == "https"
        } else if rows.indices.contains(row), let version = selectedVersion() {
            let mod = rows[row], provider = provider(for: rows[row])
            metrics.stringValue = "\(provider.title) rating score: \(mod.rating_score.formatted())\nTotal downloads: \(mod.totalDownloads.formatted())\nThis version: \(version.downloads.formatted()) downloads\nReleased: \(version.date_created.prefix(10))"
            requirements.stringValue = mod.requirement.title + catalogInstallation(mod)
            do {
                let resolved = try ModCatalog.resolve(package: mod.full_name, version: version.version_number, in: catalogs[provider] ?? [], installed: try library.load().mods)
                let needed = resolved.dropLast()
                let supplied = version.dependencies.filter { ModCompatibility.supplies($0) }
                dependencies.string = mod.requirement.title + (needed.isEmpty ? "\n\nNo additional dependency downloads needed." : "\n\nDependencies to download and enable:\n\n") + needed.map { "• \($0.package.name) \($0.version.version_number) — \(catalogPlayerEvidence($0.package,version:$0.version).requirement.title)" }.joined(separator:"\n") + (supplied.isEmpty ? "" : "\n\nIncluded with Manager:\n" + supplied.map { pin in
                    let requirement = (catalogs[provider] ?? []).first(where: { $0.full_name == ModCompatibility.split(pin)?.name })?.requirement.title ?? "Player requirements unknown"
                    return pin + " — " + requirement
                }.joined(separator:"\n"))
                if needed.isEmpty && supplied.isEmpty { dependencies.string = mod.requirement.title + "\n\nNo additional downloads needed." }
                let existing = try library.load().mods
                let reused = version.dependencies.compactMap { ModCompatibility.dependency($0, in: existing) }
                if !reused.isEmpty { dependencies.string += "\n\nAlready installed (will be enabled):\n" + reused.map { "• \($0.name) \($0.version ?? "") — \(ModPlayerEvidence.installed($0,in:existing).title)" }.joined(separator: "\n") }
                downloadButton.title = needed.isEmpty ? "Install Mod" : "Install Mod + Dependencies"
                downloadButton.isEnabled = !loading && mod.requirement != .clientOnly
            } catch { dependencies.string = "Cannot download: " + error.localizedDescription }
            if ModCompatibility.bundled[mod.full_name] != nil {
                downloadButton.title = catalogInstallation(mod).contains(" · Installed ") ? "Installed" : "Included with Manager"; downloadButton.isEnabled = false
                dependencies.string = mod.requirement.title + "\n\nManaged automatically. Use the selections at the top of Server Management to enable or disable bundled mods."
            }
            hostButton.isEnabled = mod.package_url.scheme == "https"
            let key = mod.package_url.absoluteString + version.version_number
            renderDescription(readmes[key] ?? version.description + "\n\nLoading full description…")
            if readmes[key] == nil {
                installInstructions.string = "Loading author installation instructions…"
                installationNotice.isHidden = true
                readmeTask = Task { @MainActor in
                    do {
                        let text = try await ModCatalog.readme(package: mod, version: version, source: provider)
                        guard !Task.isCancelled else { return }
                        readmes[key] = text; renderDescription(text)
                    } catch {
                        guard !Task.isCancelled else { return }
                        renderDescription(version.description + "\n\nFull description could not be loaded. Use Open Mod Website to read it.")
                        installInstructions.string = "Author instructions could not be loaded. Use Open Mod Website to read them.\n\n" + error.localizedDescription
                        installationNotice.isHidden = true
                    }
                }
            }
        } else { detail.string = "Select a mod to read its full description, choose a version, and see included dependencies." }
    }
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        if let url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        return true
    }
    private func catalogPlayerEvidence(_ mod:ModPackage, version:ModVersion?, readme:String? = nil, visited:Set<String> = []) -> ModPlayerEvidence {
        guard let version, !visited.contains(mod.full_name) else { return ModPlayerEvidence.read() }
        var visited = visited; visited.insert(mod.full_name)
        let own = ModPlayerEvidence.read(declared:mod.requirement,description:version.description,
            readme:readme ?? readmes[mod.package_url.absoluteString + version.version_number] ?? "")
        let existing = (try? library.load().mods) ?? []
        var dependencyEvidence:[ModPlayerRequirement] = []
        var requiredNames:[String] = []
        for pin in version.dependencies {
            if ModCompatibility.supplies(pin) { continue }
            var requirement:ModPlayerRequirement = .unknown
            if let installed = ModCompatibility.dependency(pin,in:existing) { requirement = ModPlayerEvidence.installed(installed,in:existing) }
            else if let split = ModCompatibility.split(pin),
                    let dependency = (catalogs[provider(for:mod)] ?? []).first(where:{$0.full_name == split.name}),
                    let neededVersion = dependency.versions.first(where:{$0.version_number == split.version}) {
                requirement = catalogPlayerEvidence(dependency,version:neededVersion,visited:visited).requirement
            }
            dependencyEvidence.append(requirement)
            if requirement == .playersRequired || requirement == .clientOnly { requiredNames.append(pin) }
        }
        let effective = ModPlayerEvidence.includingDependencies(own.requirement,dependencies:dependencyEvidence)
        return ModPlayerEvidence(requirement:effective,explanation:own.explanation + (requiredNames.isEmpty ? "" : "\nPlayer installation required by dependencies: " + requiredNames.joined(separator:", ")))
    }
    private func renderDescription(_ text: String) {
        let row = table.selectedRow
        if !isLibrary, rows.indices.contains(row) {
            let mod = rows[row]
            let evidence = catalogPlayerEvidence(mod,version:selectedVersion(),readme:text)
            requirements.stringValue = evidence.requirement.title + catalogInstallation(mod)
            requirements.toolTip = evidence.explanation
            requirements.textColor = evidence.requirement == .playersRequired ? .systemOrange : .secondaryLabelColor
        }
        let instructions = ModInstallInstructions(markdown: text)
        renderReadme(instructions.text, into:installInstructions)
        installationNotice.isHidden = !instructions.found
        installationNotice.stringValue = instructions.mayNeedExtraSteps ? "Possible extra setup — see Install Instructions." : "Author setup instructions available — see Install Instructions."
        renderReadme(text, into:detail)
        detail.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
    private func renderReadme(_ text:String, into view:NSTextView) {
        let normalized = ModReadme.displayText(text)
        guard let markdown = try? AttributedString(markdown:normalized,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace)) else { view.string = normalized; return }
        let rendered = NSMutableAttributedString(string:"")
        for run in markdown.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = intent.contains(.code) ? NSFont.monospacedSystemFont(ofSize:12,weight:.regular) : NSFont.systemFont(ofSize:13)
            if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font,toHaveTrait:.boldFontMask) }
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font,toHaveTrait:.italicFontMask) }
            var attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor]
            if let link = run.link, ["https","http"].contains(link.scheme?.lowercased() ?? "") { attributes[.link] = link }
            rendered.append(NSAttributedString(string:String(markdown[run.range].characters),attributes:attributes))
        }
        view.textStorage?.setAttributedString(rendered)
    }
    private func selectedVersion() -> ModVersion? {
        guard rows.indices.contains(table.selectedRow) else { return nil }
        return rows[table.selectedRow].versions.first { $0.version_number == versions.titleOfSelectedItem }
    }
    @objc func openHost() {
        let row = table.selectedRow
        let url = isLibrary ? (stored.indices.contains(row) ? stored[row].page : nil) : (rows.indices.contains(row) ? rows[row].package_url : nil)
        if let url, url.scheme == "https" { NSWorkspace.shared.open(url) }
    }
    @objc func downloadSelected() {
        guard !loading, !isLibrary, rows.indices.contains(table.selectedRow), let version = selectedVersion() else { return }
        let provider = provider(for: rows[table.selectedRow])
        do {
            let resolved = try ModCatalog.resolve(package: rows[table.selectedRow].full_name, version: version.version_number, in: catalogs[provider] ?? [], installed: try library.load().mods)
            let dependencies = resolved.dropLast()
            if !dependencies.isEmpty {
                let review = NSAlert(); review.messageText = "Install \(rows[table.selectedRow].name) and dependencies?"
                review.informativeText = "These dependencies need to be downloaded and enabled:\n" + dependencies.map { "• \($0.package.name) \($0.version.version_number) — \(catalogPlayerEvidence($0.package,version:$0.version).requirement.title)" }.joined(separator:"\n") + "\n\nChanges apply on the next server start.\n\n" + catalogPlayerEvidence(rows[table.selectedRow],version:version).requirement.title
                review.addButton(withTitle: "Install Mod + Dependencies"); review.addButton(withTitle:"Cancel")
                guard review.runModal() == .alertFirstButtonReturn else { return }
            }
            setLoading(true, "Downloading \(resolved.count) packages and dependencies…")
            Task { @MainActor in
                do {
                    let records = try await library.download(resolved, source:provider)
                    if let chosen = records.last { try library.select(chosen.id,enabled:true) }
                    setLoading(false,"Mod and dependencies enabled. They will load on the next server start.")
                }
                catch { setLoading(false, "Installation did not finish. Review the error; any downloaded files remain in This Server."); showError(error) }
                showDetails()
            }
        } catch { showError(error) }
    }
    @objc func importMod() {
        guard !loading else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.message = "Choose a mod ZIP, plugin folder, or DLL. Files are copied; the original is preserved."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setLoading(true, "Inspecting and importing mod…")
        DispatchQueue.global(qos: .userInitiated).async {
            let inspected = Result { try self.library.prepareImport(url) }
            DispatchQueue.main.async {
                switch inspected {
                case .failure(let error): self.setLoading(false,"Import failed"); self.showError(error)
                case .success(let prepared):
                    let review = NSAlert(); review.messageText = "Install " + prepared.record.name + "?"
                    review.informativeText = (prepared.record.dependencies.isEmpty ? "No dependencies declared. A missing manifest does not prove there are no dependencies." : "Required dependencies will also be enabled:\n" + prepared.record.dependencies.joined(separator:"\n") + "\n\nIf any are missing, installation will stop.") + "\n\n" + prepared.record.requirement.title + "\n\nChanges apply on the next server start."
                    review.addButton(withTitle:prepared.record.dependencies.isEmpty ? "Install Mod" : "Install Mod + Dependencies"); review.addButton(withTitle:"Cancel")
                    guard review.runModal() == .alertFirstButtonReturn else { self.setLoading(false,"Installation cancelled"); return }
                    DispatchQueue.global(qos:.userInitiated).async {
                        let installed = Result { try self.library.add([prepared.record]); try self.library.select(prepared.record.id,enabled:true) }
                        DispatchQueue.main.async {
                            self.setLoading(false,"Mod enabled. It will load on the next server start.")
                            if case .failure(let error) = installed { self.status.stringValue = "Mod was not enabled. Any copied files remain in This Server."; self.showError(error) }
                            self.filterRows()
                        }
                    }
                }
            }
        }
    }
    @objc func toggleSelection() {
        guard !loading, isLibrary, stored.indices.contains(table.selectedRow) else { return }
        let mod = stored[table.selectedRow]
        setLoading(true,mod.selected ? "Disabling mod…" : "Checking mod and dependencies…")
        DispatchQueue.global(qos:.userInitiated).async {
            let result = Result { try self.library.select(mod.id,enabled:!mod.selected) }
            DispatchQueue.main.async {
                self.setLoading(false,"Changes apply on the next server start.")
                if case .failure(let error) = result { self.status.stringValue = "Selection unchanged"; self.showError(error) }
                self.filterRows()
            }
        }
    }
    private func setLoading(_ value: Bool, _ message: String) {
        loading = value; status.stringValue = message; source.isEnabled = !value; importButton.isEnabled = !value
        downloadButton.isEnabled = false; selectionButton.isEnabled = false
    }
    private func showError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "Mods need attention"; alert.informativeText = error.localizedDescription; alert.runModal()
    }
}
