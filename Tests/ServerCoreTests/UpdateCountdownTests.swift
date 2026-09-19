import XCTest
@testable import ServerCore

final class UpdateCountdownTests: XCTestCase {
    func testWarningsUseOneDeadlineAndNeverTenSeconds() {
        let start = Date(timeIntervalSince1970: 1000)
        var countdown = UpdateCountdown(now: start)
        XCTAssertEqual(countdown.warning(at: start), 15)
        XCTAssertNil(countdown.warning(at: start.addingTimeInterval(1)))
        XCTAssertNil(countdown.warning(at: start.addingTimeInterval(299)))
        XCTAssertEqual(countdown.warning(at: start.addingTimeInterval(300)), 10)
        XCTAssertEqual(countdown.warning(at: start.addingTimeInterval(600)), 5)
        XCTAssertEqual(countdown.warning(at: start.addingTimeInterval(840)), 1)
        XCTAssertNil(countdown.warning(at: start.addingTimeInterval(890)))
        XCTAssertNil(countdown.warning(at: start.addingTimeInterval(900)))
        XCTAssertEqual(countdown.remaining(at: start.addingTimeInterval(900)), 0)
        XCTAssertEqual(countdown.deadline, start.addingTimeInterval(900))
    }
    func testDelayedTimerDoesNotSendStaleWarningBurst() {
        let start = Date(timeIntervalSince1970: 1000)
        var countdown = UpdateCountdown(now: start)
        XCTAssertEqual(countdown.warning(at: start.addingTimeInterval(850)), 1)
        XCTAssertNil(countdown.warning(at: start.addingTimeInterval(851)))
    }
    func testNewServerOptsIntoManagementAndLegacyDoesNot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(paths: Paths(root: root))
        let old = Profile()
        try store.update { $0.profiles = [old]; $0.selected = old.id }
        XCTAssertFalse(ManagedServer(paths: store.servicePaths(old.id)).enabled)
        var added = Profile(); added.label = "New managed world"; added.name = "Managed test"; added.password = "test-password"; added.world = "ManagedTest"
        try store.save(added)
        XCTAssertTrue(ManagedServer(paths: store.servicePaths(added.id)).enabled)
        XCTAssertFalse(ManagedServer(paths: store.servicePaths(old.id)).enabled)
    }
}
