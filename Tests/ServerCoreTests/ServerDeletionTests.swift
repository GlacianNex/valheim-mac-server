import XCTest
import Darwin
@testable import ServerCore

final class ServerDeletionTests: XCTestCase {
    func testDeletionPreservesWorldAndOtherServerAndRefusesRunning() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = Paths(root: root), store = try Store(paths: paths)
        var first = Profile(); first.label = "First"; first.name = "First"; first.world = "First"; first.password = "test-secret"
        var second = first; second.id = UUID().uuidString.lowercased(); second.label = "Second"
        try store.save(first); try store.save(second)
        let world = store.saveDirectory(first).appendingPathComponent("sentinel")
        try atomicWrite(Data("preserve".utf8), to: world)
        let fd = open(store.servicePaths(first.id).file("service.lock").path, O_CREAT | O_RDWR, 0o600)
        defer { close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        XCTAssertThrowsError(try store.delete(first.id))
        flock(fd, LOCK_UN)
        let recovery = try store.delete(first.id)
        XCTAssertEqual(try String(contentsOf: recovery.appendingPathComponent("world/sentinel")), "preserve")
        XCTAssertEqual(try store.load().profiles, [second])
        XCTAssertEqual(try store.load().selected, second.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: world.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.saveDirectory(second).path))
    }
    func testPasswordFreeRequiresUnlistedAndShortPasswordsStillFail() throws {
        var p = Profile(); p.label = "Test"; p.name = "Test"; p.world = "Test"
        XCTAssertThrowsError(try p.validate())
        p.isPublic = false; XCTAssertNoThrow(try p.validate())
        p.password = "1234"; XCTAssertThrowsError(try p.validate())
        p.password = "12345"; XCTAssertNoThrow(try p.validate())
    }
}
