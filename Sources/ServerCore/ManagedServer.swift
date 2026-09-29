import Foundation
import CryptoKit

/// Per-profile installation. Never writes into the shared Valve runtime or world directory.
public final class ManagedServer {
    public let paths: Paths
    public init(paths: Paths) { self.paths = paths }
    public var root: URL { paths.root.appendingPathComponent("management/" + (paths.profileID ?? "unselected")) }
    public var runtime: URL { root.appendingPathComponent("runtime") }
    public var executable: URL { runtime.appendingPathComponent("valheim_server/Valheim") }
    public static var availableVersion: String? {
        guard let package, let data = try? Data(contentsOf: package.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
        return manifest.identity
    }
    public var needsUpdate: Bool {
        guard loaderEnabled, let version = Self.availableVersion,
              let installation = try? JSONDecoder().decode(Installation.self, from: Data(contentsOf: root.appendingPathComponent("installation.json"))) else { return false }
        return installation.package != Self.selectionIdentity(version, management: enabled, networking: networkingEnabled, maxPlayers:configuredPlayerLimit) + customModIdentity
    }
    public var enabled: Bool {
        guard let id = paths.profileID, let db = try? Store(paths: paths).load() else { return false }
        return db.managedServers?[id] == true
    }
    public var networkingEnabled: Bool {
        guard let id = paths.profileID, let db = try? Store(paths: paths).load() else { return false }
        return db.networkOptimizations?[id] == true
    }
    public var loaderEnabled: Bool { enabled || networkingEnabled || !customModIdentity.isEmpty }
    private var customModIdentity: String { (try? modLibrary?.selectionIdentity) ?? "" }
    private var modLibrary: ModLibrary? { paths.profileID.flatMap { try? ModLibrary(paths:paths,profileID:$0) } }
    public var hasDeployedCustomMods: Bool {
        guard let receipt = try? JSONDecoder().decode(ModDeploymentReceipt.self,from:Data(contentsOf:runtime.appendingPathComponent("BepInEx/vsm-mod-receipt.json"))) else { return false }
        return !receipt.mods.isEmpty
    }
    private var configuredPlayerLimit: Int? { (try? Store(paths:paths).selected())?.maxPlayers }
    static func selectionIdentity(_ package: String, management: Bool, networking: Bool, maxPlayers: Int? = nil) -> String {
        package + ":network-policy=vanilla-capacity-v1:management=\(management):networking=\(networking):players=\(networking ? maxPlayers.map(String.init) ?? "default" : "default")"
    }
    /// Networking optimization must not change the game's player capacity.
    static func vanillaCapacityConfig(_ existing: String) -> String {
        var lines = existing.components(separatedBy: "\n")
        let section = lines.firstIndex { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "[Player Limit]" }
        guard let section else { return existing + "\n[Player Limit]\nEnable Player Limit Override = false\n" }
        let end = lines.indices.dropFirst(section + 1).first { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
        if let key = (section + 1..<end).first(where: { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("Enable Player Limit Override =") }) {
            lines[key] = "Enable Player Limit Override = false"
        } else { lines.insert("Enable Player Limit Override = false", at: section + 1) }
        return lines.joined(separator: "\n")
    }
    static func capacityConfig(_ existing: String, maxPlayers: Int?) -> String {
        let vanilla = vanillaCapacityConfig(existing)
        guard let maxPlayers else { return vanilla }
        var lines = vanilla.components(separatedBy:"\n")
        let start = lines.firstIndex { $0.trimmingCharacters(in:.whitespaces) == "[Player Limit]" }!
        let end = lines.indices.dropFirst(start + 1).first { lines[$0].trimmingCharacters(in:.whitespaces).hasPrefix("[") } ?? lines.count
        for i in start + 1..<end where lines[i].trimmingCharacters(in:.whitespaces).hasPrefix("Enable Player Limit Override =") { lines[i] = "Enable Player Limit Override = true" }
        if let key = (start + 1..<end).first(where:{ lines[$0].trimmingCharacters(in:.whitespaces).hasPrefix("Max Players =") }) { lines[key] = "Max Players = \(maxPlayers)" }
        else { lines.insert("Max Players = \(maxPlayers)",at:start + 1) }
        return lines.joined(separator:"\n")
    }
    public static var package: URL? {
        if let explicit = ProcessInfo.processInfo.environment["VSM_MANAGEMENT_PACKAGE"] { return URL(fileURLWithPath: explicit) }
        return Bundle.main.resourceURL?.appendingPathComponent("Management")
    }
    public struct Manifest: Codable, Equatable {
        public let version: String
        public let files: [String: String]
        public var identity: String {
            let content = files.keys.sorted().map { $0 + "=" + files[$0]! }.joined(separator: "\n")
            return version + ":" + SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }
    public struct Installation: Codable { let package: String; let build: String }
    public func prepare(package: URL? = ManagedServer.package, management: Bool = true, networking: Bool = false) throws {
        guard let package else { throw MonitorError("Management support is missing from this app. Reinstall the manager.") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: package.appendingPathComponent("manifest.json")))
        let required = ["BepInEx/core/BepInEx.dll", "BepInEx/core/BepInEx.Preloader.dll", "BepInEx/plugins/ManagerRcon/ManagerRcon.dll", "libdoorstop.dylib", "BepInEx/plugins/Jotunn/Jotunn.dll"] + (networking ? ["BepInEx/plugins/NetworkPerformanceSystem/NetworkPerformanceSystem.dll"] : [])
        guard required.allSatisfy({ manifest.files[$0] != nil }) else { throw MonitorError("Management package is incomplete.") }
        for (name, digest) in manifest.files {
            guard !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else { throw MonitorError("Invalid management package path.") }
            let data = try Data(contentsOf: package.appendingPathComponent(name))
            guard SHA256.hash(data: data).map({ String(format:"%02x",$0) }).joined() == digest else { throw MonitorError("Management package verification failed.") }
        }
        guard let build = ServerVersion.installed(paths: paths) else { throw MonitorError("Install the native server first.") }
        let file = root.appendingPathComponent("installation.json")
        let selectedPackage = Self.selectionIdentity(manifest.identity, management: management, networking: networking, maxPlayers:configuredPlayerLimit) + (try modLibrary?.selectionIdentity ?? "")
        let identity = selectedPackage + ":" + build
        if (try? String(contentsOf: root.appendingPathComponent("rejected-installation"))) == identity {
            throw MonitorError("Management startup failed for this build. The previous installation is preserved. Install a corrected manager package before retrying.")
        }
        if let current = try? JSONDecoder().decode(Installation.self, from: Data(contentsOf: file)),
           current.package == selectedPackage, current.build == build,
           FileManager.default.isExecutableFile(atPath: executable.path) { return }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
        let stage = root.appendingPathComponent("stage-" + UUID().uuidString)
        defer { try? fm.removeItem(at: stage) }
        // APFS clone when available, with a normal copy fallback for other volumes.
        if (try? command("/bin/cp", ["-cR", paths.server.path, stage.path]).code) != 0 {
            try? fm.removeItem(at: stage); try fm.copyItem(at: paths.server, to: stage)
        }
        let previous = runtime.appendingPathComponent("BepInEx")
        if fm.fileExists(atPath: previous.path) { try fm.copyItem(at: previous, to: stage.appendingPathComponent("BepInEx")) }
        // Replace managed binaries completely so removed DLLs cannot survive an upgrade.
        for directory in ["BepInEx/core", "BepInEx/plugins/ManagerRcon", "BepInEx/plugins/Jotunn", "BepInEx/plugins/NetworkPerformanceSystem"] {
            let target = stage.appendingPathComponent(directory)
            if fm.fileExists(atPath:target.path) { try fm.removeItem(at:target) }
        }
        for name in manifest.files.keys.sorted() {
            if !management && name.hasPrefix("BepInEx/plugins/ManagerRcon/") { continue }
            if !networking && name.hasPrefix("BepInEx/plugins/NetworkPerformanceSystem/") { continue }
            let target = stage.appendingPathComponent(name)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: package.appendingPathComponent(name), to: target)
        }
        let lib = stage.appendingPathComponent("valheim_server/Data/lib")
        try fm.createDirectory(at: lib, withIntermediateDirectories: true)
        let targetLib = lib.appendingPathComponent("libmono-native.dylib")
        if fm.fileExists(atPath: targetLib.path) { try fm.removeItem(at: targetLib) }
        try fm.copyItem(at: stage.appendingPathComponent("valheim_server/libmono-native.dylib"), to: targetLib)
        if networking {
            let networkConfig = stage.appendingPathComponent("BepInEx/config/MidnightsFX.NetworkPerformanceSystem.cfg")
            let existing = (try? String(contentsOf: networkConfig, encoding: .utf8)) ?? ""
            try atomicWrite(Data(Self.capacityConfig(existing,maxPlayers:configuredPlayerLimit).utf8), to: networkConfig)
        }
        try modLibrary?.deploy(into:stage,previous:runtime)
        let secretFile = root.appendingPathComponent("credential")
        let secret: String
        if let existing = try? String(contentsOf: secretFile), existing.count >= 32 { secret = existing }
        else { secret = UUID().uuidString + UUID().uuidString; try atomicWrite(Data(secret.utf8), to: secretFile) }
        let config = stage.appendingPathComponent("BepInEx/config/io.github.glaciannex.manager.rcon.cfg")
        try atomicWrite(Data("[Connection]\nPassword = \(secret)\nPort = 0\n".utf8), to: config)
        try? fm.removeItem(at: stage.appendingPathComponent("BepInEx/config/manager-rcon-endpoint.json"))
        if let existing = try? Data(contentsOf: file) { try atomicWrite(existing, to: root.appendingPathComponent("previous-installation.json")) }
        let backup = root.appendingPathComponent("previous-runtime")
        if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
        if fm.fileExists(atPath: runtime.path) { try fm.moveItem(at: runtime, to: backup) }
        do { try fm.moveItem(at: stage, to: runtime); try atomicWrite(encode(Installation(package: selectedPackage, build: build)), to: file) }
        catch { if !fm.fileExists(atPath: runtime.path), fm.fileExists(atPath: backup.path) { try? fm.moveItem(at: backup, to: runtime) }; throw error }
    }
    public func rollbackFailedStart() throws {
        let fm = FileManager.default
        if let installation = try? JSONDecoder().decode(Installation.self, from: Data(contentsOf: root.appendingPathComponent("installation.json"))) {
            try atomicWrite(Data((installation.package + ":" + installation.build).utf8), to: root.appendingPathComponent("rejected-installation"))
        }
        let previous = root.appendingPathComponent("previous-runtime")
        guard fm.fileExists(atPath: previous.path) else { return }
        let failed = root.appendingPathComponent("failed-runtime-" + UUID().uuidString)
        try fm.moveItem(at: runtime, to: failed)
        try fm.moveItem(at: previous, to: runtime)
        if let data = try? Data(contentsOf: root.appendingPathComponent("previous-installation.json")) { try atomicWrite(data, to: root.appendingPathComponent("installation.json")) }
    }
    public func connection() throws -> RconClient {
        let endpoint = try JSONDecoder().decode(RconEndpoint.self, from: Data(contentsOf: runtime.appendingPathComponent("BepInEx/config/manager-rcon-endpoint.json")))
        let lifecycle = Lifecycle(paths: paths)
        guard let record = lifecycle.record, record.pid == endpoint.pid, lifecycle.owns(record) else { throw MonitorError("Management endpoint does not belong to this server.") }
        let password = try String(contentsOf: root.appendingPathComponent("credential"))
        return try RconClient(port: endpoint.port, password: password)
    }
    public func moderate(action: String, target: String) throws -> String {
        guard ["kick","ban","unban"].contains(action), !target.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              !target.contains("\n"), !target.contains("\r"), !target.contains("\0") else { throw MonitorError("Enter a valid player name or platform ID.") }
        let client = try connection()
        let response = try client.send(action + " " + target)
        if action != "kick" {
            struct BanInfo: Decodable { let entries: [String] }
            let bans = try JSONDecoder().decode(BanInfo.self,from:Data(client.send("banned").utf8))
            try Store(paths:paths).update { db in
                guard let index = db.profiles.firstIndex(where:{$0.id == paths.profileID}) else { throw MonitorError("Server profile was removed.") }
                db.profiles[index].banned = bans.entries.joined(separator:"\n")
            }
        }
        return response
    }
    public func broadcast(_ text: String) throws {
        let message = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 500, !message.contains("\n"), !message.contains("\r"), !message.contains("\0") else {
            throw MonitorError("Enter one line of text, up to 500 characters.")
        }
        let client = try connection()
        for command in ["say " + message, "showMessage " + message] {
            let response = try client.send(command)
            guard response == "OK" else { throw MonitorError(response) }
        }
    }
    public func warn(minutes: Int, managementOnly: Bool = false, scheduled: Bool = false) throws {
        let client = try connection()
        guard try client.send("health").hasPrefix("OK ManagerRcon") else { throw MonitorError("Management health check failed.") }
        let message = scheduled ? "The server will restart in \(minutes)m for its scheduled restart." : managementOnly ? "The server will restart in \(minutes)m to update its management components." : "The server will restart in \(minutes)m to update to the latest Valheim version."
        _ = try client.send("say " + message); _ = try client.send("showMessage " + message)
    }
}
