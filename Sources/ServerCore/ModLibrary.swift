import Foundation
import CryptoKit

public struct StoredMod: Codable, Equatable, Identifiable {
    public var id: String
    public var source: ModSource
    public var package: String
    public var name: String
    public var version: String?
    public var digest: String
    public var requirement: ModPlayerRequirement
    public var dependencies: [String]
    public var description: String
    public var page: URL?
    public var selected: Bool
}
public struct ModManifest: Codable, Equatable {
    public var schema = 1
    public var mods: [StoredMod] = []
    public init() {}
}
public struct ImportedMod {
    public let record: StoredMod
    public let folder: URL
}

/// Preparation only: this store never changes a running server or its shared runtime.
public final class ModLibrary {
    public let directory: URL
    public let cache: URL
    public init(paths: Paths, profileID: String) throws {
        guard UUID(uuidString: profileID) != nil else { throw MonitorError("Invalid server identifier for mods.") }
        directory = paths.root.appendingPathComponent("mods/servers/" + profileID)
        cache = paths.root.appendingPathComponent("mods/packages")
    }
    private final class EvidenceCache: @unchecked Sendable {
        let lock = NSLock()
        var values: [String:ModPlayerRequirement] = [:]
        func requirement(key:String,read:() -> ModPlayerRequirement) -> ModPlayerRequirement {
            lock.lock(); defer { lock.unlock() }
            if let value = values[key] { return value }
            let value = read()
            if values.count >= 1000 { values.removeAll() }
            values[key] = value
            return value
        }
    }
    private static let evidenceCache = EvidenceCache()
    public func load() throws -> ModManifest {
        let url = directory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return ModManifest() }
        var result = try JSONDecoder().decode(ModManifest.self, from: Data(contentsOf: url))
        guard result.schema == 1 else { throw MonitorError("This mod library was created by a newer manager.") }
        for index in result.mods.indices where result.mods[index].requirement == .unknown {
            let mod = result.mods[index]
            result.mods[index].requirement = Self.evidenceCache.requirement(key:cache.path + mod.digest + mod.description) {
                ModPlayerEvidence.read(description:mod.description,readme:(try? self.readme(for:mod)) ?? "").requirement
            }
        }
        return result
    }
    private func change(_ body: (inout ModManifest) throws -> Void) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try withLock(directory.appendingPathComponent("mods.lock")) {
            var manifest = try load(); try body(&manifest)
            try atomicWrite(encode(manifest), to: directory.appendingPathComponent("manifest.json"))
        }
    }
    public func add(_ records: [StoredMod]) throws {
        try change { manifest in
            for record in records {
                guard ModCompatibility.bundled[record.package] == nil else { throw MonitorError("\(record.name) is supplied by the manager. Use the controls at the top of Server Management.") }
                guard !manifest.mods.contains(where: { $0.source == record.source && $0.package == record.package && $0.version == record.version && $0.digest != record.digest }) else {
                    throw MonitorError("\(record.name) already has different files for the same version. Keep the existing copy or remove it before importing this one.")
                }
                if !manifest.mods.contains(where: { $0.id == record.id }) { manifest.mods.append(record) }
            }
        }
    }
    public func select(_ id: String, enabled: Bool) throws {
        try change { manifest in
            guard let index = manifest.mods.firstIndex(where: { $0.id == id }) else { throw MonitorError("Mod not found.") }
            func dependency(_ pin:String) throws -> Int {
                guard let found = ModCompatibility.dependency(pin, in: manifest.mods).flatMap({ candidate in manifest.mods.firstIndex(where: { $0.id == candidate.id }) }) else { throw MonitorError("Missing dependency: \(pin). Download or import it first.") }
                return found
            }
            if enabled {
                var visiting = Set<Int>(), chosen = Set<Int>()
                func visit(_ i:Int) throws {
                    if chosen.contains(i) { return }
                    guard visiting.insert(i).inserted else { throw MonitorError("Circular mod dependency.") }
                    guard manifest.mods[i].requirement != .clientOnly else { throw MonitorError("\(manifest.mods[i].name) is client-only.") }
                    for pin in manifest.mods[i].dependencies where !ModCompatibility.supplies(pin) { try visit(dependency(pin)) }
                    visiting.remove(i); chosen.insert(i)
                }
                try visit(index)
                for i in chosen {
                    guard !chosen.contains(where:{ $0 != i && manifest.mods[$0].package == manifest.mods[i].package }) else { throw MonitorError("Conflicting mod dependency versions.") }
                    for j in manifest.mods.indices where manifest.mods[j].package == manifest.mods[i].package { manifest.mods[j].selected = false }
                }
                for i in chosen { manifest.mods[i].selected = true }
                for item in manifest.mods where item.selected {
                    for pin in item.dependencies where !ModCompatibility.supplies(pin) {
                        guard manifest.mods[try dependency(pin)].selected else { throw MonitorError("This version conflicts with a dependency of \(item.name).") }
                    }
                }
            } else {
                let target = manifest.mods[index]
                let dependants = manifest.mods.filter { $0.selected && $0.dependencies.contains(where: { ModCompatibility.satisfies(package: target.package, version: target.version, pin: $0) }) }.map(\.name)
                guard dependants.isEmpty else { throw MonitorError("Required by: " + dependants.joined(separator:", ") + ". Disable those mods first.") }
                manifest.mods[index].selected = false
            }
            if enabled { try validateSelection(manifest.mods) }
        }
    }
    public func remove(_ id: String) throws {
        try change { manifest in
            guard let item = manifest.mods.first(where:{$0.id == id}) else { return }
            guard !item.selected else { throw MonitorError("Disable this mod before removing it.") }
            let target = item
            guard !manifest.mods.contains(where:{$0.selected && $0.dependencies.contains(where: { ModCompatibility.satisfies(package: target.package, version: target.version, pin: $0) })}) else { throw MonitorError("An enabled mod requires this dependency.") }
            manifest.mods.removeAll { $0.id == id }
        }
        // Cache stays recoverable and may be used by another server.
    }
    public func folder(for record: StoredMod) throws -> URL {
        guard record.digest.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else { throw MonitorError("Invalid mod checksum.") }
        return cache.appendingPathComponent(record.digest)
    }
    public func prepareImport(_ source: URL, from provider: ModSource = .local, package: ModPackage? = nil, version: ModVersion? = nil) throws -> ImportedMod {
        let fm = FileManager.default
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let staging = cache.appendingPathComponent(".import-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        if source.pathExtension.lowercased() == "zip" {
            let listing = try command("/usr/bin/unzip", ["-Z1", source.path])
            let names = listing.output.split(separator: "\n")
            guard listing.code == 0, !names.isEmpty, names.count <= 20_000 else { throw MonitorError("Cannot read this ZIP, or it contains too many files.") }
            var archivePaths = Set<String>()
            for name in names {
                let normalized = String(name).replacingOccurrences(of: "\\", with: "/")
                guard !normalized.hasPrefix("/"), !normalized.contains(":"), !normalized.split(separator: "/").contains("..") else { throw MonitorError("The mod ZIP contains an unsafe path.") }
                let key = normalized.split(separator: "/").filter { $0 != "." }.joined(separator: "/").lowercased()
                guard !key.isEmpty, archivePaths.insert(key).inserted else { throw MonitorError("The mod ZIP contains duplicate paths.") }
            }
            let details = try command("/usr/bin/zipinfo", ["-l", source.path])
            guard details.code == 0 else { throw MonitorError("Cannot inspect the mod ZIP.") }
            if details.output.split(separator: "\n").contains(where: { $0.first == "?" }) {
                let attributes = try command("/usr/bin/zipinfo", ["-v", source.path])
                guard attributes.code == 0 else { throw MonitorError("Cannot inspect ZIP file types.") }
                let expression = try NSRegularExpression(pattern: #"Unix file attributes \(([0-7]+) octal\)"#)
                for match in expression.matches(in: attributes.output, range: NSRange(attributes.output.startIndex..., in: attributes.output)) {
                    guard let range = Range(match.range(at: 1), in: attributes.output), let mode = UInt32(attributes.output[range], radix: 8), [UInt32(0), 0o100000, 0o040000].contains(mode & 0o170000) else {
                        throw MonitorError("Mod archives cannot contain links or special files.")
                    }
                }
            }
            var bytes: UInt64 = 0
            for line in details.output.split(separator: "\n") {
                let columns = line.split(whereSeparator: \.isWhitespace)
                if let mode = columns.first, (7...10).contains(mode.count), "-dl?bcps".contains(mode.prefix(1)) {
                    guard mode.first == "-" || mode.first == "d" || mode.first == "?" else { throw MonitorError("Mod archives cannot contain links or special files.") }
                    guard columns.count > 3, let size = UInt64(columns[3]), size <= 2_000_000_000, bytes <= 2_000_000_000 - size else { throw MonitorError("Expanded mod size exceeds 2 GB.") }
                    bytes += size
                }
            }
            try checkCommand("/usr/bin/ditto", ["-x", "-k", source.path, staging.path])
            // Some Windows archives retain backslashes as literal filenames on macOS.
            // Normalize only after validating every archive path, and never overwrite another entry.
            let extracted = try Self.files(in: staging).sorted { $0.path.count < $1.path.count }
            for file in extracted where Self.relative(file, to: staging).contains("\\") {
                let relative = Self.relative(file, to: staging).replacingOccurrences(of: "\\", with: "/")
                let target = staging.appendingPathComponent(relative)
                if file.lastPathComponent.hasSuffix("\\") {
                    guard (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize == 0 else { throw MonitorError("A Windows directory entry contains file data.") }
                    try fm.removeItem(at: file)
                    try fm.createDirectory(at: target, withIntermediateDirectories: true)
                    continue
                }
                guard !fm.fileExists(atPath: target.path) else { throw MonitorError("The mod ZIP contains conflicting Windows paths.") }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: file, to: target)
            }
        } else {
            _ = try Self.files(in: source)
            let directory = try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            guard directory || source.pathExtension.lowercased() == "dll" else { throw MonitorError("Choose a mod ZIP, plugin folder, or DLL.") }
            try fm.copyItem(at: source, to: staging.appendingPathComponent(source.lastPathComponent))
        }
        let files = try Self.files(in: staging).filter { !$0.lastPathComponent.hasPrefix("._") && !$0.path.contains("/__MACOSX/") }
        let manifests = files.filter { $0.lastPathComponent.lowercased() == "manifest.json" }
        guard manifests.count <= 1 else { throw MonitorError("This archive contains multiple mods. Import each package separately.") }
        var metadata: [String: Any] = [:]
        if let manifest = manifests.first {
            metadata = (try JSONSerialization.jsonObject(with: Data(contentsOf: manifest))) as? [String: Any] ?? [:]
        }
        let dependencies = metadata["dependencies"] as? [String] ?? []
        guard files.contains(where: { $0.pathExtension.lowercased() == "dll" }) || !dependencies.isEmpty else {
            throw MonitorError("No plugin DLLs or modpack dependencies were found in this package.")
        }
        if let package, let version {
            guard metadata["name"] as? String == package.name, metadata["version_number"] as? String == version.version_number else {
                throw MonitorError("The downloaded package identity or version does not match \(package.name) \(version.version_number).")
            }
        }
        let digest = try Self.packageDigest(staging)
        let name = package?.name ?? metadata["name"] as? String ?? source.deletingPathExtension().lastPathComponent
        let modVersion = version?.version_number ?? metadata["version_number"] as? String
        var localIdentity = modVersion == nil ? name + ":" + digest : name
        if let modVersion {
            let filename = source.deletingPathExtension().lastPathComponent
            let suffix = "-" + name + "-" + modVersion
            if filename.hasSuffix(suffix) {
                let owner = String(filename.dropLast(suffix.count))
                if owner.range(of:#"^[A-Za-z0-9_]+$"#,options:.regularExpression) != nil { localIdentity = owner + "-" + name }
            }
        }
        let authorReadme = files.filter { ["readme.md", "readme.txt"].contains($0.lastPathComponent.lowercased()) }.first.flatMap { url -> String? in
            guard let size = try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize, size <= 2_097_152 else { return nil }
            return try? String(contentsOf:url,encoding:.utf8)
        } ?? ""
        let playerEvidence = ModPlayerEvidence.read(declared:package?.requirement ?? .unknown,
            description:version?.description ?? metadata["description"] as? String ?? "", readme:authorReadme)
        let record = StoredMod(id: provider.rawValue + ":" + digest, source: provider,
            package: package?.full_name ?? localIdentity, name: name, version: modVersion,
            digest: digest, requirement: playerEvidence.requirement, dependencies: version?.dependencies ?? dependencies,
            description: version?.description ?? metadata["description"] as? String ?? "Custom import", page: package?.package_url, selected: false)
        let destination = cache.appendingPathComponent(digest)
        try withLock(cache.appendingPathComponent("cache.lock")) {
            if !fm.fileExists(atPath: destination.path) { try fm.moveItem(at: staging, to: destination) }
        }
        return ImportedMod(record: record, folder: destination)
    }
    public func readme(for record: StoredMod) throws -> String? {
        let candidates = try Self.files(in: folder(for: record)).filter { ["readme.md", "readme.txt", "readme"].contains($0.lastPathComponent.lowercased()) }.sorted { $0.path.count < $1.path.count }
        guard let url = candidates.first else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max <= 2_000_000 else { throw MonitorError("README exceeds 2 MB.") }
        return try String(contentsOf: url, encoding: .utf8)
    }
    static func files(in root: URL) throws -> [URL] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        var failure: Error?
        let entries = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys), errorHandler: { _, error in failure = error; return false })
        var files: [URL] = [], bytes = 0, count = 0
        func inspect(_ url: URL) throws {
            count += 1
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true, values.isDirectory == true || values.isRegularFile == true else { throw MonitorError("Mods cannot contain links or special files.") }
            if values.isRegularFile == true {
                bytes += values.fileSize ?? 0; files.append(url)
            }
            guard count <= 20_000, bytes <= 2_000_000_000 else { throw MonitorError("The mod exceeds the 2 GB or 20,000-file import limit.") }
        }
        try inspect(root)
        if (try root.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
            guard let entries else { throw MonitorError("Cannot read the mod folder.") }
            for case let url as URL in entries { try inspect(url) }
        }
        if let failure { throw failure }
        return files
    }
}

extension ModLibrary {
    public func download(_ selection: [ResolvedMod], source: ModSource) async throws -> [StoredMod] {
        var records: [StoredMod] = []
        for entry in selection {
            let url = entry.version.download_url
            guard url.scheme == "https", url.user == nil, url.password == nil else { throw MonitorError("This mod has an unsupported download address.") }
            var request = URLRequest(url: url); request.timeoutInterval = 180
            request.setValue("ValheimServerManager/2.0-development", forHTTPHeaderField: "User-Agent")
            let (temporary, response) = try await URLSession.shared.download(for: request)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MonitorError("\(entry.package.name) could not be downloaded. Use View on Host, then Import Mod… if a manual download is required.") }
            guard (try temporary.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max <= 512_000_000 else { throw MonitorError("The mod download exceeds 512 MB.") }
            let zip = temporary.appendingPathExtension("zip")
            try FileManager.default.moveItem(at: temporary, to: zip)
            defer { try? FileManager.default.removeItem(at: zip) }
            records.append(try prepareImport(zip, from: source, package: entry.package, version: entry.version).record)
        }
        try add(records)
        return records
    }
}
