import XCTest
@testable import ServerCore

final class RestartScheduleTests: XCTestCase {
    var calendar: Calendar { var c = Calendar(identifier:.gregorian); c.timeZone = TimeZone(identifier:"America/New_York")!; return c }
    func date(_ y: Int = 2026,_ m: Int = 9,_ d: Int = 19,_ h: Int = 3,_ min: Int = 0) -> Date {
        calendar.date(from:DateComponents(year:y,month:m,day:d,hour:h,minute:min))!
    }
    func testDailyIntervalAndWeekdays() throws {
        var s = RestartSchedule(); s.enabled = true
        XCTAssertEqual(s.next(after:date(),calendar:calendar),date(2026,9,20))
        s.frequency = .interval; s.anchor = date(); s.everyDays = 2
        XCTAssertEqual(s.next(after:date(),calendar:calendar),date(2026,9,21))
        s.frequency = .weekdays; s.weekdays = [6]
        XCTAssertEqual(s.next(after:date(),calendar:calendar),date(2026,9,25))
        s.weekdays = []; XCTAssertThrowsError(try s.validate())
    }
    func testDSTGapAndRepeatedHourAndCalendarInterval() {
        var s = RestartSchedule(); s.enabled = true; s.hour = 2; s.minute = 30
        XCTAssertEqual(s.occurrence(on:date(2026,3,8),calendar:calendar),date(2026,3,8,3))
        s.hour = 1; s.minute = 30
        let first = s.occurrence(on:date(2026,11,1),calendar:calendar)!
        XCTAssertEqual(calendar.timeZone.secondsFromGMT(for:first),-4*3600)
        XCTAssertEqual(s.next(after:first,calendar:calendar),date(2026,11,2,1,30))
        s.frequency = .interval; s.everyDays = 2; s.anchor = date(2026,3,7); s.hour = 3; s.minute = 0
        XCTAssertEqual(s.next(after:date(2026,3,7),calendar:calendar),date(2026,3,9))
    }
    func testReceiptDeduplicationAndMissedOccurrence() {
        var s = RestartSchedule(); s.enabled = true
        let due = date(), receipt = RestartReceipt(occurrence:s.key(for:due,calendar:calendar),due:due,state:"requested")
        XCTAssertEqual(ScheduledRestartPolicy.decide(schedule:s,receipt:receipt,now:due,running:true,players:2,canWarn:true,calendar:calendar),.none)
        XCTAssertEqual(ScheduledRestartPolicy.decide(schedule:s,receipt:nil,now:due.addingTimeInterval(3600),running:true,players:0,canWarn:true,calendar:calendar),.skip("Missed while manager was unavailable"))
    }
    func testAllPlayerPoliciesUnknownCountsAndStoppedServer() {
        var s = RestartSchedule(); s.enabled = true; s.players = .skip
        let due = date()
        func decide(_ count: Int?, running: Bool = true, warn: Bool = true, receipt: RestartReceipt? = nil) -> ScheduledRestartPolicy.Decision {
            ScheduledRestartPolicy.decide(schedule:s,receipt:receipt,now:due,running:running,players:count,canWarn:warn,calendar:calendar)
        }
        XCTAssertEqual(decide(0),.run(due)); XCTAssertEqual(decide(nil),.skip("Players connected or count unavailable"))
        XCTAssertEqual(decide(2),.skip("Players connected or count unavailable")); XCTAssertEqual(decide(0,running:false),.skip("Server is stopped"))
        s.players = .postpone; XCTAssertEqual(decide(nil),.waiting); XCTAssertEqual(decide(1),.waiting); XCTAssertEqual(decide(0),.run(due))
        s.players = .warn; XCTAssertEqual(decide(2,warn:false),.waiting)
        XCTAssertEqual(decide(0,warn:false),.run(due)); XCTAssertEqual(decide(2),.run(due.addingTimeInterval(900)))
    }
    func testMidnightWarningAndPendingRestartAfterRelaunch() {
        var s = RestartSchedule(); s.enabled = true; s.hour = 0; s.minute = 5
        let now = date(2026,9,19,23,50), due = date(2026,9,20,0,5)
        XCTAssertEqual(ScheduledRestartPolicy.decide(schedule:s,receipt:nil,now:now,running:true,players:2,canWarn:true,calendar:calendar),.run(due))
        s.players = .postpone
        let receipt = RestartReceipt(occurrence:s.key(for:due,calendar:calendar),due:due,state:"waiting")
        XCTAssertEqual(ScheduledRestartPolicy.decide(schedule:s,receipt:receipt,now:due.addingTimeInterval(3600),running:true,players:0,canWarn:true,calendar:calendar),.run(due.addingTimeInterval(3600)))
    }
    func testClaimRejectsChangedScheduleAndDuplicateOccurrence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = try Store(paths:Paths(root:root)); let profile = Profile()
        var s = RestartSchedule(); s.enabled = true
        try store.update { $0.profiles = [profile]; $0.restartSchedules = [profile.id:s] }
        let configuration = try XCTUnwrap(store.load().restartSchedules?[profile.id])
        let receipt = RestartReceipt(occurrence:"2026-09-19",due:date(),state:"requested")
        var changed = configuration; changed.hour = 4
        XCTAssertFalse(try store.claimScheduledRestart(id:profile.id,configuration:changed,receipt:receipt))
        XCTAssertTrue(try store.claimScheduledRestart(id:profile.id,configuration:configuration,receipt:receipt))
        XCTAssertFalse(try store.claimScheduledRestart(id:profile.id,configuration:configuration,receipt:receipt))
    }
    func testScheduleRoundTripAndLegacyDatabase() throws {
        let legacy = Data("{\"schema\":2,\"profiles\":[],\"selected\":\"\",\"autostart\":false,\"monitorAtLogin\":false}".utf8)
        var db = try JSONDecoder().decode(Database.self,from:legacy)
        XCTAssertNil(db.restartSchedules)
        var s = RestartSchedule(); s.enabled = true; s.weekdays = [1,4,7]; db.restartSchedules = ["a":s]
        XCTAssertEqual(try JSONDecoder().decode(Database.self,from:encode(db)).restartSchedules?["a"],s)
    }
}
