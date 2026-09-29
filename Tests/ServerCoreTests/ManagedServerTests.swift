import XCTest
import CryptoKit
@testable import ServerCore

final class ManagedServerTests: XCTestCase {
    func testPackageInstallPreservesCredentialsAndCustomConfigAcrossUpgrade() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = Paths(root: root, profileID: "test-server")
        try paths.prepare()
        let fm = FileManager.default
        for name in ["valheim_server/Valheim", "valheim_server/libmono-native.dylib", "steamapps/appmanifest_896660.acf"] {
            let data = name.hasSuffix("acf") ? Data("\"buildid\" \"100\"".utf8) : Data("runtime".utf8)
            try atomicWrite(data, to: paths.server.appendingPathComponent(name))
        }
        try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:paths.executable.path)
        let package = root.appendingPathComponent("package")
        let names = ["BepInEx/core/BepInEx.dll", "BepInEx/core/BepInEx.Preloader.dll", "BepInEx/plugins/ManagerRcon/ManagerRcon.dll", "libdoorstop.dylib", "BepInEx/plugins/Jotunn/Jotunn.dll", "BepInEx/plugins/NetworkPerformanceSystem/NetworkPerformanceSystem.dll"]
        var hashes: [String:String] = [:]
        for name in names {
            let data = Data(name.utf8); try atomicWrite(data,to:package.appendingPathComponent(name))
            hashes[name] = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
        }
        func manifest(_ version: String) throws { try atomicWrite(encode(ManagedServer.Manifest(version:version,files:hashes)),to:package.appendingPathComponent("manifest.json")) }
        try manifest("1")
        let managed = ManagedServer(paths:paths)
        try managed.prepare(package:package)
        let credential = try Data(contentsOf:managed.root.appendingPathComponent("credential"))
        let custom = managed.runtime.appendingPathComponent("BepInEx/config/custom.cfg")
        try atomicWrite(Data("keep-me".utf8),to:custom)
        try atomicWrite(Data("obsolete".utf8),to:managed.runtime.appendingPathComponent("BepInEx/core/obsolete.dll"))
        try manifest("2"); try managed.prepare(package:package)
        XCTAssertFalse(fm.fileExists(atPath:managed.runtime.appendingPathComponent("BepInEx/core/obsolete.dll").path))
        XCTAssertEqual(try Data(contentsOf:managed.root.appendingPathComponent("credential")),credential)
        XCTAssertEqual(try String(contentsOf:custom),"keep-me")
        XCTAssertTrue(fm.fileExists(atPath:managed.root.appendingPathComponent("previous-runtime").path))
        // Corrupt package must not mutate the installed runtime or credentials.
        try atomicWrite(Data("corrupt".utf8),to:package.appendingPathComponent(names[0]))
        XCTAssertThrowsError(try managed.prepare(package:package))
        XCTAssertEqual(try String(contentsOf:custom),"keep-me")
        try managed.rollbackFailedStart()
        XCTAssertEqual(try String(contentsOf:custom),"keep-me")
        let old = try JSONDecoder().decode(ManagedServer.Installation.self,from:Data(contentsOf:managed.root.appendingPathComponent("installation.json")))
        XCTAssertTrue(old.package.hasPrefix("1:"))
        try atomicWrite(Data(names[0].utf8),to:package.appendingPathComponent(names[0]))
        XCTAssertThrowsError(try managed.prepare(package:package)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Management startup failed"))
        }
    }
    func testIndependentPluginSelectionReplacesBinariesAndPreservesSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = Paths(root: root, profileID: "selection-test")
        let store = try Store(paths: paths)
        XCTAssertFalse(ManagedServer(paths: paths).networkingEnabled)
        for name in ["valheim_server/Valheim", "valheim_server/libmono-native.dylib", "steamapps/appmanifest_896660.acf"] {
            try atomicWrite(Data((name.hasSuffix("acf") ? "\"buildid\" \"100\"" : "runtime").utf8), to: paths.server.appendingPathComponent(name))
        }
        try FileManager.default.setAttributes([.posixPermissions:0o700], ofItemAtPath:paths.executable.path)
        let package = root.appendingPathComponent("package")
        var hashes: [String:String] = [:]
        for name in ["BepInEx/core/BepInEx.dll", "BepInEx/core/BepInEx.Preloader.dll", "libdoorstop.dylib", "BepInEx/plugins/ManagerRcon/ManagerRcon.dll", "BepInEx/plugins/Jotunn/Jotunn.dll", "BepInEx/plugins/NetworkPerformanceSystem/NetworkPerformanceSystem.dll"] {
            let data = Data(name.utf8); try atomicWrite(data, to:package.appendingPathComponent(name))
            hashes[name] = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
        }
        try atomicWrite(encode(ManagedServer.Manifest(version:"1",files:hashes)),to:package.appendingPathComponent("manifest.json"))
        let managed = ManagedServer(paths:paths)
        var identities = Set<String>()
        for (management,networking) in [(true,false),(true,true),(false,true),(true,false)] {
            try store.update { $0.managedServers = ["selection-test":management]; $0.networkOptimizations = ["selection-test":networking] }
            XCTAssertEqual(managed.enabled,management); XCTAssertEqual(managed.networkingEnabled,networking)
            XCTAssertTrue(managed.loaderEnabled)
            try managed.prepare(package:package,management:management,networking:networking)
            let plugins = managed.runtime.appendingPathComponent("BepInEx/plugins")
            XCTAssertEqual(FileManager.default.fileExists(atPath:plugins.appendingPathComponent("ManagerRcon/ManagerRcon.dll").path),management)
            XCTAssertEqual(FileManager.default.fileExists(atPath:plugins.appendingPathComponent("NetworkPerformanceSystem/NetworkPerformanceSystem.dll").path),networking)
            XCTAssertTrue(FileManager.default.fileExists(atPath:plugins.appendingPathComponent("Jotunn/Jotunn.dll").path))
            let config = managed.runtime.appendingPathComponent("BepInEx/config/custom.cfg")
            if identities.isEmpty { try atomicWrite(Data("preserve".utf8),to:config) }
            XCTAssertEqual(try String(contentsOf:config),"preserve")
            let installed = try JSONDecoder().decode(ManagedServer.Installation.self,from:Data(contentsOf:managed.root.appendingPathComponent("installation.json")))
            identities.insert(installed.package)
        }
        // Every profile uses this policy, including upgrades of an existing 60-slot config.
        for id in ["new-profile-a", "new-profile-b"] {
            let other = ManagedServer(paths:Paths(root:root,profileID:id))
            try other.prepare(package:package,management:true,networking:true)
            let config = other.runtime.appendingPathComponent("BepInEx/config/MidnightsFX.NetworkPerformanceSystem.cfg")
            XCTAssertTrue(try String(contentsOf:config).contains("Enable Player Limit Override = false"))
            try atomicWrite(Data("[Player Limit]\nEnable Player Limit Override = true\nMax Players = 60\n[Send Window]\nTarget Rate KBps = 150\n".utf8),to:config)
            let old = ManagedServer.Installation(package:"old-policy",build:"100")
            try atomicWrite(encode(old),to:other.root.appendingPathComponent("installation.json"))
            try other.prepare(package:package,management:true,networking:true)
            let updated = try String(contentsOf:config)
            XCTAssertTrue(updated.contains("Enable Player Limit Override = false"))
            XCTAssertTrue(updated.contains("Target Rate KBps = 150"))
        }
        XCTAssertEqual(identities.count,3)
        try store.update { $0.managedServers = ["selection-test":false]; $0.networkOptimizations = ["selection-test":false] }
        XCTAssertFalse(managed.loaderEnabled)
    }
    func testNetworkingKeepsVanillaCapacityWithoutChangingOtherTuning() {
        let existing = "[Player Limit]\nEnable Player Limit Override = true\nMax Players = 60\n[Send Window]\nTarget Rate KBps = 150\n"
        let result = ManagedServer.vanillaCapacityConfig(existing)
        XCTAssertTrue(result.contains("Enable Player Limit Override = false"))
        XCTAssertTrue(result.contains("Target Rate KBps = 150"))
        XCTAssertEqual(result, ManagedServer.vanillaCapacityConfig(result))
        XCTAssertTrue(ManagedServer.vanillaCapacityConfig("").contains("[Player Limit]\nEnable Player Limit Override = false"))
        XCTAssertTrue(ManagedServer.vanillaCapacityConfig("[Player Limit]\nMax Players = 60\n[Other]\nX = 1").contains("[Player Limit]\nEnable Player Limit Override = false"))
    }
    func testExplicitCapacityAndReturnToDefault() throws {
        let custom = ManagedServer.capacityConfig("",maxPlayers:20)
        XCTAssertTrue(custom.contains("Enable Player Limit Override = true"))
        XCTAssertTrue(custom.contains("Max Players = 20"))
        XCTAssertTrue(ManagedServer.capacityConfig(custom,maxPlayers:nil).contains("Enable Player Limit Override = false"))
        XCTAssertNotEqual(ManagedServer.selectionIdentity("v",management:true,networking:true),ManagedServer.selectionIdentity("v",management:true,networking:true,maxPlayers:20))
        var profile = Profile(); profile.label = "Test"; profile.name = "Test"; profile.world = "Test"; profile.password = "abcde"
        var old = profile.form; old.removeValue(forKey:"maxPlayers")
        XCTAssertNil(try Profile(form:old).maxPlayers)
        old["maxPlayers"] = "20"; XCTAssertEqual(try Profile(form:old).maxPlayers,20)
        old["maxPlayers"] = "10"; XCTAssertNil(try Profile(form:old).maxPlayers)
        old["maxPlayers"] = "61"; XCTAssertThrowsError(try Profile(form:old))
        let legacy = try JSONSerialization.jsonObject(with:encode(profile)) as! [String:Any]
        XCTAssertNil(try JSONDecoder().decode(Profile.self,from:JSONSerialization.data(withJSONObject:legacy)).maxPlayers)
    }
    func testPackageIdentityChangesWithContents() {
        XCTAssertNotEqual(ManagedServer.Manifest(version:"1",files:["a":"x"]).identity,ManagedServer.Manifest(version:"1",files:["a":"y"]).identity)
        XCTAssertEqual(ManagedServer.Manifest(version:"1",files:["a":"x","b":"y"]).identity,ManagedServer.Manifest(version:"1",files:["b":"y","a":"x"]).identity)
    }
}
