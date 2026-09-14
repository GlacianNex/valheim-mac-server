import XCTest
@testable import ServerCore

final class InstallationProgressTests: XCTestCase {
    func testRealDownloadOutputBecomesFriendlyProgress() {
        let log = "[Monitor] Connecting to Valve…\n Update state (0x61) downloading, progress: 28.24 (584471130 / 2069392147)\r\nSteam internal diagnostic\n"
        let result = InstallationProgress.latest(in: log)
        XCTAssertEqual(result?.message, "Downloading server files — 28%")
        XCTAssertEqual(result?.percent, 28.24)
    }
    func testPhasesDoNotShowCodesOrStalePercentages() {
        for (state, expected) in [("verifying", "Checking server files"), ("preallocating", "Preparing space for server files"), ("committing", "Installing server files")] {
            XCTAssertEqual(InstallationProgress.latest(in: "Update state (0x5) \(state), progress: 50.00 (5 / 10)")?.message, expected + " — 50%")
        }
        let result = InstallationProgress.latest(in: "Update state (0x61) downloading, progress: 100.00\n[Monitor] Finishing installation…\n")
        XCTAssertEqual(result?.message, "Finishing installation…")
        XCTAssertNil(result?.percent)
        XCTAssertNil(InstallationProgress.latest(in: "opaque diagnostic 0x61"))
        XCTAssertNil(InstallationProgress.latest(in: "Update state (0x61) downloading, progress: 999.00")?.percent)
    }
    func testDownloaderBootstrapAndUnknownStatesStayReadable() {
        XCTAssertEqual(InstallationProgress.latest(in: "[ 38%] Downloading update (8,973 of 15,667 KB)...")?.message, "Updating Valve’s download tool…")
        XCTAssertEqual(InstallationProgress.latest(in: "Update state (0x999) unknown")?.message, "Preparing server files…")
        XCTAssertEqual(InstallationProgress.latest(in: "Success! App '896660' fully installed.")?.message, "Finishing installation…")
    }
}
