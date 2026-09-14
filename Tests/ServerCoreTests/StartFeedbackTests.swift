import XCTest
@testable import ServerCore

final class StartFeedbackTests: XCTestCase {
    func testClickIsPendingBeforeCommandReturnsAndThroughStoppedSnapshots() {
        var feedback = StartFeedback()
        let now = Date()
        feedback.begin(now: now)
        XCTAssertTrue(feedback.pending)
        XCTAssertFalse(feedback.observe(running: false, now: now.addingTimeInterval(60)))
        XCTAssertTrue(feedback.pending) // A slow command is not mistaken for failed startup.
        feedback.commandFinished(success: true, now: now.addingTimeInterval(60))
        XCTAssertFalse(feedback.observe(running: false, now: now.addingTimeInterval(61)))
        XCTAssertTrue(feedback.pending)
        XCTAssertFalse(feedback.observe(running: true, now: now.addingTimeInterval(62)))
        XCTAssertFalse(feedback.pending)
    }
    func testFailureAndUnconfirmedStartDoNotLeavePermanentStartingState() {
        var feedback = StartFeedback()
        let now = Date()
        feedback.begin(now: now)
        feedback.commandFinished(success: false, now: now)
        XCTAssertFalse(feedback.pending)
        feedback.begin(now: now)
        feedback.commandFinished(success: true, now: now)
        XCTAssertTrue(feedback.observe(running: false, now: now.addingTimeInterval(30)))
        XCTAssertFalse(feedback.pending)
        XCTAssertFalse(feedback.observe(running: false, now: now.addingTimeInterval(31)))
    }
}
