import Foundation

/// A one-launch handoff after a successful app replacement.
public enum AppUpdateResume {
    public static func shouldStart(wasRunning: Bool, autostart: Bool) -> Bool {
        wasRunning || autostart
    }

    public static func run(paths: Paths, profileID: String?, start: () throws -> Void) throws {
        guard let profileID, !profileID.isEmpty,
              try Store(paths: paths).selected().id == profileID else {
            throw MonitorError("The app was updated, but the selected world changed. Choose your world and start it from the menu.")
        }
        try start()
    }
}
