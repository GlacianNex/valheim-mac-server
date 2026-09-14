import XCTest
@testable import ServerCore

final class SavedWorldSettingsTests: XCTestCase {
    func metadata(version: Int = 41, keys: [String]) -> Data {
        func integer(_ n: Int) -> [UInt8] { (0..<4).map { UInt8((n >> ($0*8)) & 255) } }
        func string(_ value: String) -> [UInt8] {
            let bytes = Array(value.utf8); var n = bytes.count; var prefix: [UInt8] = []
            repeat { prefix.append(UInt8(n & 127) | (n > 127 ? 128 : 0)); n >>= 7 } while n > 0
            return prefix + bytes
        }
        var payload = integer(version) + string("TestWorld") + string("TestSeed") + Array(repeating: UInt8(0), count: 16)
        if version >= 30 { payload += [1] }
        payload += integer(keys.count)
        for key in keys { payload += string(key) }
        return Data(integer(payload.count) + payload)
    }
    func testLegacyAndModernModifiersAndFlags() throws {
        for version in [32,34,35,41] {
            let data = metadata(version: version, keys: ["resourcerate 200", "preset combat_default:deathpenalty_default:resources_muchmore:raids_default:portals_default", "nomap"])
            let settings = try SavedWorldSettings.decode(data)
            XCTAssertEqual(settings.modifiers["Resources"], "muchmore")
            XCTAssertEqual(settings.modifiers["Combat"], "default")
            XCTAssertEqual(settings.flags["nomap"], true)
            XCTAssertEqual(settings.flags["nobuildcost"], false)
        }
    }
    func testRejectsTruncationAndUnknownVersion() {
        XCTAssertThrowsError(try SavedWorldSettings.decode(metadata(version: 99, keys: [])))
        XCTAssertThrowsError(try SavedWorldSettings.decode(metadata(keys: []).dropLast()))
        XCTAssertThrowsError(try SavedWorldSettings.decode(Data()))
    }
    func testEveryImportedWorldIsReadWithoutPersistingOverrides() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = Paths(root: root), store = try Store(paths: paths)
        for modern in [false,true] {
            var profile = Profile(); profile.label = modern ? "Modern" : "Legacy"; profile.name = profile.label; profile.world = profile.label; profile.password = "test-only-secret"
            profile = try Profile(form: profile.form)
            let source = root.appendingPathComponent("import-" + profile.label)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            let saved = metadata(version: modern ? 41 : 35, keys: ["resourcerate 200"])
            let importSource: URL
            if modern {
                let folder = source.appendingPathComponent(profile.world)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try saved.write(to: folder.appendingPathComponent("_main.1.fwl2"))
                try Data().write(to: folder.appendingPathComponent("_main.1.db2"))
                try Data().write(to: folder.appendingPathComponent("_main.1.ok"))
                // Incomplete newer save must not replace the completed snapshot.
                try metadata(keys: []).write(to: folder.appendingPathComponent("_main.2.fwl2"))
                importSource = folder
            } else {
                try saved.write(to: source.appendingPathComponent(profile.world + ".fwl"))
                importSource = source.appendingPathComponent(profile.world + ".db")
                try Data().write(to: importSource)
            }
            try store.save(profile, importSource: importSource)
            let before = try Data(contentsOf: paths.file("profiles.json"))
            let result = try Engine(paths: paths).execute("get-profile", arguments: [profile.id])
            let form = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String:Any])
            XCTAssertEqual((form["_savedModifiers"] as? [String:String])?["Resources"], "muchmore")
            XCTAssertEqual(form["Resources"] as? String, "")
            try store.save(Profile(form: form))
            XCTAssertEqual(try Data(contentsOf: paths.file("profiles.json")), before)
        }
    }
}
