import Foundation

public final class Engine {
    public let paths: Paths
    public init(paths: Paths = Paths()) { self.paths = paths }
    public func execute(_ action: String, arguments: [String] = [], input: Data? = nil) throws -> String {
        let store = try Store(paths: paths), lifecycle = Lifecycle(paths: paths)
        switch action {
        case "status": return String(decoding: try encode(lifecycle.status()), as: UTF8.self)
        case "default-profile":
            var form = Profile().form; form["id"] = ""
            return String(decoding: try JSONSerialization.data(withJSONObject: form), as: UTF8.self)
        case "get-profile": return String(decoding: try JSONSerialization.data(withJSONObject: store.selected().form), as: UTF8.self)
        case "save-profile":
            guard let input, let form = try JSONSerialization.jsonObject(with: input) as? [String: Any] else { throw MonitorError("Invalid profile data.") }
            let source = (form["import"] as? String).flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            return try store.save(Profile(form: form), importSource: source)
        case "select-profile":
            guard let id = arguments.first else { throw MonitorError("Choose a profile.") }; try store.select(id)
        case "start": try LoginItems(paths: paths).start()
        case "stop": try lifecycle.requestStop()
        case "autostart-on": try LoginItems(paths: paths).serverAtLogin(true)
        case "autostart-off": try LoginItems(paths: paths).serverAtLogin(false)
        case "monitor-login-on": try LoginItems(paths: paths).monitorAtLogin(true)
        case "monitor-login-off": try LoginItems(paths: paths).monitorAtLogin(false)
        case "install": try Installer(paths: paths).install()
        default: throw MonitorError("Unknown command.")
        }
        return "Done"
    }
}
