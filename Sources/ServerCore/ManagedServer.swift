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
        guard enabled, let version = Self.availableVersion,
              let installation = try? JSONDecoder().decode(Installation.self, from: Data(contentsOf: root.appendingPathComponent("installation.json"))) else { return false }
        return installation.package != version
    }
    public var enabled: Bool {
        guard let id = paths.profileID, let db = try? Store(paths: paths).load() else { return false }
        return db.managedServers?[id] == true
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
    public func prepare(package: URL? = ManagedServer.package) throws {
        guard let package else { throw MonitorError("Management support is missing from this app. Reinstall the manager.") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: package.appendingPathComponent("manifest.json")))
        let required = ["BepInEx/core/BepInEx.dll", "BepInEx/core/BepInEx.Preloader.dll", "BepInEx/plugins/ManagerRcon/ManagerRcon.dll", "libdoorstop.dylib"]
        guard required.allSatisfy({ manifest.files[$0] != nil }) else { throw MonitorError("Management package is incomplete.") }
        for (name, digest) in manifest.files {
            guard !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else { throw MonitorError("Invalid management package path.") }
            let data = try Data(contentsOf: package.appendingPathComponent(name))
            guard SHA256.hash(data: data).map({ String(format:"%02x",$0) }).joined() == digest else { throw MonitorError("Management package verification failed.") }
        }
        guard let build = ServerVersion.installed(paths: paths) else { throw MonitorError("Install the native server first.") }
        let file = root.appendingPathComponent("installation.json")
        let identity = manifest.identity + ":" + build
        if (try? String(contentsOf: root.appendingPathComponent("rejected-installation"))) == identity {
            throw MonitorError("Management startup failed for this build. The previous installation is preserved. Install a corrected manager package before retrying.")
        }
        if let current = try? JSONDecoder().decode(Installation.self, from: Data(contentsOf: file)),
           current.package == manifest.identity, current.build == build,
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
        for directory in ["BepInEx/core", "BepInEx/plugins/ManagerRcon"] {
            let target = stage.appendingPathComponent(directory)
            if fm.fileExists(atPath:target.path) { try fm.removeItem(at:target) }
        }
        for name in manifest.files.keys.sorted() {
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
        do { try fm.moveItem(at: stage, to: runtime); try atomicWrite(encode(Installation(package: manifest.identity, build: build)), to: file) }
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
    public func warn(minutes: Int, managementOnly: Bool = false, scheduled: Bool = false) throws {
        let client = try connection()
        guard try client.send("health").hasPrefix("OK ManagerRcon") else { throw MonitorError("Management health check failed.") }
        let message = scheduled ? "The server will restart in \(minutes)m for its scheduled restart." : managementOnly ? "The server will restart in \(minutes)m to update its management components." : "The server will restart in \(minutes)m to update to the latest Valheim version."
        _ = try client.send("say " + message); _ = try client.send("showMessage " + message)
    }
}
