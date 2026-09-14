import Foundation

public struct Profile: Codable, Equatable {
    public var id = UUID().uuidString.lowercased()
    public var label = "", name = "", world = "", password = ""
    public var port = 2456, saveinterval = 1800, backups = 4, backupshort = 7200, backuplong = 43200
    public var isPublic = true, crossplay = true
    public var instanceid = "", preset = "", extra = ""
    public var modifiers: [String: String] = [:]
    public var flags: [String: Bool] = [:]
    public var admins = "", banned = "", permitted = ""
    public static let modifierChoices = ["Combat": ["veryeasy", "easy", "hard", "veryhard"], "DeathPenalty": ["casual", "veryeasy", "easy", "hard", "hardcore"], "Resources": ["muchless", "less", "more", "muchmore", "most"], "Raids": ["none", "muchless", "less", "more", "muchmore"], "Portals": ["casual", "hard", "veryhard"]]
    public static let flagNames = ["nobuildcost", "playerevents", "passivemobs", "nomap", "fire"]
    public init() {}
    public init(form: [String: Any]) throws {
        self.init()
        func text(_ key: String) -> String { form[key].map { String(describing: $0) } ?? "" }
        if let value = form["id"] as? String, !value.isEmpty { id = value }
        label = text("label"); name = text("name"); world = text("world"); password = text("password")
        if text("id").isEmpty, text("import").isEmpty, world.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            world = Self.defaultWorldName(for: label)
        }
        for key in ["port", "saveinterval", "backups", "backupshort", "backuplong"] {
            guard let value = Int(text(key)) else { throw MonitorError("\(key) must be a whole number.") }
            switch key { case "port": port = value; case "saveinterval": saveinterval = value; case "backups": backups = value; case "backupshort": backupshort = value; default: backuplong = value }
        }
        isPublic = form["public"] as? Bool ?? true; crossplay = form["crossplay"] as? Bool ?? true
        instanceid = text("instanceid"); preset = text("preset"); extra = text("extra")
        for key in Self.modifierChoices.keys { modifiers[key] = text(key) }
        for key in Self.flagNames { flags[key] = form[key] as? Bool ?? false }
        admins = text("admins"); banned = text("banned"); permitted = text("permitted")
        try validate()
    }
    public static func defaultWorldName(for label: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let parts = label.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        let name = String(parts.joined(separator: "_").prefix(80))
        return name.isEmpty ? "World" : name
    }
    public var form: [String: Any] {
        var value: [String: Any] = ["id": id, "label": label, "name": name, "world": world, "password": password, "port": port, "saveinterval": saveinterval, "backups": backups, "backupshort": backupshort, "backuplong": backuplong, "public": isPublic, "crossplay": crossplay, "instanceid": instanceid, "preset": preset, "extra": extra, "admins": admins, "banned": banned, "permitted": permitted]
        for key in Self.modifierChoices.keys { value[key] = modifiers[key] ?? "" }
        for key in Self.flagNames { value[key] = flags[key] ?? false }
        return value
    }
    public func validate() throws {
        guard UUID(uuidString: id) != nil else { throw MonitorError("Invalid profile identifier.") }
        for (key, value) in [("Profile name", label), ("Server name", name), ("World filename", world), ("Password", password)] {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  value.rangeOfCharacter(from: .controlCharacters) == nil, !value.contains("\"") else { throw MonitorError("\(key) is required and cannot contain quotes or control characters.") }
        }
        guard !world.contains("/"), !world.contains("\\"), !world.contains(":"), world != ".", world != ".." else { throw MonitorError("World filename must be a plain filename.") }
        guard password.count >= 5, !name.localizedCaseInsensitiveContains(password) else { throw MonitorError("Use at least five password characters, and do not include the password in the server name.") }
        guard (1...65534).contains(port), saveinterval > 0, backups >= 0, backupshort > 0, backuplong > 0 else { throw MonitorError("Check the port (1–65534), positive save intervals, and nonnegative backup count.") }
        guard ["", "Normal", "Casual", "Easy", "Hard", "Hardcore", "Immersive", "Hammer"].contains(preset) else { throw MonitorError("Unknown preset.") }
        for (key, choices) in Self.modifierChoices {
            guard ([""] + choices).contains(modifiers[key] ?? "") else { throw MonitorError("Unknown \(key) option.") }
        }
        let controlled: Set<String> = ["-name", "-world", "-password", "-port", "-savedir", "-logfile", "-public", "-crossplay", "-instanceid", "-saveinterval", "-backups", "-backupshort", "-backuplong", "-preset", "-modifier", "-setkey", "-batchmode", "-nographics"]
        guard !extraArguments().contains(where: { controlled.contains($0.lowercased().components(separatedBy: "=")[0]) }) else { throw MonitorError("Use the profile fields for managed settings, not Additional arguments.") }
        _ = try Self.splitArguments(extra)
    }
    public static func splitArguments(_ value: String) throws -> [String] {
        var result: [String] = [], token = "", quote: Character?, escaped = false, started = false
        for c in value {
            if c.isNewline || c == "\0" { throw MonitorError("Arguments cannot contain newlines or NUL characters.") }
            if escaped { token.append(c); escaped = false; started = true; continue }
            if c == "\\", quote != "'" { escaped = true; started = true; continue }
            if let q = quote { if c == q { quote = nil } else { token.append(c) }; continue }
            if c == "'" || c == "\"" { quote = c; started = true }
            else if c.isWhitespace { if started { result.append(token); token = ""; started = false } }
            else { token.append(c); started = true }
        }
        guard quote == nil, !escaped else { throw MonitorError("Close quotes and trailing escapes in Additional arguments.") }
        if started { result.append(token) }
        return result
    }
    private func extraArguments() -> [String] { (try? Self.splitArguments(extra)) ?? [] }
    public func arguments(saveDirectory: URL, log: URL) throws -> [String] {
        try validate()
        var args = ["-nographics", "-batchmode", "-name", name, "-world", world, "-password", password,
                    "-savedir", saveDirectory.path, "-logFile", log.path, "-port", String(port), "-public", isPublic ? "1" : "0",
                    "-saveinterval", String(saveinterval), "-backups", String(backups), "-backupshort", String(backupshort), "-backuplong", String(backuplong)]
        if crossplay { args.append("-crossplay") }
        if !instanceid.isEmpty { args += ["-instanceid", instanceid] }
        if !preset.isEmpty { args += ["-preset", preset.lowercased()] }
        for key in Self.modifierChoices.keys.sorted() { if let value = modifiers[key], !value.isEmpty { args += ["-modifier", key.lowercased(), value] } }
        for key in Self.flagNames where flags[key] == true { args += ["-setkey", key] }
        return args + (try Self.splitArguments(extra))
    }
}
