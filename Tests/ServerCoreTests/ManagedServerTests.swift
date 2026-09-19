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
        let names = ["BepInEx/core/BepInEx.dll", "BepInEx/core/BepInEx.Preloader.dll", "BepInEx/plugins/ManagerRcon/ManagerRcon.dll", "libdoorstop.dylib"]
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
    func testPackageIdentityChangesWithContents() {
        XCTAssertNotEqual(ManagedServer.Manifest(version:"1",files:["a":"x"]).identity,ManagedServer.Manifest(version:"1",files:["a":"y"]).identity)
        XCTAssertEqual(ManagedServer.Manifest(version:"1",files:["a":"x","b":"y"]).identity,ManagedServer.Manifest(version:"1",files:["b":"y","a":"x"]).identity)
    }
}
