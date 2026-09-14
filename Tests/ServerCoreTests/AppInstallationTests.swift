import XCTest
import Foundation
import Darwin
@testable import ServerCore

final class AppInstallationTests: XCTestCase {
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
