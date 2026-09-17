import XCTest
@testable import ServerCore

final class ManagerReleaseTests: XCTestCase {
    private func release(version: String = "v1.2.0", draft: Bool = false, prerelease: Bool = false,
                         url: String? = nil, digest: String? = "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                         size: Int = 3) throws -> ManagerRelease {
        var asset: [String: Any] = ["name": "Valheim-Server-Manager-for-Mac.zip", "size": size,
            "browser_download_url": url ?? "https://github.com/GlacianNex/valheim-mac-server/releases/download/\(version)/Valheim-Server-Manager-for-Mac.zip"]
        if let digest { asset["digest"] = digest }
        return try JSONDecoder().decode(ManagerRelease.self, from: JSONSerialization.data(withJSONObject:
            ["tag_name": version, "draft": draft, "prerelease": prerelease, "assets": [asset]]))
    }
    func testStableVersionsOnlyAndNumericOrdering() throws {
        XCTAssertTrue(try release(version: "v1.10.0").isNewer(than: "1.9.0"))
        XCTAssertFalse(try release().isNewer(than: "1.2.0"))
        XCTAssertFalse(try release().isNewer(than: "2.0.0"))
        XCTAssertFalse(try release(draft: true).isNewer(than: "1.0.0"))
        XCTAssertFalse(try release(prerelease: true).isNewer(than: "1.0.0"))
        XCTAssertFalse(try release(version: "v1.3.0-beta").isNewer(than: "1.0.0"))
        XCTAssertFalse(try release().isNewer(than: "Development"))
    }
    func testRejectsUntrustedOrUnverifiableAssets() throws {
        XCTAssertThrowsError(try release(url: "https://example.com/update.zip").downloadAsset())
        XCTAssertThrowsError(try release(url: "https://github.com/other/repo/releases/download/v1.2.0/Valheim-Server-Manager-for-Mac.zip").downloadAsset())
        XCTAssertThrowsError(try release(digest: nil).downloadAsset())
        XCTAssertThrowsError(try release(digest: "sha256:invalid").downloadAsset())
        XCTAssertThrowsError(try release(size: 50_000_001).downloadAsset())
        XCTAssertThrowsError(try release(prerelease: true).downloadAsset())
    }
    func testChecksumAndSizeMustMatchBeforeExtraction() throws {
        let value = try release()
        XCTAssertNoThrow(try value.verifyDownload(Data("abc".utf8)))
        XCTAssertThrowsError(try value.verifyDownload(Data("abd".utf8)))
        XCTAssertThrowsError(try value.verifyDownload(Data("abcd".utf8)))
    }
}
