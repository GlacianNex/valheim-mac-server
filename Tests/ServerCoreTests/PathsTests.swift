import XCTest
@testable import ServerCore

final class PathsTests: XCTestCase {
    func testCreatingDefaultDirectoryDoesNotSwitchToDevelopmentMode() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:base) }
        let before = base.appendingPathComponent("Valheim Server Monitor").standardizedFileURL
        let paths = Paths(root:before)
        XCTAssertFalse(paths.isDevelopment(defaultRoot:before,environmentOverride:nil))
        try paths.prepare()
        let after = base.appendingPathComponent("Valheim Server Monitor").standardizedFileURL
        XCTAssertNotEqual(before,after, "Fixture reproduces Foundation's directory URL change")
        XCTAssertEqual(before.path,after.path)
        XCTAssertFalse(paths.isDevelopment(defaultRoot:after,environmentOverride:nil))
        XCTAssertFalse(Paths(root:after).isDevelopment(defaultRoot:before,environmentOverride:nil))
    }
    func testCustomRootsAndExplicitOverridesRemainIsolated() {
        let normal = URL(fileURLWithPath:"/tmp/normal",isDirectory:true)
        XCTAssertTrue(Paths(root:URL(fileURLWithPath:"/tmp/custom")).isDevelopment(defaultRoot:normal,environmentOverride:nil))
        XCTAssertTrue(Paths(root:normal).isDevelopment(defaultRoot:normal,environmentOverride:normal.path))
        XCTAssertTrue(Paths(root:normal).isDevelopment(defaultRoot:normal,environmentOverride:""))
    }
}
