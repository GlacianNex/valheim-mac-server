import Foundation
import Darwin

public enum AppInstallation {
    /// Called only after the user approves installing the currently running app.
    public static func copy(from source: URL, to destination: URL) throws {
        let files = FileManager.default
        guard !files.fileExists(atPath: destination.path) else {
            throw MonitorError("Valheim Server Monitor is already in Applications. Replace it in Finder to update the app. Server data is stored separately.")
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
