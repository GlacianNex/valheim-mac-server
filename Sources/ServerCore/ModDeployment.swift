import Foundation
import CryptoKit

public struct ModFileReceipt: Codable, Equatable {
    public let path: String
    public let digest: String
    public let owner: String
}
public struct ModDeploymentReceipt: Codable {
    public var schema = 1
    public var mods: [StoredMod]
    public var files: [ModFileReceipt]
}
public struct ModInventoryEntry {
    public var modID: String? = nil
    public var enabled: Bool = false
    public let name: String
    public let version: String
    public let status: String
    public let detail: String
    public var playersRequired: Bool = false
}

extension ModLibrary {
    public var selectionIdentity: String {
        get throws {
            let mods = try load().mods.filter(\.selected).sorted { $0.id < $1.id }
            return mods.isEmpty ? "" : ":mods=" + SHA256.hash(data: try encode(mods)).map { String(format:"%02x",$0) }.joined()
        }
    }
    /// Deploy only into a new, unpublished runtime stage. Existing runtime remains recoverable.
    public func deploy(into stage: URL, previous: URL, selection:[StoredMod]? = nil) throws {
        let fm = FileManager.default
        let selected = try selection ?? load().mods.filter(\.selected)
        let receiptName = "BepInEx/vsm-mod-receipt.json"
        let previousReceipt = previous.appendingPathComponent(receiptName)
        var old: ModDeploymentReceipt?
        if fm.fileExists(atPath: previousReceipt.path) {
            old = try JSONDecoder().decode(ModDeploymentReceipt.self, from: Data(contentsOf: previousReceipt))
            guard old?.schema == 1 else { throw MonitorError("Unsupported mod installation receipt.") }
        }
        for item in old?.files ?? [] {
            try Self.validateDestination(item.path)
            if item.path.hasPrefix("BepInEx/config/") { continue }
            let target = stage.appendingPathComponent(item.path)
            if fm.fileExists(atPath: target.path) {
                guard try Self.fileDigest(target) == item.digest else { throw MonitorError("\(item.path) was changed outside the manager. Back up and remove that file before changing mods.") }
                try fm.removeItem(at: target)
            }
        }
        var receipt = ModDeploymentReceipt(mods:selected, files:[])
        var claimed = Set<String>()
        for mod in selected {
            guard mod.requirement != .clientOnly else { throw MonitorError("\(mod.name) is client-only.") }
            let root = try folder(for:mod)
            let files = try Self.files(in:root)
            guard try Self.packageDigest(root) == mod.digest else { throw MonitorError("\(mod.name) cached files changed. Import the original package again.") }
            // Imported folders may wrap the package once or several times.
            var base = root
            while true {
                let entries = try fm.contentsOfDirectory(at:base,includingPropertiesForKeys:[.isDirectoryKey]).filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX" }
                guard entries.count == 1, let entry = entries.first,
                      try entry.resourceValues(forKeys:[.isDirectoryKey]).isDirectory == true,
                      !["bepinex","plugins","patchers","config"].contains(entry.lastPathComponent.lowercased()) else { break }
                base = entry
            }
            // Catalog packages expect the conventional Author-Package directory for assets.
            // Digest-only folders break plugins that locate resources by their package name.
            // Untrusted/local names retain the bounded opaque fallback.
            let slot = mod.package.range(of:"^[A-Za-z0-9_]+-[A-Za-z0-9_]+$",options:.regularExpression) != nil
                ? mod.package : "VSM-" + String(mod.digest.prefix(16))
            for file in files {
                let relative = Self.relative(file,to:base)
                let parts = relative.split(separator:"/").map(String.init)
                guard let first = parts.first, !first.hasPrefix("."), first != "__MACOSX" else { continue }
                if ["manifest.json","readme.md","readme.txt","icon.png","license","license.md","license.txt","changelog.md"].contains(relative.lowercased()) { continue }
                var payload = parts
                if payload.first?.lowercased() == "bepinex" { payload.removeFirst() }
                let area = payload.first?.lowercased() ?? ""
                if ["core","monomod"].contains(area) || ["exe","dylib","sh","bat","command"].contains(file.pathExtension.lowercased()) {
                    throw MonitorError("\(mod.name) contains loader or platform-specific files. This package needs a custom installation; it cannot replace the manager's Mac loader.")
                }
                let destination: String
                if ["plugins","patchers","config"].contains(area) {
                    payload.removeFirst()
                    guard !payload.isEmpty else { continue }
                    destination = "BepInEx/" + area + "/" + (area == "config" ? "" : slot + "/") + payload.joined(separator:"/")
                } else { destination = "BepInEx/plugins/" + slot + "/" + relative }
                try Self.validateDestination(destination)
                guard !["io.github.glaciannex.manager.rcon.cfg","manager-rcon-endpoint.json","vsm-mod-status.json","BepInEx.cfg"].contains(targetName(destination)) else { throw MonitorError("This package attempts to replace manager configuration.") }
                var ancestor = stage.appendingPathComponent(destination).deletingLastPathComponent()
                while ancestor.path != stage.path && ancestor.path.hasPrefix(stage.path + "/") {
                    guard (try? ancestor.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) != true else { throw MonitorError("Mod destination contains a symbolic link.") }
                    ancestor.deleteLastPathComponent()
                }
                guard claimed.insert(destination.lowercased()).inserted else { throw MonitorError("Two mods install the same file: \(destination).") }
                let target = stage.appendingPathComponent(destination)
                if fm.fileExists(atPath:target.path) {
                    guard destination.hasPrefix("BepInEx/config/") else { throw MonitorError("A manually installed file conflicts with \(mod.name): \(destination).") }
                    continue // User configuration always wins over a package's defaults.
                }
                try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                try fm.copyItem(at:file,to:target)
                receipt.files.append(ModFileReceipt(path:destination,digest:try Self.fileDigest(target),owner:mod.id))
            }
        }
        try atomicWrite(encode(receipt),to:stage.appendingPathComponent(receiptName))
    }
    private func targetName(_ path:String) -> String { URL(fileURLWithPath:path).lastPathComponent }
    func validateSelection(_ mods:[StoredMod]) throws {
        let stage = directory.appendingPathComponent(".validate-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:stage) }
        try deploy(into:stage,previous:stage.appendingPathComponent("absent"),selection:mods.filter(\.selected))
    }
    static func relative(_ file:URL,to root:URL) -> String {
        String(file.resolvingSymlinksInPath().path.dropFirst(root.resolvingSymlinksInPath().path.count + 1))
    }
    static func packageDigest(_ root:URL) throws -> String {
        var hash = SHA256()
        let files = try Self.files(in:root).filter { !$0.lastPathComponent.hasPrefix("._") && !$0.path.contains("/__MACOSX/") }
        for file in files.sorted(by:{$0.path < $1.path}) {
            hash.update(data:Data(("/" + Self.relative(file,to:root)).utf8)); hash.update(data:Data([0]))
            let handle = try FileHandle(forReadingFrom:file); defer { try? handle.close() }
            while let data = try handle.read(upToCount:65536), !data.isEmpty { hash.update(data:data) }
        }
        return hash.finalize().map { String(format:"%02x",$0) }.joined()
    }
    static func validateDestination(_ path:String) throws {
        guard ["BepInEx/plugins/","BepInEx/patchers/","BepInEx/config/"].contains(where:path.hasPrefix),
              !path.contains("\\"), !path.contains(":"), !path.split(separator:"/",omittingEmptySubsequences:false).contains(where:{ $0 == ".." || $0 == "." || $0.isEmpty }) else { throw MonitorError("Invalid mod deployment path.") }
    }
    static func fileDigest(_ file:URL) throws -> String {
        let values = try file.resourceValues(forKeys:[.isSymbolicLinkKey,.isRegularFileKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else { throw MonitorError("Invalid mod file.") }
        return SHA256.hash(data:try Data(contentsOf:file)).map { String(format:"%02x",$0) }.joined()
    }
    /// Disk inventory includes manually copied DLLs. A file on disk is not proof that it loaded.
    public func inventory(runtime:URL, running:Bool, live:ModRuntimeStatus? = nil) throws -> [ModInventoryEntry] {
        let manifest = try load()
        let receipt = try? JSONDecoder().decode(ModDeploymentReceipt.self,from:Data(contentsOf:runtime.appendingPathComponent("BepInEx/vsm-mod-receipt.json")))
        var result: [ModInventoryEntry] = []
        for mod in manifest.mods {
            let installed = receipt?.mods.contains(where:{$0.id == mod.id}) == true
            let missing = receipt?.files.filter { $0.owner == mod.id && !FileManager.default.fileExists(atPath:runtime.appendingPathComponent($0.path).path) } ?? []
            var status = !running ? (mod.selected ? "Enabled" : "Disabled") : !installed ? (mod.selected ? "Pending restart" : "Disabled") : "Checking…"
            let ownedPaths = Set(receipt?.files.filter { $0.owner == mod.id }.map { runtime.appendingPathComponent($0.path).resolvingSymlinksInPath().path } ?? [])
            let loaded = live?.mods.filter { ownedPaths.contains(URL(fileURLWithPath:$0.path).resolvingSymlinksInPath().path) } ?? []
            if running && installed && !loaded.isEmpty {
                // A plugin can ship optional support libraries that are never referenced in a dedicated server.
                // Their absence is not a plugin failure; a library-only package still requires assembly evidence.
                let confirmed = loaded.filter { $0.kind != "library" || !$0.status.hasPrefix("Awaiting ") }
                status = confirmed.contains(where:{$0.status != "Loaded" && !$0.status.hasPrefix("Awaiting ")}) ? "Failed" : confirmed.isEmpty || confirmed.contains(where:{$0.status.hasPrefix("Awaiting ")}) ? "Checking…" : "Running"
            }
            if status == "Running", live?.unattributedErrors?.isEmpty == false { status = "Check logs" }
            if running && installed && !missing.isEmpty { status = "Failed" }
            let errors = loaded.filter { !$0.error.isEmpty }.map { $0.name + ": " + $0.error }.joined(separator:"\n")
            let playerRequirement = ModPlayerEvidence.installed(mod,in:manifest.mods)
            let explanation = !errors.isEmpty ? errors : mod.selected != installed ? "Changes apply on the next server start." : status == "Running" ? "Loading confirmed by this server's current logs." : status == "Check logs" ? "Server logs contain compatibility errors that could not be attributed to a specific mod.\n" + (live?.unattributedErrors?.joined(separator:"\n") ?? "") : status == "Failed" ? "A required mod file is missing or failed to load." : running ? "Waiting for loading evidence from the current server session." : "Changes apply on the next server start."
            result.append(ModInventoryEntry(modID:mod.id,enabled:mod.selected,name:mod.name,version:mod.version ?? "Unknown",status:status,detail:explanation + "\n" + playerRequirement.title,playersRequired:playerRequirement == .playersRequired))
        }
        // Loading the root DLL is not enough when a required installed dependency failed.
        // Use the deployed receipt, not pending selections for the next restart.
        if running, let receipt {
            let indices = Dictionary(manifest.mods.enumerated().map { ($0.element.id,$0.offset) },uniquingKeysWith: { first,_ in first })
            for _ in 0..<receipt.mods.count {
                var changed = false
                for mod in receipt.mods {
                    guard let index = indices[mod.id], ["Running","Checking…","Check logs"].contains(result[index].status) else { continue }
                    let failed = mod.dependencies.compactMap { pin -> String? in
                        guard !ModCompatibility.supplies(pin), let dependency = ModCompatibility.dependency(pin,in:receipt.mods),
                              let dependencyIndex = indices[dependency.id], result[dependencyIndex].status == "Failed" else { return nil }
                        return dependency.name
                    }
                    guard !failed.isEmpty else { continue }
                    let entry = result[index]
                    result[index] = ModInventoryEntry(modID:entry.modID,enabled:entry.enabled,name:entry.name,version:entry.version,status:"Failed",
                        detail:"Required dependency failed: " + failed.joined(separator:", ") + "\n" + entry.detail,playersRequired:entry.playersRequired)
                    changed = true
                }
                if !changed { break }
            }
        }
        let owned = Set(receipt?.files.map(\.path) ?? [])
        for area in ["plugins","patchers"] {
            let root = runtime.appendingPathComponent("BepInEx/" + area)
            guard FileManager.default.fileExists(atPath:root.path) else { continue }
            for file in try Self.files(in:root) where file.pathExtension.lowercased() == "dll" {
                let relative = Self.relative(file,to:runtime)
                guard !owned.contains(relative), !["ManagerRcon","Jotunn","NetworkPerformanceSystem"].contains(where:{relative.hasPrefix("BepInEx/plugins/" + $0 + "/")}) else { continue }
                let observed = live?.mods.filter { URL(fileURLWithPath:$0.path).resolvingSymlinksInPath().path == file.resolvingSymlinksInPath().path } ?? []
                if observed.isEmpty {
                    result.append(ModInventoryEntry(name:file.deletingPathExtension().lastPathComponent,version:"Unknown",status:"Unmanaged",detail:relative + "\nManually installed file; may be a plugin or supporting library."))
                } else {
                    for entry in observed { result.append(ModInventoryEntry(name:entry.name,version:entry.version,status:running ? (entry.status == "Loaded" ? "Running" : entry.status.hasPrefix("Awaiting ") ? "Checking…" : "Failed") : "Enabled",detail:entry.guid + "\n" + relative + "\n" + entry.error)) }
                }
            }
        }
        if running {
            result = result.map { entry in
                guard let id = entry.modID else { return entry }
                let deployed = receipt?.mods.contains { $0.id == id } == true
                guard deployed != entry.enabled else { return entry }
                let pending = entry.enabled ? "Enables on restart" : "Disables on restart"
                let status = entry.status == "Failed" ? "Failed · " + pending : pending
                return ModInventoryEntry(modID:id,enabled:entry.enabled,name:entry.name,version:entry.version,status:status,
                    detail:pending + ". Cancelling a restart does not undo this selection.\nCurrent session: " + entry.status + "\n" + entry.detail,playersRequired:entry.playersRequired)
            }
        }
        return result
    }
}

public struct ModRuntimeStatus: Decodable {
    public struct Entry: Decodable {
        public let guid: String
        public let name: String
        public let version: String
        public let path: String
        public var status: String
        public var error: String
        public let kind: String?
        public let patcherTypes: [String]?
    }
    public let pid: Int32
    public let updated: String
    public var mods: [Entry]
    public var unattributedErrors: [String]?
    public static func read(paths:Paths, runtime:URL) -> ModRuntimeStatus? {
        let lifecycle = Lifecycle(paths:paths)
        guard let record = lifecycle.record, lifecycle.owns(record),
              let file = try? FileHandle(forReadingFrom:URL(fileURLWithPath:record.log)) else { return nil }
        defer { try? file.close() }
        guard let end = try? file.seekToEnd() else { return nil }
        // Initialization exceptions can precede the management plugin and disappear from the tail.
        var startup = Data()
        if end > 1_048_576 {
            try? file.seek(toOffset:0)
            startup = (try? file.read(upToCount:524_288)) ?? Data()
        }
        try? file.seek(toOffset:end > 1_048_576 ? end - 1_048_576 : 0)
        guard let data = try? file.readToEnd() else { return nil }
        return parseLog(String(decoding:startup,as:UTF8.self) + "\n" + String(decoding:data,as:UTF8.self),pid:record.pid)
    }
    public static func parseLog(_ text:String,pid:Int32,now:Date = Date()) -> ModRuntimeStatus? {
        for line in text.components(separatedBy:"\n").reversed() {
            guard let marker = line.range(of:"VSM mod status: "),
                  var value = try? JSONDecoder().decode(Self.self,from:Data(line[marker.upperBound...].utf8)), value.pid == pid,
                  let date = ISO8601DateFormatter.fractional.date(from:value.updated), abs(date.timeIntervalSince(now)) < 20 else { continue }
            let blocks = errorBlocks(text)
            var attributed = Set<String>()
            for index in value.mods.indices {
                let entry = value.mods[index]
                if entry.kind == "patcher" {
                    let identity = NSRegularExpression.escapedPattern(for:entry.name + " " + entry.version)
                    let registered = text.range(of:#"Loaded [1-9][0-9]* patcher methods? from \["# + identity + #"\]"#,options:.regularExpression) != nil
                    let finished = text.contains("[Message:   BepInEx] Preloader finished")
                    if registered && finished { value.mods[index].status = "Loaded" }
                    if let failure = blocks.first(where: { block in
                        (entry.patcherTypes ?? []).contains { type in block.contains(type) }
                    }) {
                        attributed.insert(failure)
                        value.mods[index].status = "Failed"; value.mods[index].error = String(failure.prefix(2000))
                    }
                }
                let stem = URL(fileURLWithPath:entry.path).deletingPathExtension().lastPathComponent
                let names = Set([stem,entry.name]).filter { $0.count >= 3 }
                if let block = blocks.first(where: { block in
                    names.contains { name in
                        let escaped = NSRegularExpression.escapedPattern(for:name)
                        return block.range(of:#"(?i)(?:\bat |\bvoid |\bstatic |\btype initializer for '?)"# + escaped + #"[.+:]|\[\s*(?:Error|Fatal)\s*:\s*"# + escaped + #"\s*\]"#,options:.regularExpression) != nil
                    }
                }) {
                    attributed.insert(block)
                    value.mods[index].status = "Failed"
                    value.mods[index].error = String(block.prefix(2000))
                }
            }
            value.unattributedErrors = blocks.filter { block in
                !attributed.contains(block) && block.range(of:#"\b(?:MissingMethod|MissingField|TypeLoad|TypeInitialization|Harmony)Exception:"#,options:.regularExpression) != nil
            }.map { String($0.prefix(2000)) }
            return value
        }
        return nil
    }
    private static func errorBlocks(_ text:String) -> [String] {
        let lines = text.components(separatedBy:"\n")
        var result:[String] = []
        for index in lines.indices {
            let line = lines[index]
            guard !line.contains("VSM mod status:"), line.range(of:#"\b[A-Za-z]*Exception:|\[\s*(?:Error|Fatal)\s*:"#,options:.regularExpression) != nil else { continue }
            var block = [line]
            for next in lines.dropFirst(index + 1).prefix(30) {
                if next.isEmpty || next.contains("VSM mod status:") { break }
                block.append(next)
            }
            result.append(block.joined(separator:"\n"))
        }
        return result
    }

}
private extension ISO8601DateFormatter {
    static var fractional: ISO8601DateFormatter { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime,.withFractionalSeconds]; return f }
}
