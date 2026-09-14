import XCTest
import Foundation
import Darwin
@testable import ServerCore

final class CoreTests: XCTestCase {
    var root: URL!
    var paths: Paths!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vsm-tests-" + UUID().uuidString)
        paths = Paths(root: root); try paths.prepare()
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func profile(_ name: String = "Test World") -> Profile {
        var p = Profile(); p.label = name; p.name = name; p.world = "TestWorld"; p.password = "test-only-password"; return p
    }
    func testFreshStoreHasNoPersonalDefaults() throws {
        let store = try Store(paths: paths)
        XCTAssertTrue(try store.load().profiles.isEmpty)
        XCTAssertFalse(try store.load().autostart)
        XCTAssertThrowsError(try store.selected())
    }
    func testCreationPreservesSelectionAndSaves() throws {
        let store = try Store(paths: paths), first = profile(), second = profile("Second")
        try store.save(first)
        let sentinel = store.saveDirectory(first).appendingPathComponent("preserve.txt")
        try Data("original".utf8).write(to: sentinel)
        try store.save(second)
        XCTAssertEqual(try store.load().selected, first.id)
        XCTAssertEqual(try store.load().profiles, [first, second])
        XCTAssertEqual(try String(contentsOf: sentinel), "original")
        XCTAssertNotEqual(store.saveDirectory(first), store.saveDirectory(second))
    }
    func testExistingWorldCannotBeRenamed() throws {
        let store = try Store(paths: paths); var p = profile(); try store.save(p)
        p.world = "Other"
        XCTAssertThrowsError(try store.save(p))
        XCTAssertEqual(try store.selected().world, "TestWorld")
    }
    func testInvalidNamesAndNumericValues() throws {
        var p = profile(); p.world = "../escape"; XCTAssertThrowsError(try p.validate())
        p = profile(); p.id = "../escape"; XCTAssertThrowsError(try p.validate())
        p = profile(); p.port = 65535; XCTAssertThrowsError(try p.validate())
        p = profile(); p.password = "1234"; XCTAssertThrowsError(try p.validate())
        p = profile(); p.name = "A TEST-ONLY-PASSWORD server"; XCTAssertThrowsError(try p.validate())
    }
    func testArgumentsStayLiteralAndManagedOverridesFail() throws {
        var p = profile(); p.name = "Name & $(literal)"; p.extra = "-custom 'hello world'"
        let args = try p.arguments(saveDirectory: root.appendingPathComponent("space here"), log: root.appendingPathComponent("test.log"))
        XCTAssertEqual(args[args.firstIndex(of: "-name")! + 1], p.name)
        XCTAssertEqual(args.suffix(2), ["-custom", "hello world"])
        p.extra = "-world Another"; XCTAssertThrowsError(try p.validate())
        p.extra = "-logFile=/tmp/override"; XCTAssertThrowsError(try p.validate())
        p.extra = "'unclosed"; XCTAssertThrowsError(try p.validate())
    }
    func testFormRoundTripKeepsRawOptions() throws {
        var p = profile(); p.modifiers = ["Resources": "muchmore", "DeathPenalty": "hard"]
        p.flags = ["nomap": true]
        let roundTrip = try Profile(form: p.form)
        XCTAssertEqual(roundTrip.modifiers["Resources"], "muchmore")
        XCTAssertEqual(roundTrip.flags["nomap"], true)
        XCTAssertEqual(roundTrip.port, 2456)
    }
    func modernSource() throws -> URL {
        let source = root.appendingPathComponent("source/TestWorld")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for name in ["_main.1.db2", "_main.1.fwl2", "_main.1.ok", "chunk.chunk"] { try Data("fixture".utf8).write(to: source.appendingPathComponent(name)) }
        return source
    }
    func testModernImportCopiesAndPreservesOriginal() throws {
        let source = try modernSource(), store = try Store(paths: paths), p = profile()
        try store.save(p, importSource: source)
        let copied = store.saveDirectory(p).appendingPathComponent("worlds_local/TestWorld/chunk.chunk")
        XCTAssertEqual(try Data(contentsOf: copied), Data("fixture".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("chunk.chunk").path))
    }
    func testZipImport() throws {
        let source = try modernSource(), archive = root.appendingPathComponent("world.zip")
        try checkCommand("/usr/bin/ditto", ["-c", "-k", "--keepParent", source.path, archive.path])
        let store = try Store(paths: paths), p = profile(); try store.save(p, importSource: archive)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.saveDirectory(p).appendingPathComponent("worlds_local/TestWorld/_main.1.ok").path))
    }
    func testSymlinkImportIsRejectedWithoutCreatingProfile() throws {
        let source = try modernSource()
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("link"), withDestinationURL: root)
        let store = try Store(paths: paths)
        XCTAssertThrowsError(try store.save(profile(), importSource: source))
        XCTAssertTrue(try store.load().profiles.isEmpty)
    }
    func testSymlinkZipRejectedBeforeExtraction() throws {
        let source = try modernSource(), archive = root.appendingPathComponent("links.zip")
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("link"), withDestinationURL: root)
        try checkCommand("/usr/bin/ditto", ["-c", "-k", "--keepParent", source.path, archive.path])
        XCTAssertThrowsError(try Store(paths: paths).save(profile(), importSource: archive))
    }
    func testIncompleteImportRollsBack() throws {
        let source = try modernSource(); try FileManager.default.removeItem(at: source.appendingPathComponent("_main.1.ok"))
        let store = try Store(paths: paths), p = profile()
        XCTAssertThrowsError(try store.save(p, importSource: source))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.saveDirectory(p).path))
        XCTAssertTrue(try store.load().profiles.isEmpty)
    }
    func testUnrelatedProcessIsNeverOwned() throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sleep"); process.arguments = ["20"]; try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let record = RunningRecord(pid: process.processIdentifier, executable: "/bin/sleep", started: Lifecycle.birth(process.processIdentifier), profile: "unrelated", log: "/tmp/unused")
        XCTAssertFalse(Lifecycle(paths: paths).owns(record))
        try atomicWrite(encode(record), to: paths.file("running.json"))
        try Lifecycle(paths: paths).requestStop(wait: false)
        XCTAssertTrue(process.isRunning)
    }
    func testActiveServiceRejectsSwitchAndEdit() throws {
        let store = try Store(paths: paths), p = profile(); try store.save(p)
        let fd = open(paths.file("service.lock").path, O_CREAT | O_RDWR, 0o600)
        defer { flock(fd, LOCK_UN); close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        XCTAssertThrowsError(try store.select(p.id))
        XCTAssertThrowsError(try store.save(p))
    }
    func testLogParserUsesMostRecentCount() {
        let status = Lifecycle.parseLog("Session \"Fixture\" with join code 123456 is active with 0 player(s)\nnow 2 player(s)\nnow 1 player(s)")
        XCTAssertTrue(status.online); XCTAssertEqual(status.players, "1"); XCTAssertEqual(status.code, "123456")
        XCTAssertFalse(Lifecycle.parseLog("Initializing").online)
        XCTAssertEqual(Lifecycle.parseLog("Game server connected").players, "")
    }
    func testIsolatedPathsCannotRegisterLoginItems() throws {
        XCTAssertTrue(paths.isDevelopment)
        let login = LoginItems(paths: paths)
        XCTAssertThrowsError(try login.monitorAtLogin(true))
        XCTAssertThrowsError(try login.serverAtLogin(true))
        XCTAssertThrowsError(try login.start())
    }
    func testOccupiedPortIsRejected() throws {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        defer { close(fd) }
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = 0; address.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &address) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        XCTAssertEqual(bound, 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &address) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(fd, $0, &length) } }
        XCTAssertThrowsError(try Lifecycle.checkPorts(min(65534, Int(UInt16(bigEndian: address.sin_port)))))
    }
    func testProfileFilePermissions() throws {
        try Store(paths: paths).save(profile())
        let permissions = try FileManager.default.attributesOfItem(atPath: paths.file("profiles.json").path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }
}
