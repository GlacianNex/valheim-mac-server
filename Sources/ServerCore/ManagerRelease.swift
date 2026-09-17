import Foundation
import CryptoKit

public struct ManagerRelease: Decodable {
    public let tag_name: String
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]
    public struct Asset: Decodable {
        public let name: String
        public let browser_download_url: URL
        public let digest: String?
        public let size: Int
    }
    public var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    public static func validVersion(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil
    }
    public func isNewer(than current: String) -> Bool {
        !draft && !prerelease && Self.validVersion(version) && Self.validVersion(current)
            && version.compare(current, options: .numeric) == .orderedDescending
    }
    public func downloadAsset() throws -> Asset {
        guard !draft, !prerelease, Self.validVersion(version),
              let asset = assets.first(where: { $0.name == "Valheim-Server-Manager-for-Mac.zip" }),
              asset.size > 0, asset.size <= 50_000_000,
              asset.browser_download_url.scheme == "https",
              asset.browser_download_url.host == "github.com",
              asset.browser_download_url.user == nil, asset.browser_download_url.password == nil,
              asset.browser_download_url.port == nil,
              asset.browser_download_url.path == "/GlacianNex/valheim-mac-server/releases/download/\(tag_name)/\(asset.name)",
              let digest = asset.digest,
              digest.range(of: #"^sha256:[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            throw MonitorError("This release has no supported, verifiable Mac download. Please check the GitHub releases page.")
        }
        return asset
    }
    public func verifyDownload(_ data: Data) throws {
        let asset = try downloadAsset()
        let digest = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == asset.size, digest == asset.digest else {
            throw MonitorError("The downloaded update did not match its published checksum. Please retry.")
        }
    }
}
