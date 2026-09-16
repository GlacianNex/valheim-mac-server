import Foundation
import XCTest
@testable import ServerCore

final class InstallerArchitectureTests: XCTestCase {
    func testAcceptsUniversalAndRejectsEitherMissingArchitecture() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vsm architecture " + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("fixture.c")
        try Data("int fixture(void) { return 0; }\n".utf8).write(to: source)
        let arm = root.appendingPathComponent("arm.o"), intel = root.appendingPathComponent("intel.o")
        for (architecture, output) in [("arm64", arm), ("x86_64", intel)] {
            try checkCommand("/usr/bin/clang", ["-arch", architecture, "-c", source.path, "-o", output.path])
        }
        let universal = root.appendingPathComponent("universal.o")
        try checkCommand("/usr/bin/lipo", ["-create", arm.path, intel.path, "-output", universal.path])
        XCTAssertNoThrow(try Installer.verifyArchitectures(universal))
        XCTAssertThrowsError(try Installer.verifyArchitectures(arm))
        XCTAssertThrowsError(try Installer.verifyArchitectures(intel))
        XCTAssertThrowsError(try Installer.verifyArchitectures(source))
        XCTAssertThrowsError(try Installer.verifyArchitectures(root.appendingPathComponent("missing")))
    }
}
