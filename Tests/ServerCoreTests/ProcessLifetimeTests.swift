import XCTest
import Foundation
@testable import ServerCore

final class ProcessLifetimeTests: XCTestCase {
    func testDetectsRealProcessExitWithoutAppKitNotifications() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        let identity = try XCTUnwrap(ProcessLifetime(pid: child.processIdentifier))
        XCTAssertTrue(identity.isRunning)
        child.terminate()
        child.waitUntilExit()
        XCTAssertFalse(identity.isRunning)
        XCTAssertNil(ProcessLifetime(pid: child.processIdentifier))
    }
    func testCurrentProcessIsStillRunning() throws {
        let identity = try XCTUnwrap(ProcessLifetime(pid: ProcessInfo.processInfo.processIdentifier))
        XCTAssertTrue(identity.isRunning)
    }
}
