import Foundation
import Darwin

public enum AppInstallation {
    public static let bundleIdentifier = "io.github.glaciannex.valheimservermonitor"

    public static func destination(in applications: URL, exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let names = ["Valheim Server Manager for Mac.app", "Valhiem Server Manager for Mac.app", "Valheim Server Monitor.app"]
        let candidates = names.map { applications.appendingPathComponent($0) }
        return candidates.first(where: exists) ?? candidates[0]
    }

    public static func version(at app: URL) throws -> String {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundleIdentifier,
              let version = info["CFBundleShortVersionString"] as? String,
              version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil else {
            throw MonitorError("This is not a supported Valheim Server Manager for Mac app.")
        }
        return version
    }

    public static func isExperimental(_ bundle: Bundle = .main) -> Bool {
        bundle.object(forInfoDictionaryKey: "VSMReleaseChannel") as? String == "experimental"
    }

    public static func isExperimental(at app: URL) throws -> Bool {
        _ = try version(at: app)
        let data = try Data(contentsOf:app.appendingPathComponent("Contents/Info.plist"))
        let info = try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any]
        return info?["VSMReleaseChannel"] as? String == "experimental"
    }

    public static func canReplace(from source: URL, to destination: URL) throws -> Bool {
        let incoming = try version(at:source), installed = try version(at:destination)
        // A deliberately opened experimental download can replace any build, including
        // another experiment with the same public version. Stable upgrades stay monotonic.
        if try isExperimental(at:source) { return true }
        if try isExperimental(at:destination) { return false }
        return incoming.compare(installed,options:.numeric) == .orderedDescending
    }

    public static func displayVersion(at app: URL) throws -> String {
        try isExperimental(at:app) ? "Experimental" : version(at:app)
    }

    /// Returns a backup directory. Keep it until the replacement has launched successfully.
    public static func update(from source: URL, to destination: URL, beforeReplacing: () throws -> Void) throws -> URL {
        guard try canReplace(from:source,to:destination) else {
            throw MonitorError("This download cannot replace the installed build. Experimental builds take precedence; stable updates must be newer. To leave experimental testing, replace the app in Applications using Finder.")
        }
        let files = FileManager.default
        let transaction = destination.deletingLastPathComponent().appendingPathComponent(".valheim-update-" + UUID().uuidString)
        try files.createDirectory(at: transaction, withIntermediateDirectories: false)
        let staged = transaction.appendingPathComponent("New.app"), backup = transaction.appendingPathComponent("Previous.app")
        do {
            try copy(from: source, to: staged)
            try checkCommand("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
            try beforeReplacing()
            try replacePrepared(staged, destination: destination, backup: backup)
            return transaction
        } catch {
            // Never discard the old app if a rollback itself failed.
            if !files.fileExists(atPath: backup.path) { try? files.removeItem(at: transaction) }
            throw error
        }
    }

    static func replacePrepared(_ staged: URL, destination: URL, backup: URL,
                                move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) throws {
        try move(destination, backup)
        do { try move(staged, destination) }
        catch {
            do { try move(backup, destination) }
            catch { throw MonitorError("The update could not finish. Your previous app is preserved at \(backup.path). Move it back to Applications using Finder.") }
            throw error
        }
    }

    /// Called only after the user approves installing the currently running app.
    public static func copy(from source: URL, to destination: URL) throws {
        let files = FileManager.default
        guard !files.fileExists(atPath: destination.path) else {
            throw MonitorError("Valheim Server Manager for Mac is already in Applications. Replace it in Finder to update the app. Server data is stored separately.")
        }
        try files.copyItem(at: source, to: destination)
        do {
            // FileManager preserves quarantine, unlike a user move in Finder. Leaving it
            // on our approved installed copy can cause another App Translocation launch.
            // Only change the new copy, never the download or system Gatekeeper settings.
            try clearQuarantine(destination)
            var enumerationError: Error?
            let entries = files.enumerator(at: destination, includingPropertiesForKeys: nil,
                errorHandler: { _, error in enumerationError = error; return false })
            guard let entries else { throw MonitorError("Could not inspect the installed app.") }
            for case let entry as URL in entries { try clearQuarantine(entry) }
            if let enumerationError { throw enumerationError }
        } catch {
            try? files.removeItem(at: destination)
            throw error
        }
    }

    private static func clearQuarantine(_ url: URL) throws {
        // Do not follow links out of the copied bundle.
        if removexattr(url.path, "com.apple.quarantine", XATTR_NOFOLLOW) != 0 {
            let code = errno
            if code != ENOATTR { throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
        }
    }
}
