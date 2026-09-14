import XCTest
import Foundation
import Darwin
@testable import ServerCore

final class AppInstallationTests: XCTestCase {
    func testReplacementRollsBackWhenInstallingNewCopyFails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let installed = root.appendingPathComponent("Installed.app"), staged = root.appendingPathComponent("New.app"), backup = root.appendingPathComponent("Previous.app")
        try Data("old".utf8).write(to: installed); try Data("new".utf8).write(to: staged)
        XCTAssertThrowsError(try AppInstallation.replacePrepared(staged, destination: installed, backup: backup) { source, destination in
            if source == staged { throw MonitorError("Simulated disk failure") }
            try FileManager.default.moveItem(at: source, to: destination)
        })
        XCTAssertEqual(try String(contentsOf: installed), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        try AppInstallation.replacePrepared(staged, destination: installed, backup: backup)
        XCTAssertEqual(try String(contentsOf: installed), "new")
        XCTAssertEqual(try String(contentsOf: backup), "old")
    }

    func testUpdateRejectsOlderWrongAndUnsignedAppsBeforeClosingMonitor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func fixture(_ name: String, _ version: String, identifier: String = AppInstallation.bundleIdentifier) throws -> URL {
            let app = root.appendingPathComponent(name + ".app")
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version], format: .xml, options: 0)
            try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
            return app
        }
        let installed = try fixture("Installed", "0.1.3")
        for (name, version) in [("Older", "0.1.2"), ("Same", "0.1.3"), ("Unsigned", "0.1.10")] {
            let source = try fixture(name, version)
            XCTAssertThrowsError(try AppInstallation.update(from: source, to: installed) { XCTFail("Must validate before closing the old monitor") })
            XCTAssertEqual(try AppInstallation.version(at: installed), "0.1.3")
        }
        let unrelated = try fixture("Other", "9.0.0", identifier: "other.app")
        XCTAssertThrowsError(try AppInstallation.update(from: unrelated, to: installed) {})
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".valheim-update-") })
    }

    func testApprovedCopyClearsOnlyCopiedQuarantine() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Download.app")
        let contents = source.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let executable = contents.appendingPathComponent("executable")
        try Data("app fixture".utf8).write(to: executable)
        let outside = root.appendingPathComponent("outside")
        try Data("untouched".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: contents.appendingPathComponent("link"), withDestinationURL: outside)
        for url in [source, executable, outside] {
            XCTAssertEqual(setxattr(url.path, "com.apple.quarantine", "0083;12345678;Test;", 19, 0, 0), 0)
        }
        XCTAssertEqual(setxattr(executable.path, "test.preserved", "yes", 3, 0, 0), 0)
        let destination = root.appendingPathComponent("Installed.app")
        try AppInstallation.copy(from: source, to: destination)
        for url in [destination, destination.appendingPathComponent("Contents/executable")] {
            XCTAssertEqual(getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0), -1)
            XCTAssertEqual(errno, ENOATTR)
        }
        for url in [source, executable, outside] {
            XCTAssertGreaterThan(getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0), 0)
        }
        XCTAssertEqual(getxattr(destination.appendingPathComponent("Contents/executable").path, "test.preserved", nil, 0, 0, 0), 3)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Contents/executable")), Data("app fixture".utf8))
        XCTAssertThrowsError(try AppInstallation.copy(from: source, to: destination))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Contents/executable")), Data("app fixture".utf8))
    }

    func testCopyWithoutQuarantineSucceeds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Download.app")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent("Installed.app")
        try AppInstallation.copy(from: source, to: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }
}
