import XCTest
import CryptoKit
import Darwin
@testable import ServerCore

final class ManagementDefaultsTests: XCTestCase {
    func testStoppedMigrationPreservesWorldAndExplicitOptOutAndRetriesSafely() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store = try Store(paths:Paths(root:root))
        var profile = Profile(); profile.name = "Legacy"; profile.label = "Legacy"; profile.world = "Existing"; profile.password = "testing123"
        let id = try store.save(profile)
        try store.update { $0.managedServers = nil; $0.automaticServerUpdates = false }
        let paths = store.servicePaths(id)
        let world = store.saveDirectory(profile).appendingPathComponent("worlds_local/Existing.db")
        try atomicWrite(Data("existing world data".utf8),to:world)
        // No runtime installed: leave settings untouched until native setup completes.
        XCTAssertFalse(try ManagementDefaults.installWhileStopped(paths:paths,package:nil))
        for name in ["valheim_server/Valheim","valheim_server/libmono-native.dylib","steamapps/appmanifest_896660.acf"] {
            try atomicWrite(Data((name.hasSuffix("acf") ? "\"buildid\" \"100\"" : "runtime").utf8),to:paths.server.appendingPathComponent(name))
        }
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:paths.executable.path)
        let package = root.appendingPathComponent("package")
        var hashes: [String:String] = [:]
        for name in ["BepInEx/core/BepInEx.dll","BepInEx/core/BepInEx.Preloader.dll","BepInEx/plugins/ManagerRcon/ManagerRcon.dll","libdoorstop.dylib"] {
            let data = Data(name.utf8); try atomicWrite(data,to:package.appendingPathComponent(name))
            hashes[name] = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
        }
        try atomicWrite(encode(ManagedServer.Manifest(version:"1",files:hashes)),to:package.appendingPathComponent("manifest.json"))
        let before = try Data(contentsOf:paths.file("profiles.json"))
        // A service lock represents running/startup, including an older manager's service.
        let fd = open(paths.file("service.lock").path,O_CREAT | O_RDWR,0o600)
        XCTAssertGreaterThanOrEqual(fd,0); defer { close(fd) }
        XCTAssertEqual(flock(fd,LOCK_EX | LOCK_NB),0)
        XCTAssertFalse(try ManagementDefaults.installWhileStopped(paths:paths,package:package))
        XCTAssertEqual(try Data(contentsOf:paths.file("profiles.json")),before)
        XCTAssertFalse(FileManager.default.fileExists(atPath:ManagedServer(paths:paths).root.path))
        flock(fd,LOCK_UN)
        XCTAssertThrowsError(try ManagementDefaults.installWhileStopped(paths:paths,package:nil))
        XCTAssertEqual(try Data(contentsOf:paths.file("profiles.json")),before)
        XCTAssertTrue(try ManagementDefaults.installWhileStopped(paths:paths,package:package))
        XCTAssertEqual(try store.load().managedServers?[id],true)
        XCTAssertEqual(try store.load().automaticServerUpdates,false)
        XCTAssertEqual(try Data(contentsOf:world),Data("existing world data".utf8))
        let installation = ManagedServer(paths:paths).root.appendingPathComponent("installation.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath:installation.path))
        XCTAssertFalse(try ManagementDefaults.installWhileStopped(paths:paths,package:package))
        try store.update { $0.managedServers?[id] = false }
        XCTAssertFalse(try ManagementDefaults.installWhileStopped(paths:paths,package:package))
        XCTAssertFalse(try ManagementDefaults.installBeforeLaunch(paths:paths,package:package))
        XCTAssertEqual(try store.load().managedServers?[id],false)
        // The service-start path handles a legacy server that was running during app migration.
        try store.update { $0.managedServers?.removeValue(forKey:id) }
        XCTAssertEqual(flock(fd,LOCK_EX | LOCK_NB),0)
        XCTAssertTrue(try ManagementDefaults.installBeforeLaunch(paths:paths,package:package))
        flock(fd,LOCK_UN)
        XCTAssertEqual(try store.load().managedServers?[id],true)
        XCTAssertEqual(try Data(contentsOf:world),Data("existing world data".utf8))
    }
}
