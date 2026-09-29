import Foundation

public enum ModSource: String, Codable, CaseIterable {
    case thunderstore, hexium, local
    public var title: String { rawValue.capitalized }
    public var catalogURL: URL? {
        switch self {
        case .thunderstore: return URL(string: "https://thunderstore.io/c/valheim/api/v1/package/")
        case .hexium: return URL(string: "https://valheim.hexium.gg/api/v1/package/")
        case .local: return nil
        }
    }
}
public enum ModPlayerRequirement: String, Codable {
    case serverOnly, playersRequired, clientOnly, unknown
    public var title: String {
        switch self {
        case .serverOnly: return "Server only (author declared)"
        case .playersRequired: return "Players must install (author declared)"
        case .clientOnly: return "Client only — not a server mod"
        case .unknown: return "Player requirements unknown"
        }
    }
    public static func categories(_ values: [String]) -> Self {
        let tags = Set(values.map { $0.lowercased().replacingOccurrences(of: "_", with: "-") })
        // Server-side alone does not prove that clients do not also need the mod.
        if tags.contains("client-only") { return .clientOnly }
        if tags.contains("server-only") { return .serverOnly }
        if tags.contains("both") || tags.contains("client-and-server") || tags.contains("client & server") { return .playersRequired }
        return .unknown
    }
}
public struct ModVersion: Codable, Equatable {
    public var version_number: String
    public var description: String
    public var download_url: URL
    public var dependencies: [String]
    public var downloads: Int
    public var date_created: String
    public var is_active: Bool
    public var file_size: Int?
}
public struct ModPackage: Codable, Equatable {
    public var name: String
    public var full_name: String
    public var owner: String
    public var package_url: URL
    public var rating_score: Int
    public var is_deprecated: Bool
    public var categories: [String]
    public var versions: [ModVersion]
    public var requirement: ModPlayerRequirement { .categories(categories) }
    public var totalDownloads: Int { versions.reduce(0) { $0 + $1.downloads } }
    public var latest: ModVersion? { versions.first(where: { $0.is_active }) }
    public func matches(_ query: String) -> Bool {
        let text = ([name, owner, full_name, latest?.description ?? ""] + categories).joined(separator: " ")
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { text.localizedCaseInsensitiveContains(String($0)) }
    }
}
public struct ResolvedMod: Equatable {
    public let package: ModPackage
    public let version: ModVersion
}
public enum ModCatalog {
    public static func fetch(_ source: ModSource) async throws -> [ModPackage] {
        guard let url = source.catalogURL else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("ValheimServerManager/2.0-development", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw MonitorError("\(source.title) could not be reached. Your imported mods remain available. Retry later or import a downloaded ZIP.")
        }
        return try JSONDecoder().decode([ModPackage].self, from: data)
    }
    /// Keep the selected root version; merge dependency minimums and reuse satisfying installed versions.
    public static func resolve(package: String, version: String, in catalog: [ModPackage], installed: [StoredMod] = []) throws -> [ResolvedMod] {
        let index = Dictionary(catalog.map { ($0.full_name, $0) }, uniquingKeysWith: { first, _ in first })
        enum RetryResolution: Error { case newerRequirement }
        var requirements: [String: String] = [:]
        var visiting = Set<String>(), selected: [String: String] = [:], ordered: [ResolvedMod] = []
        func visit(_ name: String, _ requested: String) throws {
            var pin = requested
            if let previous = requirements[name] {
                if ModCompatibility.satisfies(package: name, version: previous, pin: name + "-" + requested) { pin = previous }
                else if !ModCompatibility.satisfies(package: name, version: requested, pin: name + "-" + previous) {
                    throw MonitorError("Incompatible dependency versions for \(name): \(previous) and \(requested).")
                }
            }
            requirements[name] = pin
            if name == package && pin != version { throw MonitorError("A dependency requires a different version of the selected mod.") }
            if visiting.contains(name) { throw MonitorError("Circular dependency involving \(name).") }
            if let chosen = selected[name] {
                guard ModCompatibility.satisfies(package: name, version: chosen, pin: name + "-" + pin) else { throw RetryResolution.newerRequirement }
                return
            }
            if ModCompatibility.supplies(name + "-" + pin) { return }
            if let bundled = ModCompatibility.bundled[name], ["BepInEx", "Jötunn"].contains(bundled.name) {
                throw MonitorError("This mod requires \(name) \(pin), newer than the dependency version supported by this manager (\(bundled.version)). Update the manager before installing this mod.")
            }
            if name != package, let existing = ModCompatibility.dependency(name + "-" + pin, in: installed) {
                guard visiting.insert(name).inserted else { throw MonitorError("Circular dependency involving \(name).") }
                for dependency in existing.dependencies {
                    guard let parts = ModCompatibility.split(dependency) else { throw MonitorError("Invalid dependency: \(dependency).") }
                    try visit(parts.name, parts.version)
                }
                visiting.remove(name); selected[name] = existing.version
                return
            }
            if visiting.contains(name) { throw MonitorError("Circular dependency involving \(name).") }
            guard let candidate = index[name] else {
                throw MonitorError("Missing dependency: \(name) \(pin). Import that version or choose another mod version.")
            }
            // Requirements are minimums. Fresh installs should receive maintenance fixes,
            // while explicit root selections and already-satisfied installations stay pinned.
            let available = candidate.versions.filter { entry in
                guard entry.is_active else { return false }
                if name == package { return entry.version_number == pin }
                if entry.version_number == pin { return true }
                guard ModCompatibility.satisfies(package:name,version:entry.version_number,pin:name + "-" + pin) else { return false }
                let required = pin.split(separator:"."), actual = entry.version_number.split(separator:".")
                return required[0] == actual[0] && (required[0] != "0" || required[1] == actual[1])
            }.sorted { $0.version_number.compare($1.version_number,options:.numeric) == .orderedDescending }
            guard !available.isEmpty else {
                throw MonitorError("Missing dependency: \(name) \(pin). Import that version or choose another mod version.")
            }
            guard ModCompatibility.catalogEligible(candidate) else { throw MonitorError("\(candidate.name) is not supported on a dedicated Mac server.") }
            var lastFailure: Error?
            for version in available {
                let savedRequirements = requirements, savedVisiting = visiting, savedSelected = selected, savedOrdered = ordered
                do {
                    visiting.insert(name)
                    for dependency in version.dependencies {
                        guard let parts = ModCompatibility.split(dependency) else { throw MonitorError("Invalid dependency: \(dependency).") }
                        try visit(parts.name,parts.version)
                    }
                    visiting.remove(name); selected[name] = version.version_number
                    ordered.append(ResolvedMod(package:candidate,version:version))
                    return
                } catch RetryResolution.newerRequirement {
                    // Keep the stronger minimum for the outer convergence pass.
                    throw RetryResolution.newerRequirement
                } catch {
                    // A newer dependency can introduce a cycle or an unavailable requirement.
                    // Try the next eligible version without retaining its partial dependency graph.
                    requirements = savedRequirements; visiting = savedVisiting
                    selected = savedSelected; ordered = savedOrdered; lastFailure = error
                }
            }
            throw lastFailure ?? MonitorError("No usable dependency version for \(name).")
        }
        for _ in 0...catalog.count {
            visiting = []; selected = [:]; ordered = []
            do { try visit(package, version); return ordered }
            catch RetryResolution.newerRequirement { continue }
        }
        throw MonitorError("Dependency resolution did not converge.")
    }
}


extension ModCatalog {
    /// Fetch version-specific author documentation, never execute package contents.
    public static func readme(package: ModPackage, version: ModVersion, source: ModSource) async throws -> String {
        if source == .thunderstore {
          do {
            var url = URL(string: "https://thunderstore.io/api/experimental/package/")!
            for component in [package.owner, package.name, version.version_number, "readme"] { url.appendPathComponent(component) }
            var request = URLRequest(url: url.appendingPathComponent("")); request.timeoutInterval = 30
            request.setValue("ValheimServerManager/2.0-development", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MonitorError("Full description unavailable.") }
            struct Readme: Decodable { let markdown: String }
            let markdown = try JSONDecoder().decode(Readme.self, from: data).markdown
            guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MonitorError("Empty README.") }
            return markdown
          } catch { try Task.checkCancellation() }
        }
        var request = URLRequest(url: version.download_url); request.timeoutInterval = 60
        guard version.download_url.scheme == "https" else { throw MonitorError("Unsupported download address.") }
        let (archive, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: archive) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MonitorError("The mod host could not provide its documentation.") }
        return try archiveReadme(archive)
    }
    /// Read documentation without importing, enabling, or validating a package for installation.
    public static func archiveReadme(_ archive: URL) throws -> String {
        guard (try archive.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max <= 512_000_000 else { throw MonitorError("Archive exceeds 512 MB.") }
        let listing = try command("/usr/bin/unzip", ["-Z1", archive.path])
        guard listing.code == 0 else { throw MonitorError("Cannot read mod archive.") }
        let candidates = listing.output.split(separator: "\n").map(String.init).filter {
            ["readme.md", "readme.txt", "readme"].contains(URL(fileURLWithPath: $0).lastPathComponent.lowercased()) && !$0.contains("__MACOSX/")
        }.sorted { $0.count < $1.count }
        guard let name = candidates.first else { throw MonitorError("No README supplied by the author.") }
        // Escape ZIP glob characters; only stream this bounded document, never extract files.
        let pattern = name.replacingOccurrences(of: "[", with: "[[]").replacingOccurrences(of: "*", with: "[*]").replacingOccurrences(of: "?", with: "[?]")
        let info = try command("/usr/bin/unzip", ["-l", archive.path, pattern])
        let sizes = info.output.split(separator: "\n").compactMap { line -> Int? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 4, fields[1].contains("-"), fields[2].contains(":") else { return nil }
            return Int(fields[0])
        }
        guard info.code == 0, sizes.count == 1, sizes[0] <= 2_000_000 else { throw MonitorError("README is ambiguous or exceeds 2 MB.") }
        let result = try command("/usr/bin/unzip", ["-p", archive.path, pattern])
        guard result.code == 0, !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MonitorError("No README supplied by the author.") }
        return result.output
    }
}
