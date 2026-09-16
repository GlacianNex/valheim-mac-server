import Foundation
import XCTest
@testable import ServerCore

final class ServerLogReaderTests: XCTestCase {
    func testLargeLogRetainsReadinessAndReconstructsAfterManagerRestart() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let log = "Session with join code 123456 is active with 0 player(s)\n" + String(repeating: "World save completed\n", count: 30_000) + "Connections 2 ZDOS:42\n"
        try Data(log.utf8).write(to: url)
        for reader in [ServerLogReader(), ServerLogReader()] {
            let value = reader.read(url)
            XCTAssertTrue(value.online); XCTAssertEqual(value.code, "123456"); XCTAssertEqual(value.players, "2")
            XCTAssertEqual(reader.read(url).code, "123456")
        }
    }
    func testAppendedPartialLinesAndDisconnectThenZero() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("Session with join code 123456 is active with 1 player(s)\n".utf8).write(to: url)
        let reader = ServerLogReader(); XCTAssertEqual(reader.read(url).players, "1")
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("Player connection lost server Fixture, now 1 player(s)\nConnections ".utf8))
        XCTAssertEqual(reader.read(url).players, "")
        try handle.write(contentsOf: Data("0 ZDOS:42\n".utf8))
        XCTAssertEqual(reader.read(url).players, "0")
        try handle.write(contentsOf: Data("Session with join code 654321 is active with 2 player(s)\n".utf8))
        XCTAssertEqual(reader.read(url).code, "654321"); XCTAssertEqual(reader.read(url).players, "2")
    }
    func testExplicitZeroOnDisconnectRemainsKnownAfterRefreshAndRelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("Session with join code 123456 is active with 1 player(s)\nPlayer connection lost server Fixture, now 0 player(s)\n".utf8).write(to: url)
        let reader = ServerLogReader()
        XCTAssertEqual(reader.read(url).players, "0")
        XCTAssertEqual(reader.read(url).players, "0")
        XCTAssertEqual(ServerLogReader().read(url).players, "0")
        XCTAssertEqual(Lifecycle.parseLog("Player connection lost server Fixture, now 10 player(s)\n").players, "")
    }
    func testTruncationReplacementAndMissingLogClearState() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let online = Data("Session with join code 123456 is active with 1 player(s)\n".utf8)
        try online.write(to: url)
        let reader = ServerLogReader(); XCTAssertTrue(reader.read(url).online)
        let file = try FileHandle(forWritingTo: url); try file.truncate(atOffset: 0); try file.close()
        XCTAssertFalse(reader.read(url).online)
        try online.write(to: url); XCTAssertEqual(reader.read(url).code, "123456")
        try Data(String(repeating: "Initializing\n", count: 20).utf8).write(to: url, options: .atomic)
        XCTAssertEqual(reader.read(url).code, "")
        try FileManager.default.removeItem(at: url); XCTAssertFalse(reader.read(url).online)
    }
}
