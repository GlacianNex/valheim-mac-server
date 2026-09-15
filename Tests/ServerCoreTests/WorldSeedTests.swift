import XCTest
@testable import ServerCore

final class WorldSeedTests: XCTestCase {
    func fixture(_ body: (Store, Paths) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = Paths(root: root)
        try body(Store(paths: paths), paths)
    }
    func profile(seed: String? = "Meadows42") -> Profile {
        var p = Profile(); p.label = "Seed test"; p.name = p.label; p.world = "SeedFixture"; p.isPublic = false; p.seed = seed
        return p
    }
    func testHashMatchesServerGeneratedFixture() {
        // Seed/hash read from a disposable native build 25253791 world, not computed by this writer.
        XCTAssertEqual(WorldSeed.hash("ktDr7Tlbn5"), -1966100769)
        XCTAssertNotEqual(WorldSeed.hash("Meadows42"), WorldSeed.hash("meadows42"))
    }
    func testSeedValidationAndBlankRandom() throws {
        for seed in ["", "a", "1234567890", "Meadows42"] { XCTAssertNoThrow(try profile(seed: seed).validate()) }
        for seed in ["elevenchars", "my seed", "a\n", "é", "🗺", "../x", "a\0b"] { XCTAssertThrowsError(try profile(seed: seed).validate()) }
        try fixture { store, _ in
            let p = profile(seed: nil); try store.save(p)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.saveDirectory(p).appendingPathComponent("worlds_local").path))
        }
    }
    func testCreatesMetadataAndLocksSeedWithoutRewritingWorld() throws {
        try fixture { store, paths in
            var p = profile(); try store.save(p)
            let fwl = store.saveDirectory(p).appendingPathComponent("worlds_local/SeedFixture.fwl")
            let before = try Data(contentsOf: fwl)
            XCTAssertEqual(try SavedWorldSettings.read(profile: p, paths: paths).seed, "Meadows42")
            let formData = Data(try Engine(paths: paths).execute("get-profile", arguments: [p.id]).utf8)
            let form = try XCTUnwrap(JSONSerialization.jsonObject(with: formData) as? [String: Any])
            XCTAssertEqual(form["_savedSeed"] as? String, "Meadows42")
            try store.save(Profile(form: form))
            XCTAssertEqual(try Data(contentsOf: fwl), before)
            p.seed = "Different"
            XCTAssertThrowsError(try store.save(p))
            p.seed = nil
            XCTAssertThrowsError(try store.save(p))
            XCTAssertEqual(try Data(contentsOf: fwl), before)
            XCTAssertThrowsError(try WorldSeed.create(world: p.world, seed: "Other", saveDirectory: store.saveDirectory(p)))
            XCTAssertEqual(try Data(contentsOf: fwl), before)
        }
    }
    func testImportRejectsSeedOverrideAndPreservesSource() throws {
        try fixture { store, paths in
            let source = paths.file("source"); try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try WorldSeed.create(world: "SeedFixture", seed: "Original", saveDirectory: source)
            let db = source.appendingPathComponent("worlds_local/SeedFixture.db")
            try Data([1,2,3]).write(to: db)
            let fwl = db.deletingPathExtension().appendingPathExtension("fwl"), before = try Data(contentsOf: fwl)
            var p = profile()
            XCTAssertThrowsError(try store.save(p, importSource: db))
            XCTAssertTrue(try store.load().profiles.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.saveDirectory(p).path))
            p.seed = nil; try store.save(p, importSource: db)
            XCTAssertEqual(try SavedWorldSettings.read(profile: p, paths: paths).seed, "Original")
            XCTAssertEqual(try Data(contentsOf: fwl), before)
        }
    }
    func testOldProfilesDecodeAndCannotBeReseeded() throws {
        try fixture { store, _ in
            let p = profile(seed: nil)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
            json.removeValue(forKey: "seed")
            var old = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertNil(old.seed)
            try store.save(old)
            old.seed = "New"
            XCTAssertThrowsError(try store.save(old))
        }
    }
    func testLongUnicodeWorldNameUsesDotNetStringEncoding() throws {
        try fixture { store, paths in
            var p = profile(); p.world = String(repeating: "界", count: 50)
            try store.save(p)
            XCTAssertEqual(try SavedWorldSettings.read(profile: p, paths: paths).seed, "Meadows42")
        }
    }
}
