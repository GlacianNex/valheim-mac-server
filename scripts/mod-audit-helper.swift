import Foundation

// Isolated audit utility. No launchd jobs and no default production paths.
@main struct ModAuditHelper {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 5 else { throw MonitorError("Usage: helper install|inventory catalog root profile [package]") }
        let paths = Paths(root:URL(fileURLWithPath:args[3]),profileID:args[4])
        let library = try ModLibrary(paths:paths,profileID:args[4])
        if args[1] == "install" {
            let catalog = try JSONDecoder().decode([ModPackage].self,from:Data(contentsOf:URL(fileURLWithPath:args[2])))
            guard args.count > 5, let mod = catalog.first(where:{$0.full_name == args[5]}), let version = mod.latest else { throw MonitorError("Package not found") }
            let resolved = try ModCatalog.resolve(package:mod.full_name,version:version.version_number,in:catalog)
            let records = try await library.download(resolved,source:.thunderstore)
            guard let record = records.last else { throw MonitorError("No mod selected") }
            try library.select(record.id,enabled:true)
            print(String(decoding:try JSONEncoder().encode(records),as:UTF8.self))
        } else {
            let store = try Store(paths:paths), db = try store.load()
            let scoped = store.servicePaths(args[4],database:db)
            let runtime = ManagedServer(paths:scoped).runtime
            let status = try Lifecycle(paths:scoped).status()
            let live = ModRuntimeStatus.read(paths:scoped,runtime:runtime)
            let inventory = try library.inventory(runtime:runtime,running:status.running,live:live)
            let rows = inventory.map { ["name":$0.name,"version":$0.version,"status":$0.status,"detail":$0.detail] }
            let value: [String:Any] = ["state":status.state,"running":status.running,"freshLog":live != nil,"mods":rows]
            print(String(decoding:try JSONSerialization.data(withJSONObject:value),as:UTF8.self))
        }
    }
}
