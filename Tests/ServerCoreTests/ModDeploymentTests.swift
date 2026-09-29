import XCTest
@testable import ServerCore

final class ModDeploymentTests: XCTestCase {
    func setup() throws -> (URL,ModLibrary) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        return (root,try ModLibrary(paths:Paths(root:root),profileID:UUID().uuidString))
    }
    func add(_ library:ModLibrary,_ root:URL,name:String="Test",files:[String:String],deps:[String]=[]) throws -> StoredMod {
        let source = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
        for (path,text) in files { let f = source.appendingPathComponent(path); try FileManager.default.createDirectory(at:f.deletingLastPathComponent(),withIntermediateDirectories:true); try Data(text.utf8).write(to:f) }
        try JSONSerialization.data(withJSONObject:["name":name,"version_number":"1.0.0","dependencies":deps]).write(to:source.appendingPathComponent("manifest.json"))
        let record = try library.prepareImport(source).record
        try library.add([record]); return record
    }
    func testPlayerInstallFlagPropagatesThroughInstalledDependencies() throws {
        let (root,lib) = try setup()
        let required = try add(lib,root,name:"ClientDependency",files:["ClientDependency.dll":"dll","README.md":"All players must install this mod."])
        XCTAssertEqual(required.requirement,.playersRequired)
        _ = try add(lib,root,name:"Parent",files:["Parent.dll":"dll"],deps:["ClientDependency-1.0.0"])
        let inventory = try lib.inventory(runtime:root.appendingPathComponent("runtime"),running:false)
        XCTAssertTrue(inventory.first(where:{$0.name == "Parent"})?.playersRequired == true)
        XCTAssertTrue(inventory.first(where:{$0.name == "Parent"})?.detail.contains("Players must install") == true)
    }
    func testOldUnknownRequirementsRefreshFromStoredReadme() throws {
        let (root,lib) = try setup()
        let record = try add(lib,root,name:"Legacy",files:["Legacy.dll":"dll","README.md":"All players must install this mod."])
        let file = lib.directory.appendingPathComponent("manifest.json")
        var manifest = try JSONDecoder().decode(ModManifest.self,from:Data(contentsOf:file))
        manifest.mods[0].requirement = .unknown
        try JSONEncoder().encode(manifest).write(to:file)
        XCTAssertEqual(try lib.load().mods.first?.requirement,.playersRequired)
        XCTAssertEqual(try lib.load().mods.first?.id,record.id)
        // Read-only inference must not silently rewrite an existing user's manifest.
        XCTAssertEqual(try JSONDecoder().decode(ModManifest.self,from:Data(contentsOf:file)).mods[0].requirement,.unknown)
    }
    func testDependencySelectionAndRemovalGuards() throws {
        let (root,lib) = try setup()
        let b = try add(lib,root,name:"B",files:["B.dll":"b"])
        let a = try add(lib,root,name:"A",files:["A.dll":"a"],deps:["B-1.0.0"])
        try lib.select(a.id,enabled:true)
        XCTAssertEqual(try lib.load().mods.filter(\.selected).count,2)
        XCTAssertThrowsError(try lib.select(b.id,enabled:false))
        XCTAssertThrowsError(try lib.remove(b.id))
        try lib.select(a.id,enabled:false); try lib.select(b.id,enabled:false)
    }
    func testRoutingRemovalAndConfigPreservation() throws {
        let (root,lib) = try setup()
        let mod = try add(lib,root,files:["BepInEx/plugins/Test/Test.dll":"dll","BepInEx/config/test.cfg":"default","BepInEx/patchers/Patcher.dll":"patch"])
        try lib.select(mod.id,enabled:true)
        let stage = root.appendingPathComponent("stage")
        try lib.deploy(into:stage,previous:root.appendingPathComponent("absent"))
        let receipt = try JSONDecoder().decode(ModDeploymentReceipt.self,from:Data(contentsOf:stage.appendingPathComponent("BepInEx/vsm-mod-receipt.json")))
        XCTAssertEqual(receipt.files.count,3)
        XCTAssertTrue(receipt.files.contains(where:{$0.path.hasPrefix("BepInEx/patchers/")}))
        try Data("custom".utf8).write(to:stage.appendingPathComponent("BepInEx/config/test.cfg"))
        let next = root.appendingPathComponent("next")
        try FileManager.default.copyItem(at:stage,to:next)
        try lib.select(mod.id,enabled:false)
        try lib.deploy(into:next,previous:stage)
        XCTAssertEqual(try String(contentsOf:next.appendingPathComponent("BepInEx/config/test.cfg")),"custom")
        XCTAssertFalse(FileManager.default.fileExists(atPath:next.appendingPathComponent(receipt.files.first(where:{$0.path.hasSuffix("Test.dll")})!.path).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:stage.appendingPathComponent(receipt.files.first(where:{$0.path.hasSuffix("Test.dll")})!.path).path))
    }
    func testLoaderReplacementAndUnknownPlatformsRejected() throws {
        let (root,lib) = try setup()
        let mod = try add(lib,root,files:["BepInEx/core/BepInEx.dll":"bad"])
        XCTAssertThrowsError(try lib.select(mod.id,enabled:true))
        XCTAssertFalse(ModCompatibility.verified(package:"ebkr-r2modman",version:"3.2.19"))
        XCTAssertFalse(ModCompatibility.verified(package:"MidnightMods-NetworkPerformanceSystem",version:"1.9.0"))
        XCTAssertTrue(ModCompatibility.verified(package:"MidnightMods-NetworkPerformanceSystem",version:"1.6.0"))
        XCTAssertTrue(ModCompatibility.supplies("denikson-BepInExPack_Valheim-5.4.2202"))
        XCTAssertFalse(ModCompatibility.supplies("denikson-BepInExPack_Valheim-9.0.0"))
        XCTAssertTrue(ModCompatibility.supplies("BepInEx-BepInExPack-5.4.2100"))
        XCTAssertFalse(ModCompatibility.supplies("BepInEx-BepInExPack-6.0.0"))
        XCTAssertFalse(ModCompatibility.supplies("bbepis-BepInExPack-5.4.2100"))
    }
    func testLiveStatusUsesFreshCurrentSessionLogs() throws {
        let now = Date(timeIntervalSince1970:1000)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        let payload:[String:Any] = ["pid":42,"updated":formatter.string(from:now),"mods":[["guid":"test","name":"Test","version":"1","path":"/test.dll","status":"Failed","error":"Missing dependency"]]]
        let json = String(decoding:try JSONSerialization.data(withJSONObject:payload),as:UTF8.self)
        let log = "Unity prefix VSM mod status: " + json + "\nVSM mod status: {incomplete"
        XCTAssertEqual(ModRuntimeStatus.parseLog(log,pid:42,now:now)?.mods.first?.status,"Failed")
        XCTAssertNil(ModRuntimeStatus.parseLog(log,pid:43,now:now))
        XCTAssertNil(ModRuntimeStatus.parseLog(log,pid:42,now:now.addingTimeInterval(30)))
    }
    func testStartupExceptionsOverrideLoadedSnapshotOnlyForMatchingPlugin() throws {
        let now = Date(timeIntervalSince1970:1000)
        let payload:[String:Any] = ["pid":42,"updated":"1970-01-01T00:16:40.000Z","mods":[["guid":"example.mod","name":"Example","version":"1","path":"/plugins/Example.dll","status":"Loaded","error":""],["guid":"other.mod","name":"Other","version":"1","path":"/plugins/Other.dll","status":"Loaded","error":""]]]
        let json = String(decoding:try JSONSerialization.data(withJSONObject:payload),as:UTF8.self)
        let log = "MissingMethodException: Method not found\n  at Example.Plugin.Awake ()\n\nVSM mod status: " + json
        let status = ModRuntimeStatus.parseLog(log,pid:42,now:now)
        XCTAssertEqual(status?.mods[0].status,"Failed")
        XCTAssertTrue(status?.mods[0].error.contains("MissingMethodException") == true)
        XCTAssertEqual(status?.mods[1].status,"Loaded")
        XCTAssertNil(ModRuntimeStatus.parseLog(log,pid:43,now:now))
    }
    func testRecordedNativeStartupFailures() throws {
        guard let reportPath = ProcessInfo.processInfo.environment["VSM_RECORDED_AUDIT"] else { throw XCTSkip("Opt-in saved native log regression") }
        let report = try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:reportPath))) as! [String:Any]
        let results = report["results"] as! [[String:Any]]
        for (package,modName,expected) in [("OdinPlus-TeleportEverything","TeleportEverything","Failed"),("Smoothbrain-Mining","Mining","Loaded"),("Therzie-Warfare","Warfare","Loaded")] {
            let row = try XCTUnwrap(results.first { $0["package"] as? String == package })
            let log = try String(contentsOf:URL(fileURLWithPath:row["log"] as! String),encoding:.utf8)
            let last = try XCTUnwrap(log.components(separatedBy:"\n").last { $0.contains("VSM mod status:") })
            let marker = try XCTUnwrap(last.range(of:"VSM mod status: "))
            let snapshot = try JSONSerialization.jsonObject(with:Data(last[marker.upperBound...].utf8)) as! [String:Any]
            let date = ISO8601DateFormatter();date.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
            let parsed = ModRuntimeStatus.parseLog(log,pid:Int32(snapshot["pid"] as! Int),now:try XCTUnwrap(date.date(from:snapshot["updated"] as! String)))
            XCTAssertEqual(parsed?.mods.first { $0.name == modName }?.status,expected,package)
            if package == "Smoothbrain-Mining" { XCTAssertTrue(parsed?.unattributedErrors?.contains(where:{$0.contains("MissingMethodException")}) == true) }
        }
    }
    func testPatcherNeedsPreloaderEvidenceAndReportsFailure() throws {
        let payload:[String:Any] = ["pid":42,"updated":"1970-01-01T00:16:40.000Z","mods":[["guid":"ExamplePatcher","name":"ExamplePatcher","version":"1.0.0.0","path":"/patchers/Example.dll","status":"Awaiting preloader evidence","error":"","kind":"patcher","patcherTypes":["Example.Patcher"]]]]
        let json = "VSM mod status: " + String(decoding:try JSONSerialization.data(withJSONObject:payload),as:UTF8.self)
        let now = Date(timeIntervalSince1970:1000)
        XCTAssertEqual(ModRuntimeStatus.parseLog(json,pid:42,now:now)?.mods[0].status,"Awaiting preloader evidence")
        let start = "[Info   :   BepInEx] Loaded 1 patcher method from [ExamplePatcher 1.0.0.0]\n[Message:   BepInEx] Preloader finished\n"
        XCTAssertEqual(ModRuntimeStatus.parseLog(start+json,pid:42,now:now)?.mods[0].status,"Loaded")
        XCTAssertEqual(ModRuntimeStatus.parseLog(start+"[Error  :   BepInEx] Failed to run Initializer of Example.Patcher: broken\n\n"+json,pid:42,now:now)?.mods[0].status,"Failed")
    }
    func testCacheChangesAreRejectedBeforeEnabling() throws {
        let (root,lib) = try setup()
        let mod = try add(lib,root,files:["Test.dll":"original"])
        let files = try ModLibrary.files(in:lib.folder(for:mod))
        try Data("changed".utf8).write(to:files.first(where:{$0.pathExtension == "dll"})!)
        XCTAssertThrowsError(try lib.select(mod.id,enabled:true))
        XCTAssertFalse(try lib.load().mods[0].selected)
    }
    func testPendingSelectionSurvivesWithoutRestartAndClearsAfterDeployment() throws {
        let (root,lib) = try setup()
        let mod = try add(lib,root,files:["Test.dll":"dll"])
        try lib.select(mod.id,enabled:true)
        let runtime = root.appendingPathComponent("runtime")
        try lib.deploy(into:runtime,previous:root.appendingPathComponent("absent"))
        try lib.select(mod.id,enabled:false)
        XCTAssertEqual(try lib.inventory(runtime:runtime,running:true).first?.status,"Disables on restart")
        XCTAssertEqual(try lib.inventory(runtime:runtime,running:true).first?.status,"Disables on restart")
        XCTAssertEqual(try lib.inventory(runtime:runtime,running:false).first?.status,"Disabled")
        let next = root.appendingPathComponent("next")
        try lib.deploy(into:next,previous:runtime)
        XCTAssertEqual(try lib.inventory(runtime:next,running:true).first?.status,"Disabled")
        try lib.select(mod.id,enabled:true)
        XCTAssertEqual(try lib.inventory(runtime:next,running:true).first?.status,"Enables on restart")
    }
    func testRuntimeDependencyFailurePropagatesWithoutChangingSelection() throws {
        let (root,lib) = try setup()
        let dependency = try add(lib,root,name:"Dependency",files:["Dependency.dll":"dll"])
        let parent = try add(lib,root,name:"Parent",files:["Parent.dll":"dll"],deps:["Dependency-1.0.0"])
        let child = try add(lib,root,name:"Child",files:["Child.dll":"dll"],deps:["Parent-1.0.0"])
        try lib.select(child.id,enabled:true)
        let runtime = root.appendingPathComponent("runtime")
        try lib.deploy(into:runtime,previous:root.appendingPathComponent("absent"))
        let receipt = try JSONDecoder().decode(ModDeploymentReceipt.self,from:Data(contentsOf:runtime.appendingPathComponent("BepInEx/vsm-mod-receipt.json")))
        let mods = [dependency,parent,child].map { mod -> [String:Any] in
            ["guid":mod.name,"name":mod.name,"version":"1.0.0","path":runtime.appendingPathComponent(receipt.files.first { $0.owner == mod.id && $0.path.hasSuffix(".dll") }!.path).path,
             "status":mod.id == dependency.id ? "Failed":"Loaded","error":mod.id == dependency.id ? "Version mismatch":""]
        }
        let live = try JSONDecoder().decode(ModRuntimeStatus.self,from:JSONSerialization.data(withJSONObject:["pid":42,"updated":"now","mods":mods]))
        let entries = try lib.inventory(runtime:runtime,running:true,live:live)
        XCTAssertTrue(entries.allSatisfy { $0.status == "Failed" })
        XCTAssertTrue(entries.first { $0.name == "Child" }!.detail.contains("Required dependency failed: Parent"))
        XCTAssertTrue(try lib.inventory(runtime:runtime,running:false,live:live).allSatisfy { $0.status == "Enabled" })
        XCTAssertTrue(try lib.load().mods.allSatisfy(\.selected))
    }
    func testCatalogDeploymentKeepsDiscoverablePackageFolderAndMigratesOldReceipt() throws {
        let (root,lib) = try setup()
        var mod = try add(lib,root,files:["plugins/Test.dll":"dll","plugins/Assets/sails/cloth.png":"asset"])
        mod.package = "Author-Test"; mod.selected = true
        let old = root.appendingPathComponent("old"), stage = root.appendingPathComponent("new")
        let oldPath = "BepInEx/plugins/VSM-" + String(mod.digest.prefix(16)) + "/Test.dll"
        let file = old.appendingPathComponent(oldPath)
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("dll".utf8).write(to:file)
        let receipt = ModDeploymentReceipt(mods:[mod],files:[ModFileReceipt(path:oldPath,digest:try ModLibrary.fileDigest(file),owner:mod.id)])
        try JSONEncoder().encode(receipt).write(to:old.appendingPathComponent("BepInEx/vsm-mod-receipt.json"))
        try FileManager.default.copyItem(at:old,to:stage)
        try lib.deploy(into:stage,previous:old,selection:[mod])
        XCTAssertFalse(FileManager.default.fileExists(atPath:stage.appendingPathComponent(oldPath).path))
        XCTAssertEqual(try String(contentsOf:stage.appendingPathComponent("BepInEx/plugins/Author-Test/Assets/sails/cloth.png")),"asset")
        XCTAssertTrue(FileManager.default.fileExists(atPath:file.path))
        mod.package = "../escape"
        let safe = root.appendingPathComponent("safe")
        try lib.deploy(into:safe,previous:root.appendingPathComponent("absent"),selection:[mod])
        XCTAssertTrue(FileManager.default.fileExists(atPath:safe.appendingPathComponent(oldPath).path))
    }
    func testMixedMarkupHeadingAndSpacing() throws {
        let value = ModReadme.displayText("# **Features**\n\n\n**Manual Installation\n**\n\n\n> Use [guide](https://example.com).")
        let rendered = try AttributedString(markdown:value,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))
        let text = String(rendered.characters)
        XCTAssertFalse(text.contains("**"))
        XCTAssertFalse(text.contains("\n\n\n"))
        XCTAssertFalse(text.contains("> Use"))
        XCTAssertTrue(text.contains("Manual Installation"))
        XCTAssertTrue(rendered.runs.contains { $0.link != nil })
    }
    func testReadmeFormatting() {
        let rendered = ModReadme.displayText("<p align=\"center\">Hello</p>\n# Features\n| Name | Value |\n| :--- | ---: |\n| Slots | 10 |\n<script>bad()</script>")
        XCTAssertFalse(rendered.contains("<p")); XCTAssertFalse(rendered.contains(":---")); XCTAssertFalse(rendered.contains("bad()"))
        XCTAssertTrue(rendered.contains("**Name:** Slots")); XCTAssertTrue(rendered.contains("**Value:** 10")); XCTAssertTrue(rendered.contains("Hello"))
    }
    func testUnmanagedInventoryDoesNotClaimLoaded() throws {
        let (root,lib) = try setup()
        let plugins = root.appendingPathComponent("runtime/BepInEx/plugins/Manual")
        try FileManager.default.createDirectory(at:plugins,withIntermediateDirectories:true)
        try Data("dll".utf8).write(to:plugins.appendingPathComponent("Manual.dll"))
        let entries = try lib.inventory(runtime:root.appendingPathComponent("runtime"),running:true)
        XCTAssertEqual(entries.count,1); XCTAssertEqual(entries[0].status,"Unmanaged")
    }
}
