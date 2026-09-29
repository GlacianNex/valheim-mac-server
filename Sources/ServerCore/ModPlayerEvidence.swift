import Foundation

/// Conservative author statements. Absence of a statement never proves server-only compatibility.
public struct ModPlayerEvidence: Equatable {
    public let requirement: ModPlayerRequirement
    public let explanation: String
    public init(requirement:ModPlayerRequirement,explanation:String) { self.requirement = requirement; self.explanation = explanation }

    public static func read(declared: ModPlayerRequirement = .unknown, description: String = "", readme: String = "") -> Self {
        var evidence: [(ModPlayerRequirement, String)] = []
        if declared != .unknown { evidence.append((declared, "Author catalog category")) }
        let text = (description + "\n" + readme)
            .replacingOccurrences(of: #"(?s)```.*?```"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, line.count <= 1000 else { continue }
            let lower = line.lowercased()
            // Do not turn dependency instructions, quotations or optional advice into requirements for this mod.
            guard !lower.contains("dependenc"), !lower.hasPrefix(">"),
                  !lower.contains("optional"), !lower.contains("recommend"),
                  !lower.contains("not required"), !lower.contains("does not require"),
                  !lower.contains("don't need"), !lower.contains("do not need"), !lower.contains("for this setting"),
                  !lower.contains("for config sync"), !lower.contains("as admin"),
                  !lower.contains("if you"), !lower.contains("if installed") else { continue }
            let required = #"\b(?:must|required to|needs? to) be installed (?:on )?(?:(?:both )?(?:the )?(?:client(?:s)?|server)(?: and | & )(?:(?:the |all |every )(?:connecting )?)?(?:server|client(?:s)?)|(?:all |every )(?:client(?:s)?|player(?:s)?))\b|\b(?:all players|all clients|every player|every client) (?:must|need to|needs to) install (?:this mod|the mod|it)\b|^\s*(?:installation: ?)?(?:required|install) on both (?:the )?client(?:s)? and (?:the )?server[.! ]*$"#
            let serverOnly = #"^(?:[-*# ]*)(?:this mod is |this is a |installation: ?)?server[- ]only(?: mod)?[.! ]*$"#
            if lower.range(of: required, options: .regularExpression) != nil { evidence.append((.playersRequired, line)) }
            if lower.range(of: serverOnly, options: .regularExpression) != nil { evidence.append((.serverOnly, line)) }
        }
        let kinds = Set(evidence.map { $0.0.rawValue })
        guard kinds.count == 1, let first = evidence.first else {
            return Self(requirement: .unknown, explanation: kinds.isEmpty ? "The author has not clearly specified player installation requirements." : "Author statements conflict; check the mod website before installing.")
        }
        return Self(requirement: first.0, explanation: evidence.map(\.1).joined(separator: "\n"))
    }

    public static func installed(_ mod:StoredMod,in mods:[StoredMod],visited:Set<String> = []) -> ModPlayerRequirement {
        guard !visited.contains(mod.id) else { return .unknown }
        var visited = visited; visited.insert(mod.id)
        let requirements = mod.dependencies.map { pin -> ModPlayerRequirement in
            if ModCompatibility.supplies(pin) { return .serverOnly }
            guard let dependency = ModCompatibility.dependency(pin,in:mods) else { return .unknown }
            return installed(dependency,in:mods,visited:visited)
        }
        return includingDependencies(mod.requirement,dependencies:requirements)
    }

    /// A required client dependency makes the installation require clients too. Unknown dependencies
    /// prevent a server-only claim; frameworks supplied by the manager are handled by the caller.
    public static func includingDependencies(_ own: ModPlayerRequirement, dependencies: [ModPlayerRequirement]) -> ModPlayerRequirement {
        if own == .clientOnly { return .clientOnly }
        if own == .playersRequired || dependencies.contains(.playersRequired) || dependencies.contains(.clientOnly) { return .playersRequired }
        if own == .unknown || dependencies.contains(.unknown) { return .unknown }
        return .serverOnly
    }
}
