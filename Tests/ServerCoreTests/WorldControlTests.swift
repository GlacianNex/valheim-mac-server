import XCTest
import Foundation
import Darwin
@testable import ServerCore

final class WorldControlTests: XCTestCase {
    func fixture(_ body: (Paths, URL, Profile) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = try Store(paths:Paths(root:root)); var profile = Profile()
        profile.label = "Backup test"; profile.name = "Backup test"; profile.world = "BackupWorld"; profile.password = "testing123"
        let id = try store.save(profile); let paths = store.servicePaths(id)
        let world = store.saveDirectory(profile).appendingPathComponent("worlds_local")
        try FileManager.default.createDirectory(at:world,withIntermediateDirectories:true)
        try Data("original db".utf8).write(to:world.appendingPathComponent("BackupWorld.db"))
        try Data("original metadata".utf8).write(to:world.appendingPathComponent("BackupWorld.fwl"))
        try body(paths,world,profile)
    }
    func testRoundTripRestoreAndRecoveryPreserveSettings() throws {
        try fixture { paths, world, _ in
            let backups = WorldBackups(paths:paths)
            let profileBefore = try Data(contentsOf:paths.file("profiles.json"))
            let saved = try backups.create(name:"Before raid")
            try Data("new progress".utf8).write(to:world.appendingPathComponent("BackupWorld.db"))
            try backups.restore(id:saved.id)
            XCTAssertEqual(try String(contentsOf:world.appendingPathComponent("BackupWorld.db")),"original db")
            let recovery = try XCTUnwrap(backups.list().first { $0.name.hasPrefix("Before restore") })
            XCTAssertEqual(try String(contentsOf:backups.directory.appendingPathComponent(recovery.id + "/worlds_local/BackupWorld.db")),"new progress")
            XCTAssertEqual(try Data(contentsOf:paths.file("profiles.json")),profileBefore)
            XCTAssertEqual(try backups.list().count,2)
        }
    }
    func testCorruptAndTraversalRestoreAreRejectedWithoutChangingWorld() throws {
        try fixture { paths, world, _ in
            let backups = WorldBackups(paths:paths); let saved = try backups.create(name:"Saved")
            try Data("bad".utf8).write(to:backups.directory.appendingPathComponent(saved.id + "/worlds_local/BackupWorld.db"))
            XCTAssertThrowsError(try backups.restore(id:saved.id))
            XCTAssertThrowsError(try backups.restore(id:"../../worlds"))
            XCTAssertEqual(try String(contentsOf:world.appendingPathComponent("BackupWorld.db")),"original db")
        }
    }
    func testActiveLockPreventsBackupAndRestore() throws {
        try fixture { paths, _, _ in
            let backups = WorldBackups(paths:paths); let item = try backups.create(name:"Saved")
            let fd = open(paths.file("service.lock").path,O_CREAT | O_RDWR,0o600)
            XCTAssertGreaterThanOrEqual(fd,0); defer { close(fd) }; XCTAssertEqual(flock(fd,LOCK_EX | LOCK_NB),0)
            XCTAssertThrowsError(try backups.create(name:"While running"))
            XCTAssertThrowsError(try backups.restore(id:item.id))
        }
    }
    func testSettingsAndSymbolicLinks() throws {
        try fixture { paths, world, _ in
            var settings = WorldMessageSettings(); settings.welcome = "Welcome!"; settings.announcements = ["Raid night starts soon"]
            try settings.save(paths:paths)
            XCTAssertEqual(try WorldMessageSettings.load(paths:paths).welcome,"Welcome!")
            settings.welcome = "bad\nmessage"; XCTAssertThrowsError(try settings.save(paths:paths))
            XCTAssertEqual(try WorldMessageSettings.load(paths:paths).welcome,"Welcome!")
            try FileManager.default.createSymbolicLink(at:world.appendingPathComponent("linked"),withDestinationURL:paths.file("profiles.json"))
            XCTAssertThrowsError(try WorldBackups(paths:paths).create(name:"Links"))
        }
    }
}
