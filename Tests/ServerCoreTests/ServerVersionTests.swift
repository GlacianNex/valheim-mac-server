import XCTest
@testable import ServerCore

final class ServerVersionTests: XCTestCase {
    func testReadsPublicBuildWithoutMistakingBetaOrDepotForLatest() {
        let output = #""896660" { "depots" { "896663" { "manifests" { "public" { "gid" "555" } } } "branches" { "beta" { "buildid" "99999999" } "public" { "timeupdated" "123" "buildid" "25253791" } "default_old" { "buildid" "25185644" } } } }"#
        XCTAssertEqual(ServerVersion.latestBuild(in: output), "25253791")
        XCTAssertNil(ServerVersion.latestBuild(in: #""branches" { "beta" { "buildid" "999" } }"#))
        XCTAssertNil(ServerVersion.latestBuild(in: "Connection failed"))
    }
    func testInstalledManifestAndNumericBuildComparison() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = Paths(root: root)
        XCTAssertNil(ServerVersion.installed(paths: paths))
        let manifest = paths.server.appendingPathComponent("steamapps/appmanifest_896660.acf")
        let data = Data(#""AppState" { "appid" "896660" "buildid" "99" "TargetBuildID" "100" }"#.utf8)
        try atomicWrite(data, to: manifest)
        XCTAssertEqual(ServerVersion.installed(paths: paths), "99")
        XCTAssertEqual(try Data(contentsOf: manifest), data)
        XCTAssertTrue(ServerVersion.updateAvailable(installed: "99", latest: "100"))
        XCTAssertFalse(ServerVersion.updateAvailable(installed: "100", latest: "99"))
        XCTAssertFalse(ServerVersion.updateAvailable(installed: "100", latest: "100"))
        XCTAssertFalse(ServerVersion.updateAvailable(installed: "unknown", latest: "100"))
    }
}
