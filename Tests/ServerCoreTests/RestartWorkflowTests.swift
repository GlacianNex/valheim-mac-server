import XCTest
@testable import ServerCore

final class RestartWorkflowTests: XCTestCase {
    func testFullFifteenMinuteWorkflowUsesFixedClockAndCorrectOrder() throws {
        let start = Date(timeIntervalSince1970:1000); var now = start
        var actions: [String] = [], warnings: [Int] = [], phases: [ServerUpdateProgress.Phase] = []
        var w = RestartWorkflow(validate:{},warn:{ warnings.append($0) },stop:{actions.append("stop")},install:{actions.append("install")},start:{actions.append("start")},progress:{ phases.append($0.phase) })
        w.now = { now }; w.sleep = { now.addTimeInterval($0) }
        try w.run(deadline:start.addingTimeInterval(900))
        XCTAssertEqual(warnings,[15,10,5,1]); XCTAssertEqual(actions,["stop","install","start"])
        XCTAssertEqual(Array(phases.suffix(3)),[.stopping,.installing,.starting]); XCTAssertEqual(now.timeIntervalSince(start),900)
    }
    func testCancellationAndWarningFailureNeverStop() {
        var stopped = false
        let w = RestartWorkflow(validate:{throw MonitorError("cancel")},warn:{_ in},stop:{stopped = true},install:{},start:{},progress:{_ in})
        XCTAssertThrowsError(try w.run(deadline:Date().addingTimeInterval(900))); XCTAssertFalse(stopped)
        let failedWarning = RestartWorkflow(validate:{},warn:{_ in throw MonitorError("offline")},stop:{stopped = true},install:{},start:{},progress:{_ in})
        XCTAssertThrowsError(try failedWarning.run(deadline:Date().addingTimeInterval(900))); XCTAssertFalse(stopped)
    }
    func testPlayerJoinDuringCountdownAndInstallFailure() {
        var now = Date(), count = 0, stopped = false, started = false
        var w = RestartWorkflow(validate:{count += 1; if count > 5 { throw MonitorError("player joined") }},warn:{_ in},stop:{stopped = true},install:{},start:{started = true},progress:{_ in})
        w.now = { now }; w.sleep = { now.addTimeInterval($0) }
        XCTAssertThrowsError(try w.run(deadline:now.addingTimeInterval(900))); XCTAssertFalse(stopped); XCTAssertFalse(started)
        let badInstall = RestartWorkflow(validate:{},warn:{_ in},stop:{stopped = true},install:{throw MonitorError("verification failed")},start:{started = true},progress:{_ in})
        XCTAssertThrowsError(try badInstall.run(deadline:nil)); XCTAssertTrue(stopped); XCTAssertFalse(started)
    }
    func testRestartNowSkipsWaitButKeepsValidationAndLifecycleOrder() throws {
        var now = Date(), immediate = false, checks = 0
        var actions: [String] = []
        var w = RestartWorkflow(validate:{ checks += 1 },warn:{_ in},stop:{actions.append("stop")},install:{actions.append("install")},start:{actions.append("start")},progress:{_ in})
        w.now = { now }; w.sleep = { now.addTimeInterval($0); immediate = true }
        w.restartNow = { immediate }
        let began = now
        try w.run(deadline:now.addingTimeInterval(900))
        XCTAssertEqual(now.timeIntervalSince(began), 1)
        XCTAssertEqual(actions, ["stop", "install", "start"])
        XCTAssertEqual(checks, 3)
    }
    func testCancelWinsOverRestartNowDuringCountdown() {
        var now = Date(), cancelled = false, stopped = false
        var w = RestartWorkflow(validate:{ if cancelled { throw MonitorError("cancelled") } },warn:{_ in},stop:{stopped = true},install:{XCTFail("must not install")},start:{XCTFail("must not start")},progress:{_ in})
        w.now = { now }; w.sleep = { now.addTimeInterval($0); cancelled = true }
        w.restartNow = { cancelled }
        XCTAssertThrowsError(try w.run(deadline:now.addingTimeInterval(900)))
        XCTAssertFalse(stopped)
    }
    func testScheduledRestartDoesNotReportUpdating() throws {
        var phases: [ServerUpdateProgress.Phase] = []
        let w = RestartWorkflow(validate:{},warn:{_ in},stop:{},install:{},start:{},progress:{phases.append($0.phase)})
        try w.run(deadline:nil,updating:false); XCTAssertEqual(phases,[.stopping,.starting])
    }
    func testManualStopGenerationIsPerServerAndNotChangedByMaintenance() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let a = Lifecycle(paths:Paths(root:root,profileID:"a")), b = Lifecycle(paths:Paths(root:root,profileID:"b"))
        try a.paths.prepare(); try b.paths.prepare()
        try a.requestStop(wait:false,manual:false); XCTAssertEqual(a.manualStopGeneration,"")
        try b.requestStop(wait:false); XCTAssertNotEqual(b.manualStopGeneration,""); XCTAssertEqual(a.manualStopGeneration,"")
        try a.requestStop(wait:false); XCTAssertNotEqual(a.manualStopGeneration,"")
    }
    func testMaintenanceLockExcludesConcurrentUpdateAndStartThenReleases() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }; let paths = Paths(root:root); try paths.prepare()
        let lock = try MaintenanceLease(paths:paths)
        XCTAssertThrowsError(try MaintenanceLease(paths:paths)); XCTAssertThrowsError(try MaintenanceLease(paths:paths,exclusive:false))
        lock.release()
        let shared = try MaintenanceLease(paths:paths,exclusive:false)
        let another = try MaintenanceLease(paths:paths,exclusive:false)
        XCTAssertThrowsError(try MaintenanceLease(paths:paths)); shared.release(); another.release()
        let next = try MaintenanceLease(paths:paths); next.release()
    }
}
