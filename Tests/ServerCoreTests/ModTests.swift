import XCTest
@testable import ServerCore

final class ModTests: XCTestCase {
    func package(_ name: String, version: String = "1.0.0", dependencies: [String] = [], categories: [String] = []) throws -> ModPackage {
        let value: [String: Any] = ["name": name, "full_name": "Author-" + name, "owner": "Author", "package_url": "https://example.com/mod", "rating_score": 4, "is_deprecated": false, "categories": categories,
            "versions": [["version_number": version, "description": "Build larger houses", "download_url": "https://example.com/mod.zip", "dependencies": dependencies, "downloads": 12, "date_created": "2026-09-17", "is_active": true]]]
        return try JSONDecoder().decode(ModPackage.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    func mod(at root: URL, version: String = "1.0.0") throws -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("fake fixture plugin".utf8).write(to: folder.appendingPathComponent("Plugin.dll"))
        try JSONSerialization.data(withJSONObject: ["name": "BuildMod", "version_number": version, "description": "Build houses", "dependencies": []]).write(to: folder.appendingPathComponent("manifest.json"))
        return folder
    }
    func testReadmeDoesNotRequireInstallablePackage() throws {
        let root = try temporary(), folder = root.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "# Documentation\n## Installation\nUse the mod manager.".write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let zip = root.appendingPathComponent("docs.zip")
        try checkCommand("/usr/bin/ditto", ["-c", "-k", folder.path, zip.path])
        let text = try ModCatalog.archiveReadme(zip)
        XCTAssertTrue(text.contains("Use the mod manager"))
        XCTAssertTrue(ModInstallInstructions(markdown: text).found)
    }
    func testNewerInstalledDependencyIsReusedAndProtected() throws {
        let root = try temporary(), library = try ModLibrary(paths: Paths(root: root), profileID: UUID().uuidString)
        var dependency = try library.prepareImport(mod(at: root, version: "1.5.0")).record
        dependency.package = "Author-B"; dependency.name = "B"
        var parent = try library.prepareImport(mod(at: root)).record
        parent.package = "Author-A"; parent.dependencies = ["Author-B-1.0.0"]
        try library.add([dependency, parent])
        let a = try package("A", dependencies: parent.dependencies)
        XCTAssertEqual(try ModCatalog.resolve(package: a.full_name, version: "1.0.0", in: [a], installed: library.load().mods).map { $0.package.name }, ["A"])
        try library.select(parent.id, enabled: true)
        XCTAssertTrue(try library.load().mods.allSatisfy(\.selected))
        XCTAssertThrowsError(try library.select(dependency.id, enabled: false))
        XCTAssertFalse(ModCompatibility.satisfies(package: "Author-B", version: "0.9.0", pin: "Author-B-1.0.0"))
        XCTAssertFalse(ModCompatibility.satisfies(package: "Author-B", version: "2.0.0-beta.1", pin: "Author-B-1.0.0"))
    }
    func testLiveReadmes() async throws {
        guard ProcessInfo.processInfo.environment["VSM_LIVE_READMES"] == "1" else { throw XCTSkip("Opt-in network verification") }
        let catalog = try await ModCatalog.fetch(.hexium)
        for package in catalog.sorted(by: { $0.totalDownloads > $1.totalDownloads }).prefix(6) {
            let text = try await ModCatalog.readme(package: package, version: package.latest!, source: .hexium)
            let thunderstoreText = try await ModCatalog.readme(package: package, version: package.latest!, source: .thunderstore)
            XCTAssertGreaterThan(thunderstoreText.count, 100)
            XCTAssertGreaterThan(text.count, 100)
            print("README verified: \(package.name), \(text.count) chars, installation section: \(ModInstallInstructions(markdown: text).found)")
        }
    }
    func testBundledBepInExPackMapping() throws {
        for pin in ["5.4.2202", "5.4.2333", "5.4.2350", "5.4.2351"] {
            let plant = try package("PlantEverything", dependencies: ["denikson-BepInExPack_Valheim-" + pin])
            XCTAssertEqual(try ModCatalog.resolve(package: plant.full_name, version: "1.0.0", in: [plant]).count, 1)
        }
        let future = try package("Future", dependencies: ["denikson-BepInExPack_Valheim-5.4.9999"])
        XCTAssertThrowsError(try ModCatalog.resolve(package: future.full_name, version: "1.0.0", in: [future])) { error in
            XCTAssertTrue(error.localizedDescription.contains("Update the manager"))
        }
    }
    func testLivePlantEverythingInstall() async throws {
        guard ProcessInfo.processInfo.environment["VSM_LIVE_PLANT"] == "1" else { throw XCTSkip("Opt-in isolated real package test") }
        let (data, _) = try await URLSession.shared.data(from: URL(string: "https://thunderstore.io/api/experimental/package/Advize/PlantEverything/")!)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["versions"] = [try XCTUnwrap(object["latest"])]
        object["categories"] = [String]()
        let plant = try JSONDecoder().decode(ModPackage.self, from: JSONSerialization.data(withJSONObject: object))
        let resolved = try ModCatalog.resolve(package: plant.full_name, version: plant.latest!.version_number, in: [plant])
        XCTAssertEqual(resolved.map { $0.package.full_name }, ["Advize-PlantEverything"])
        let library = try ModLibrary(paths: Paths(root: temporary()), profileID: UUID().uuidString)
        let downloaded = try await library.download(resolved, source: .thunderstore)
        try library.select(try XCTUnwrap(downloaded.first).id, enabled: true)
        let installed = try library.load().mods
        XCTAssertEqual(installed.count, 1)
        XCTAssertTrue(installed[0].selected)
        XCTAssertEqual(installed[0].package, "Advize-PlantEverything")
        print("PASS: PlantEverything \(plant.latest!.version_number) installed and enabled in isolated storage; bundled BepInEx reused, no duplicate framework downloaded")
    }
    func testLiveCatalogDependencyAuditAndInstalls() async throws {
        guard let file = ProcessInfo.processInfo.environment["VSM_CATALOG_AUDIT"] else { throw XCTSkip("Opt-in catalog and isolated install audit") }
        let catalog = try JSONDecoder().decode([ModPackage].self, from: Data(contentsOf: URL(fileURLWithPath: file)))
        let limit = Int(ProcessInfo.processInfo.environment["VSM_AUDIT_LIMIT"] ?? "100") ?? 100
        let selectedPackages = Set((ProcessInfo.processInfo.environment["VSM_AUDIT_PACKAGES"] ?? "").split(separator:",").map(String.init))
        let mods = catalog.filter { (selectedPackages.isEmpty || selectedPackages.contains($0.full_name)) && !$0.is_deprecated && $0.latest != nil && ModCompatibility.catalogEligible($0) && ModCompatibility.bundled[$0.full_name] == nil && !$0.categories.contains(where: { $0.lowercased().contains("modpack") }) }.sorted { $0.totalDownloads > $1.totalDownloads }.prefix(limit)
        var results: [[String: Any]] = []
        let report = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VSM_AUDIT_REPORT"] ?? "/tmp/vsm-top100-report.json")
        for mod in mods {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("vsm-install-audit-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let version = try XCTUnwrap(mod.latest)
            var row: [String: Any] = ["package": mod.full_name, "version": version.version_number, "downloads": mod.totalDownloads]
            var phase = "resolve"
            do {
                let resolved = try ModCatalog.resolve(package: mod.full_name, version: version.version_number, in: catalog)
                XCTAssertFalse(resolved.contains { ["denikson-BepInExPack_Valheim", "ValheimModding-Jotunn"].contains($0.package.full_name) }, mod.full_name)
                row["packages"] = resolved.map { $0.package.full_name + "-" + $0.version.version_number }
                let library = try ModLibrary(paths: Paths(root: root), profileID: UUID().uuidString)
                phase = "download/import"
                let records = try await library.download(resolved, source: .thunderstore)
                phase = "enable/deploy"
                try library.select(try XCTUnwrap(records.last).id, enabled: true)
                XCTAssertTrue(try library.load().mods.allSatisfy(\.selected), mod.full_name)
                row["result"] = "pass"
            } catch { row["result"] = "failed"; row["phase"] = phase; row["error"] = error.localizedDescription }
            results.append(row)
            try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: report, options: .atomic)
        }
        XCTAssertEqual(results.count, limit, "Catalog must contain the requested number of eligible mods for this audit")
        XCTAssertTrue(results.allSatisfy { ($0["result"] as? String) == "pass" }, "Installation failures are recorded in \(report.path)")
        print("AUDIT complete: \(results.count) packages; \(results.filter { ($0["result"] as? String) == "pass" }.count) passed; report \(report.path)")
    }

    func testWindowsZipPathsAndDOSAttributesWithTraversalProtection() throws {
        let root = try temporary(), library = try ModLibrary(paths: Paths(root: root), profileID: UUID().uuidString)
        let windows = root.appendingPathComponent("windows.zip")
        try Data(base64Encoded: "UEsDBBQAAAAAAAAAIQDuQOUFBwAAAAcAAAATAAAAcGx1Z2luc1xFeGFtcGxlLmRsbGZpeHR1cmVQSwECFAAUAAAAAAAAACEA7kDlBQcAAAAHAAAAEwAAAAAAAAAAAAAApAEAAAAAcGx1Z2luc1xFeGFtcGxlLmRsbFBLBQYAAAAAAQABAEEAAAA4AAAAAAA=")!.write(to: windows)
        let traversal = root.appendingPathComponent("traversal.zip")
        try Data(base64Encoded: "UEsDBBQAAAAAAAAAIQDuQOUFBwAAAAcAAAAYAAAAcGx1Z2luc1wuLlwuLlxlc2NhcGUuZGxsZml4dHVyZVBLAQIUABQAAAAAAAAAIQDuQOUFBwAAAAcAAAAYAAAAAAAAAAAAAACkAQAAAABwbHVnaW5zXC4uXC4uXGVzY2FwZS5kbGxQSwUGAAAAAAEAAQBGAAAAPQAAAAAA")!.write(to: traversal)
        let dos = root.appendingPathComponent("dos.zip")
        try Data(base64Encoded: "UEsDBBQAAAAAAAAAIQDuQOUFBwAAAAcAAAALAAAARXhhbXBsZS5kbGxmaXh0dXJlUEsBAhQAFAAAAAAAAAAhAO5A5QUHAAAABwAAAAsAAAAAAAAAAAAAAKQBAAAAAEV4YW1wbGUuZGxsUEsFBgAAAAABAAEAOQAAADAAAAAAAA==")!.write(to: dos)
        let imported = try library.prepareImport(windows)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.folder.appendingPathComponent("plugins/Example.dll").path))
        XCTAssertNoThrow(try library.prepareImport(dos))
        XCTAssertThrowsError(try library.prepareImport(traversal))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.dll").path))
    }
    func testZipDirectoryPlaceholdersAndTypeValidation() throws {
        let root = try temporary(), library = try ModLibrary(paths: Paths(root: root), profileID: UUID().uuidString)
        let folders = root.appendingPathComponent("folders.zip")
        try Data(base64Encoded: "UEsDBBQAAAAAAAAAIQAAAAAAAAAAAAAAAAAPAAAAcGx1Z2luc1xBc3NldHNcUEsDBBQAAAAAAAAAIQBcWq8CBQAAAAUAAAAXAAAAcGx1Z2luc1xBc3NldHNcdGV4dC50eHRhc3NldFBLAwQUAAAAAAAAACEAlCdu6QYAAAAGAAAAEwAAAHBsdWdpbnNcRXhhbXBsZS5kbGxwbHVnaW5QSwECFAAUAAAAAAAAACEAAAAAAAAAAAAAAAAADwAAAAAAAAAAAAAAgAEAAAAAcGx1Z2luc1xBc3NldHNcUEsBAhQAFAAAAAAAAAAhAFxarwIFAAAABQAAABcAAAAAAAAAAAAAAIABLQAAAHBsdWdpbnNcQXNzZXRzXHRleHQudHh0UEsBAhQAFAAAAAAAAAAhAJQnbukGAAAABgAAABMAAAAAAAAAAAAAAIABZwAAAHBsdWdpbnNcRXhhbXBsZS5kbGxQSwUGAAAAAAMAAwDDAAAAngAAAAAA")!.write(to: folders)
        let unixPermissions = root.appendingPathComponent("unixPermissions.zip")
        try Data(base64Encoded: "UEsDBBQAAAAAAAAAIQCUJ27pBgAAAAYAAAALAAAARXhhbXBsZS5kbGxwbHVnaW5QSwECFAMUAAAAAAAAACEAlCdu6QYAAAAGAAAACwAAAAAAAAAAAAAAtAEAAAAARXhhbXBsZS5kbGxQSwUGAAAAAAEAAQA5AAAALwAAAAAA")!.write(to: unixPermissions)
        let symlink = root.appendingPathComponent("symlink.zip")
        try Data(base64Encoded: "UEsDBBQAAAAAAAAAIQAkQOItCwAAAAsAAAALAAAARXhhbXBsZS5kbGwvdG1wL2VzY2FwZVBLAQIUAxQAAAAAAAAAIQAkQOItCwAAAAsAAAALAAAAAAAAAAAAAAD/oQAAAABFeGFtcGxlLmRsbFBLBQYAAAAAAQABADkAAAA0AAAAAAA=")!.write(to: symlink)
        let special = root.appendingPathComponent("special.zip")
        try Data(base64Encoded: "UEsDBBQAAAAAAAAAIQCUJ27pBgAAAAYAAAALAAAARXhhbXBsZS5kbGxwbHVnaW5QSwECFAMUAAAAAAAAACEAlCdu6QYAAAAGAAAACwAAAAAAAAAAAAAApNEAAAAARXhhbXBsZS5kbGxQSwUGAAAAAAEAAQA5AAAALwAAAAAA")!.write(to: special)
        let collision = root.appendingPathComponent("collision.zip")
        try Data(base64Encoded: "UEsDBBQAAAAAAAAAIQDxhmx6AwAAAAMAAAATAAAAcGx1Z2luc1xFeGFtcGxlLmRsbG9uZVBLAwQUAAAAAAAAACEAZorKEQMAAAADAAAAEwAAAHBsdWdpbnMvRXhhbXBsZS5kbGx0d29QSwECFAAUAAAAAAAAACEA8YZsegMAAAADAAAAEwAAAAAAAAAAAAAAgAEAAAAAcGx1Z2luc1xFeGFtcGxlLmRsbFBLAQIUABQAAAAAAAAAIQBmisoRAwAAAAMAAAATAAAAAAAAAAAAAACAATQAAABwbHVnaW5zL0V4YW1wbGUuZGxsUEsFBgAAAAACAAIAggAAAGgAAAAAAA==")!.write(to: collision)
        let imported = try library.prepareImport(folders)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.folder.appendingPathComponent("plugins/Assets/text.txt").path))
        XCTAssertNoThrow(try library.prepareImport(unixPermissions))
        XCTAssertThrowsError(try library.prepareImport(symlink))
        XCTAssertThrowsError(try library.prepareImport(special))
        XCTAssertThrowsError(try library.prepareImport(collision))
    }
    func testWindowsZipExpandedSizeLimit() throws {
        let root = try temporary(), library = try ModLibrary(paths: Paths(root: root), profileID: UUID().uuidString)
        let zip = root.appendingPathComponent("oversized.zip")
        try Data(base64Encoded: "UEsDBBQAAAAAAAAAIQCDFtyMAQAAAAEAAAATAAAAcGx1Z2luc1xFeGFtcGxlLmRsbHhQSwECFAAUAAAAAAAAACEAgxbcjAEAAAABlDV3EwAAAAAAAAAAAAAAgAEAAAAAcGx1Z2luc1xFeGFtcGxlLmRsbFBLBQYAAAAAAQABAEEAAAAyAAAAAAA=")!.write(to: zip)
        XCTAssertThrowsError(try library.prepareImport(zip)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Expanded mod size exceeds"))
        }
    }
    func testInstallInstructionSectionsAndCustomSteps() {
        let readme = "# Example\nAbout the mod.\n## Installation\nInstall using a manager.\n### Server setup\nEdit the config file.\n## Changelog\nUnrelated changes."
        let result = ModInstallInstructions(markdown: readme)
        XCTAssertTrue(result.found); XCTAssertTrue(result.mayNeedExtraSteps)
        XCTAssertTrue(result.text.contains("Edit the config file"))
        XCTAssertFalse(result.text.contains("Unrelated changes"))
        XCTAssertTrue(ModInstallInstructions(markdown: "Copy Plugin.dll into the plugins folder.").found)
        XCTAssertFalse(ModInstallInstructions(markdown: "Adds new trees and weapons.").found)
        XCTAssertTrue(ModInstallInstructions(markdown: "Adds new trees.").notice.contains("does not establish"))
    }
    func testFullReadmePreservedAndDownloadsIncludeAllVersions() throws {
        let root = try temporary(), library = try ModLibrary(paths: Paths(root: root), profileID: UUID().uuidString)
        let folder = try mod(at: root)
        let text = "# Full description\n\nInstallation instructions and configuration."
        try text.write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let imported = try library.prepareImport(folder)
        XCTAssertEqual(try library.readme(for: imported.record), text)
        var item = try package("Example")
        item.versions += try package("Example", version: "2.0.0").versions
        XCTAssertEqual(item.totalDownloads, 24)
    }
    func testCatalogKeepsUnknownCompatibilityAndExcludesExplicitIncompatibility() throws {
        let unknown = try package("Builder")
        XCTAssertTrue(ModCompatibility.catalogEligible(unknown))
        XCTAssertEqual(ModCompatibility.label(package:unknown.full_name,version:"1.0.0"),"Mac compatibility unverified")
        XCTAssertFalse(ModCompatibility.catalogEligible(try package("Client",categories:["Client-only"])))
        XCTAssertFalse(ModCompatibility.catalogEligible(try package("Native",categories:["Windows Only"])))
        var manager = try package("r2modman"); manager.full_name = "ebkr-r2modman"
        XCTAssertFalse(ModCompatibility.catalogEligible(manager))
        XCTAssertEqual(ModCompatibility.label(package:"ValheimModding-Jotunn",version:"2.30.2"),"Mac tested")
        XCTAssertEqual(ModCompatibility.label(package:"ValheimModding-Jotunn",version:"99.0.0"),"Mac compatibility unverified")
    }
    func testSearchIncludesPurposeAndAuthorAndRequiresAllTerms() throws {
        let mod = try package("Builder")
        XCTAssertTrue(mod.matches("houses author"))
        XCTAssertFalse(mod.matches("houses fishing"))
    }
    func testRequirementUnknownIsNotServerOnly() {
        XCTAssertEqual(ModPlayerRequirement.categories([]), .unknown)
        XCTAssertEqual(ModPlayerRequirement.categories(["Server-side"]), .unknown)
        XCTAssertEqual(ModPlayerRequirement.categories(["Client-only"]), .clientOnly)
        XCTAssertEqual(ModPlayerRequirement.categories(["Server-only"]), .serverOnly)
        XCTAssertEqual(ModPlayerRequirement.categories(["Client-and-server"]), .playersRequired)
        XCTAssertEqual(ModPlayerRequirement.categories(["Client & Server"]), .playersRequired)
        XCTAssertEqual(ModPlayerRequirement.categories(["Client (& Server)"]), .unknown)
    }
    func testDependenciesAreOrderedAndDeduplicated() throws {
        let a = try package("A", dependencies: ["Author-B-1.0.0", "Author-C-1.0.0"])
        let b = try package("B", dependencies: ["Author-C-1.0.0"]), c = try package("C")
        let result = try ModCatalog.resolve(package: a.full_name, version: "1.0.0", in: [a,b,c])
        XCTAssertEqual(result.map { $0.package.name }, ["C", "B", "A"])
    }
    func testFreshDependenciesGetStableMaintenanceUpdatesButRootStaysPinned() throws {
        var a = try package("A", dependencies:["Author-B-1.1.0"])
        a.versions += try package("A", version:"1.9.0").versions
        var b = try package("B",version:"1.1.0")
        for version in ["1.14.17", "1.9.0", "2.0.0", "1.15.0-beta.1"] {
            b.versions += try package("B",version:version).versions
        }
        let result = try ModCatalog.resolve(package:a.full_name,version:"1.0.0",in:[a,b])
        XCTAssertEqual(result.map { $0.version.version_number },["1.14.17","1.0.0"])
        let c = try package("C", dependencies:["Author-D-0.2.0"])
        var d = try package("D",version:"0.2.0")
        d.versions += try package("D",version:"0.2.4").versions + package("D",version:"0.3.0").versions
        XCTAssertEqual(try ModCatalog.resolve(package:c.full_name,version:"1.0.0",in:[c,d]).first?.version.version_number,"0.2.4")
    }
    func testDependencyMaintenanceFallbackRestoresGraphAfterCycle() throws {
        let a = try package("A",dependencies:["Author-B-1.0.0"])
        var b = try package("B",dependencies:["Author-C-1.0.0"])
        b.versions += try package("B",version:"1.1.0",dependencies:["Author-D-1.0.0","Author-A-1.0.0"]).versions
        let c = try package("C"), d = try package("D")
        let resolved = try ModCatalog.resolve(package:a.full_name,version:"1.0.0",in:[a,b,c,d])
        XCTAssertEqual(resolved.map { $0.package.name },["C","B","A"])
        XCTAssertEqual(resolved.first { $0.package.name == "B" }?.version.version_number,"1.0.0")
        // The explicitly chosen root version must not be silently downgraded.
        XCTAssertThrowsError(try ModCatalog.resolve(package:b.full_name,version:"1.1.0",in:[a,b,c,d]))
    }
    func testMissingCycleAndClientDependencyAreRejected() throws {
        let a = try package("A", dependencies: ["Author-B-1.0.0"])
        XCTAssertThrowsError(try ModCatalog.resolve(package: a.full_name, version: "1.0.0", in: [a]))
        let b = try package("B", dependencies: ["Author-A-1.0.0"])
        XCTAssertThrowsError(try ModCatalog.resolve(package: a.full_name, version: "1.0.0", in: [a,b]))
        let client = try package("B", categories: ["Client-only"])
        XCTAssertThrowsError(try ModCatalog.resolve(package: a.full_name, version: "1.0.0", in: [a,client]))
    }
    func testDependencyBranchesUseHighestRequiredVersion() throws {
        let a = try package("A", dependencies: ["Author-B-1.0.0", "Author-C-1.0.0"])
        var b = try package("B"); b.versions += try package("B", version: "2.0.0").versions
        let c = try package("C", dependencies: ["Author-B-2.0.0"])
        let result = try ModCatalog.resolve(package: a.full_name, version: "1.0.0", in: [a,b,c])
        XCTAssertEqual(result.first(where: { $0.package.name == "B" })?.version.version_number, "2.0.0")
        XCTAssertEqual(result.filter { $0.package.name == "B" }.count, 1)
    }
    func testPerServerVersionsDoNotAffectEachOtherOrSharedRuntime() throws {
        let root = try temporary(), paths = Paths(root: root)
        let a = try ModLibrary(paths: paths, profileID: UUID().uuidString), b = try ModLibrary(paths: paths, profileID: UUID().uuidString)
        XCTAssertTrue(try a.load().mods.isEmpty)
        let source1 = try mod(at: root), source2 = try mod(at: root, version: "2.0.0")
        let first = try a.prepareImport(source1).record, second = try a.prepareImport(source2).record
        try a.add([first,second]); try b.add([first]); try a.select(second.id, enabled: true); try b.select(first.id, enabled: true)
        XCTAssertEqual(try a.load().mods.filter(\.selected).map(\.version), ["2.0.0"])
        XCTAssertEqual(try b.load().mods.filter(\.selected).map(\.version), ["1.0.0"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source1.appendingPathComponent("Plugin.dll").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.server.path))
    }
    func testDependencyPrereleaseVersionIsNotSplitIntoPackageName() throws {
        let a = try package("A", dependencies: ["Author-B-1.0.0-beta.1"])
        let b = try package("B", version: "1.0.0-beta.1")
        let result = try ModCatalog.resolve(package: a.full_name, version: "1.0.0", in: [a,b])
        XCTAssertEqual(result.first?.version.version_number, "1.0.0-beta.1")
    }
    func testNoProfileTraversalAndSymlinkImport() throws {
        let root = try temporary()
        XCTAssertThrowsError(try ModLibrary(paths: Paths(root: root), profileID: "../other"))
        let library = try ModLibrary(paths: Paths(root: root), profileID: UUID().uuidString)
        let folder = try mod(at: root)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("escape"), withDestinationURL: root)
        XCTAssertThrowsError(try library.prepareImport(folder))
        XCTAssertTrue(try library.load().mods.isEmpty)
    }
    func testImportVersionMismatchPreservesManifest() throws {
        let root = try temporary(), library = try ModLibrary(paths: Paths(root: root), profileID: UUID().uuidString)
        let folder = try mod(at: root)
        let package = try package("BuildMod", version: "2.0.0")
        XCTAssertThrowsError(try library.prepareImport(folder, from: .hexium, package: package, version: package.versions[0]))
        XCTAssertTrue(try library.load().mods.isEmpty)
    }
    func testZIPImportAndUnknownDLLVersion() throws {
        let root = try temporary(), library = try ModLibrary(paths: Paths(root: root), profileID: UUID().uuidString)
        let folder = try mod(at: root), zip = root.appendingPathComponent("mod.zip")
        try checkCommand("/usr/bin/ditto", ["-c", "-k", folder.path, zip.path])
        XCTAssertEqual(try library.prepareImport(zip).record.version, "1.0.0")
        let loose = try library.prepareImport(folder.appendingPathComponent("Plugin.dll")).record
        XCTAssertNil(loose.version); XCTAssertEqual(loose.requirement, .unknown)
    }
}
