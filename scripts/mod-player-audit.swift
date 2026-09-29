import Foundation

@main struct PlayerRequirementAudit {
    struct Row: Codable {
        var package:String
        var version:String
        var url:String
        var own:ModPlayerRequirement
        var effective:ModPlayerRequirement
        var evidence:String
        var dependencies:[String]
        var error:String?
    }
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4 else { throw MonitorError("Usage: player-audit catalog plan output-folder") }
        let catalog = try JSONDecoder().decode([ModPackage].self,from:Data(contentsOf:URL(fileURLWithPath:args[1])))
        let plan = try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:args[2]))) as! [[String:Any]]
        let selected = Set(plan.compactMap { $0["package"] as? String })
        let output = URL(fileURLWithPath:args[3]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let report = output.appendingPathComponent("player-requirements.json")
        var rows = (try? JSONDecoder().decode([Row].self,from:Data(contentsOf:report))) ?? []
        if ProcessInfo.processInfo.environment["VSM_REEVALUATE"] == "1" { rows = [] }
        let complete = Set(rows.filter { $0.error == nil }.map(\.package))
        let packages = catalog.filter { selected.contains($0.full_name) && !complete.contains($0.full_name) && $0.latest != nil }
        rows.removeAll { $0.error != nil }
        let encoder = JSONEncoder();encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        for offset in stride(from:0,to:packages.count,by:4) {
            let batch = Array(packages[offset..<min(offset+4,packages.count)])
            let fetched = await withTaskGroup(of:Row.self,returning:[Row].self) { group in
                for package in batch { group.addTask {
                    let version = package.latest!
                    var markdown = "", error:String?
                    do {
                        let cached = output.appendingPathComponent(package.full_name + ".md")
                        if FileManager.default.fileExists(atPath:cached.path) { markdown = try String(contentsOf:cached,encoding:.utf8) }
                        else { markdown = try await ModCatalog.readme(package:package,version:version,source:.thunderstore) }
                        try markdown.write(to:output.appendingPathComponent(package.full_name + ".md"),atomically:true,encoding:.utf8)
                    } catch let failure { error = failure.localizedDescription }
                    let evidence = ModPlayerEvidence.read(declared:package.requirement,description:version.description,readme:markdown)
                    return Row(package:package.full_name,version:version.version_number,url:package.package_url.absoluteString,own:evidence.requirement,effective:evidence.requirement,evidence:evidence.explanation,dependencies:version.dependencies,error:error)
                } }
                var result:[Row] = [];for await row in group { result.append(row) };return result
            }
            rows.append(contentsOf:fetched)
            try encoder.encode(rows).write(to:report,options:.atomic)
            print("Documentation checked: \(rows.count)/\(selected.count)")
        }
        let byName = Dictionary(uniqueKeysWithValues:rows.map { ($0.package,$0) })
        func effective(_ row:Row,visited:Set<String> = []) -> ModPlayerRequirement {
            guard !visited.contains(row.package) else { return .unknown }
            var visited = visited;visited.insert(row.package)
            return ModPlayerEvidence.includingDependencies(row.own,dependencies:row.dependencies.map { pin in
                if ModCompatibility.supplies(pin) { return .serverOnly }
                guard let split = ModCompatibility.split(pin),let dependency = byName[split.name],ModCompatibility.satisfies(package:dependency.package,version:dependency.version,pin:pin) else { return .unknown }
                return effective(dependency,visited:visited)
            })
        }
        for i in rows.indices { rows[i].effective = effective(rows[i]) }
        try encoder.encode(rows.sorted { $0.package < $1.package }).write(to:report,options:.atomic)
    }
}
