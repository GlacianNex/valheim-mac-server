import AppKit
import ServerCore

/// Downloads only stable official releases. AppLocation owns replacement and server recovery.
enum ManagerUpdater {
    static let endpoint = URL(string: "https://api.github.com/repos/GlacianNex/valheim-mac-server/releases/latest")!
    static func latest() async throws -> ManagerRelease {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Valheim-Server-Manager-for-Mac", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw MonitorError("Could not check GitHub for manager updates. Try again later.")
        }
        let release = try JSONDecoder().decode(ManagerRelease.self, from: data)
        guard !release.draft, !release.prerelease, ManagerRelease.validVersion(release.version) else {
            throw MonitorError("GitHub did not return a supported stable release.")
        }
        return release
    }
    static func download(_ release: ManagerRelease) async throws -> URL {
        let asset = try release.downloadAsset()
        var request = URLRequest(url: asset.browser_download_url)
        request.timeoutInterval = 120
        let (temporary, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw MonitorError("The manager update could not be downloaded. Please retry.")
        }
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size == asset.size else { throw MonitorError("The update download is incomplete. Please retry.") }
        try release.verifyDownload(Data(contentsOf: temporary, options: .mappedIfSafe))
        let files = FileManager.default
        let root = try files.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ValheimServerManagerUpdates/" + UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            // Reject unsafe paths and links before unpacking the archive.
            let listing = try ServerCore.command("/usr/bin/unzip", ["-Z1", temporary.path])
            let entries = listing.output.split(separator: "\n").map(String.init)
            guard listing.code == 0, !entries.isEmpty, entries.allSatisfy({
                $0.hasPrefix("Valheim Server Manager for Mac.app/") && !$0.split(separator: "/").contains("..") && !$0.contains("\\")
            }) else { throw MonitorError("The update archive has an unexpected layout.") }
            let details = try ServerCore.command("/usr/bin/unzip", ["-Z", "-l", temporary.path])
            guard details.code == 0, !details.output.split(separator: "\n").contains(where: { $0.hasPrefix("l") }) else {
                throw MonitorError("The update archive contains unsupported symbolic links.")
            }
            try checkCommand("/usr/bin/ditto", ["-x", "-k", temporary.path, root.path])
            let app = root.appendingPathComponent("Valheim Server Manager for Mac.app")
            guard try AppInstallation.version(at: app) == release.version else {
                throw MonitorError("The downloaded app version does not match the release.")
            }
            let requirement = "anchor apple generic and identifier \"\(AppInstallation.bundleIdentifier)\" and certificate leaf[subject.OU] = \"AB6C5XALCV\""
            try checkCommand("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", "=" + requirement, app.path])
            try checkCommand("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
            return app
        } catch {
            try? files.removeItem(at: root)
            throw error
        }
    }
}
