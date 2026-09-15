import XCTest
import Foundation
import Darwin
@testable import ServerCore

final class FleetTests: XCTestCase {
    var root: URL!, paths: Paths!, store: Store!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vsm-fleet-" + UUID().uuidString)
        paths = Paths(root: root); store = try Store(paths: paths)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func profile(_ name: String, port: Int) -> Profile {
        var p = Profile(); p.label = name; p.name = name; p.world = name; p.password = "test-only-secret"; p.port = port; return p
    }
    func testMigrationPreservesLegacyWorldAndAutostartAndBacksUpDatabase() throws {
        let original = profile("Legacy", port: 29400)
        var db = Database(); db.profiles = [original]; db.selected = original.id; db.autostart = true
        let data = try encode(db); try atomicWrite(data, to: paths.file("profiles.json"))
        let sentinel = store.saveDirectory(original).appendingPathComponent("worlds_local/Legacy.db")
        try atomicWrite(Data("saved world".utf8), to: sentinel)
        let other = profile("Second", port: 29402); try store.save(other)
        let updated = try store.load()
        XCTAssertEqual(updated.schema, 2); XCTAssertEqual(updated.legacyProfile, original.id)
        XCTAssertEqual(updated.profiles, [original, other]); XCTAssertEqual(updated.selected, original.id)
        XCTAssertTrue(store.autostart(original.id)); XCTAssertFalse(store.autostart(other.id))
        XCTAssertEqual(try Data(contentsOf: paths.file("profiles-before-multiserver.json")), data)
        XCTAssertEqual(try String(contentsOf: sentinel), "saved world")
        XCTAssertEqual(store.servicePaths(original.id).stateRoot.path, paths.root.path)
        XCTAssertNotEqual(store.servicePaths(other.id).stateRoot, paths.root)
    }
    func testIndependentStateAndReadOnlySettingsWhileOtherServerRuns() throws {
        let first = profile("First", port: 29410), second = profile("Second", port: 29412)
        try store.save(first); try store.save(second)
        let a = store.servicePaths(first.id), b = store.servicePaths(second.id); try b.prepare()
        let fd = open(a.file("service.lock").path, O_CREAT | O_RDWR, 0o600)
        defer { flock(fd, LOCK_UN); close(fd) }; XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        XCTAssertTrue(Lifecycle(paths: a).isActive); XCTAssertFalse(Lifecycle(paths: b).isActive)
        XCTAssertThrowsError(try store.save(first)); XCTAssertNoThrow(try store.save(second))
        let settings = try Engine(paths: paths).execute("get-profile", arguments: [first.id])
        XCTAssertTrue(settings.contains("First"))
        try Lifecycle(paths: b).requestStart()
        XCTAssertFalse(Lifecycle(paths: a).requested("start-request"))
        try Lifecycle(paths: b).requestStop(wait: false)
        XCTAssertFalse(Lifecycle(paths: a).requested("stop-request"))
        XCTAssertNotEqual(a.logs, b.logs); XCTAssertEqual(a.executable, b.executable)
        let statuses = try Fleet(paths: paths).statuses()
        XCTAssertEqual(statuses.map(\.selected), [first.id, second.id])
        XCTAssertEqual(statuses.map(\.running), [true, false])
        let aggregate = try JSONDecoder().decode(ServerStatus.self, from: Data(Engine(paths: paths).execute("status").utf8))
        XCTAssertEqual(aggregate.players, "", "An unknown running-server count must not become a misleading zero total")
        try Lifecycle(paths: a).requestStop(wait: false)
        let stopping = try JSONDecoder().decode(ServerStatus.self, from: Data(Engine(paths: paths).execute("status").utf8))
        XCTAssertEqual(stopping.state, "Stopping")
    }
    func testFleetStatePreservesStoppingWithOtherServersOnlineOrStarting() {
        func server(_ state: String) -> ServerStatus {
            var result = ServerStatus(); result.state = state; result.running = state != "Stopped"; return result
        }
        XCTAssertEqual(Fleet.state(for: [server("Stopping")]), "Stopping")
        XCTAssertEqual(Fleet.state(for: [server("Online"), server("Stopping")]), "Stopping")
        XCTAssertEqual(Fleet.state(for: [server("Starting"), server("Stopping")]), "Stopping")
        XCTAssertEqual(Fleet.state(for: [server("Online"), server("Starting")]), "Starting")
        XCTAssertEqual(Fleet.state(for: [server("Stopped"), server("Online")]), "Online")
        XCTAssertEqual(Fleet.state(for: [server("Stopped")]), "Stopped")
        XCTAssertEqual(Fleet.state(for: []), "Stopped")
    }
    func testSharedRuntimeAllowsParallelServersButBlocksUpdates() throws {
        var first: RuntimeLease? = try RuntimeLease(paths: paths, exclusive: false)
        var second: RuntimeLease? = try RuntimeLease(paths: paths, exclusive: false)
        XCTAssertThrowsError(try RuntimeLease(paths: paths, exclusive: true))
        first = nil
        XCTAssertThrowsError(try RuntimeLease(paths: paths, exclusive: true))
        second = nil
        let update = try RuntimeLease(paths: paths, exclusive: true)
        XCTAssertThrowsError(try RuntimeLease(paths: paths, exclusive: false))
        withExtendedLifetime((first, second, update)) {}
    }
    func testConflictingPortsAndIndependentResumePreferences() throws {
        let first = profile("First", port: 29420), second = profile("Second", port: 29421)
        try store.save(first); try store.save(second)
        let fd = open(store.servicePaths(first.id).file("service.lock").path, O_CREAT | O_RDWR, 0o600)
        defer { flock(fd, LOCK_UN); close(fd) }; XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        XCTAssertThrowsError(try Fleet(paths: paths).checkProfilePorts(second))
        try store.update { $0.profileAutostart = [first.id: false, second.id: true] }
        XCTAssertEqual(Set(try Fleet(paths: paths).resumeIDs()), Set([first.id, second.id]))
        XCTAssertEqual(try Fleet(paths: paths).runningIDs(), [first.id])
        XCTAssertFalse(store.autostart(first.id)); XCTAssertTrue(store.autostart(second.id))
    }
}
