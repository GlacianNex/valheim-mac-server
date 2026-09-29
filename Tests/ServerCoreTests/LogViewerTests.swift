import XCTest
@testable import ServerCore
final class LogViewerTests:XCTestCase {
    func testReadableFilterPreservesSpacingAndCleansTerminalCodes() {
        XCTAssertEqual(LogViewer.readable("\u{1B}[31mError\u{1B}[0m\r\n  at Stack\r\nOK\0",filter:"error"),"Error")
        XCTAssertEqual(LogViewer.readable("a\r\n  b\rprogress"),"a\n  b\nprogress")
    }
    func testLogSourcesAreSeparateAndMaintenanceIsScoped() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let paths = Paths(root:root,profileID:"test-server")
        try paths.prepare(); try FileManager.default.createDirectory(at:root.appendingPathComponent("logs"),withIntermediateDirectories:true)
        let server = paths.logs.appendingPathComponent("server-test.log")
        try Data("SERVER ONLY".utf8).write(to:server)
        try Data((server.path + "\n").utf8).write(to:paths.file("latest-log"))
        try Data("[test-server] saved\n[other] private\n[fleet] update".utf8).write(to:root.appendingPathComponent("logs/maintenance.log"))
        XCTAssertEqual(LogViewer.read(paths:paths,manager:false),"SERVER ONLY")
        let manager = LogViewer.read(paths:paths,manager:true)
        XCTAssertTrue(manager.contains("saved")); XCTAssertTrue(manager.contains("update"))
        XCTAssertFalse(manager.contains("private")); XCTAssertFalse(manager.contains("SERVER ONLY"))
    }
    func testMissingLogsAndBoundedRead() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let paths = Paths(root:root); try paths.prepare()
        XCTAssertEqual(LogViewer.read(paths:paths,manager:false),"")
        let file = paths.logs.appendingPathComponent("large.log")
        try Data(String(repeating:"x",count:LogViewer.limit * 2).utf8).write(to:file)
        try Data(file.path.utf8).write(to:paths.file("latest-log"))
        XCTAssertEqual(LogViewer.read(paths:paths,manager:false).utf8.count,LogViewer.limit)
    }
}
