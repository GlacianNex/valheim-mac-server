import XCTest
@testable import ServerCore

final class ServerUpdatePolicyTests: XCTestCase {
    func testAutomaticUpdatesRequireExplicitZeroForEveryRunningServer() {
        func server(_ state: String, _ players: String, running: Bool = true) -> ServerStatus {
            var s = ServerStatus(); s.state = state; s.players = players; s.running = running; return s
        }
        XCTAssertTrue(ServerUpdatePolicy.serversAreEmpty([server("Online", "0"), server("Online", "0")]))
        XCTAssertTrue(ServerUpdatePolicy.serversAreEmpty([server("Stopped", "", running: false)]))
        XCTAssertFalse(ServerUpdatePolicy.serversAreEmpty([server("Online", "0"), server("Online", "1")]))
        XCTAssertFalse(ServerUpdatePolicy.serversAreEmpty([server("Online", "")]))
        XCTAssertFalse(ServerUpdatePolicy.serversAreEmpty([server("Starting", "0")]))
        XCTAssertFalse(ServerUpdatePolicy.serversAreEmpty([server("Stopping", "0")]))
    }
    func testChecksEveryTenMinutesAndOnlyNewBuildsTrigger() {
        XCTAssertEqual(ServerUpdatePolicy.checkInterval, 600)
        XCTAssertTrue(ServerUpdatePolicy.shouldStart(enabled: true, installed: "100", latest: "101", busy: false, lastAttempt: nil))
        XCTAssertFalse(ServerUpdatePolicy.shouldStart(enabled: false, installed: "100", latest: "101", busy: false, lastAttempt: nil))
        XCTAssertFalse(ServerUpdatePolicy.shouldStart(enabled: true, installed: "100", latest: "101", busy: true, lastAttempt: nil))
        XCTAssertFalse(ServerUpdatePolicy.shouldStart(enabled: true, installed: "101", latest: "101", busy: false, lastAttempt: nil))
        XCTAssertFalse(ServerUpdatePolicy.shouldStart(enabled: true, installed: "102", latest: "101", busy: false, lastAttempt: nil))
        XCTAssertFalse(ServerUpdatePolicy.shouldStart(enabled: true, installed: "100", latest: nil, busy: false, lastAttempt: nil))
        XCTAssertFalse(ServerUpdatePolicy.shouldStart(enabled: true, installed: "100", latest: "101", busy: false, lastAttempt: "101"))
        XCTAssertTrue(ServerUpdatePolicy.shouldStart(enabled: true, installed: "100", latest: "102", busy: false, lastAttempt: "101"))
    }
    func testOlderSettingsDefaultOffAndPreferencePersistsWithoutChangingWorlds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = Paths(root: root), store = try Store(paths: paths)
        var profile = Profile(); profile.label = "Existing"; profile.name = "Existing"; profile.world = "Existing"; profile.password = "test-password"
        try store.save(profile)
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.file("profiles.json"))) as! [String: Any]
        json.removeValue(forKey: "automaticServerUpdates"); json.removeValue(forKey: "lastAutomaticServerUpdateAttempt")
        try JSONSerialization.data(withJSONObject: json).write(to: paths.file("profiles.json"))
        XCTAssertNil(try store.load().automaticServerUpdates)
        let world = store.saveDirectory(profile).appendingPathComponent("worlds_local/Existing.db")
        try atomicWrite(Data("existing world sentinel".utf8), to: world)
        let engine = Engine(paths: paths)
        _ = try engine.execute("automatic-server-updates-on")
        XCTAssertEqual(try store.load().automaticServerUpdates, true)
        try store.update { $0.lastAutomaticServerUpdateAttempt = "101" }
        _ = try engine.execute("automatic-server-updates-off")
        XCTAssertEqual(try store.load().automaticServerUpdates, false)
        _ = try engine.execute("automatic-server-updates-on")
        XCTAssertNil(try store.load().lastAutomaticServerUpdateAttempt)
        XCTAssertEqual(try store.load().profiles, [profile])
        XCTAssertEqual(try Data(contentsOf: world), Data("existing world sentinel".utf8))
    }
}
