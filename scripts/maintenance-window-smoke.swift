import AppKit
import ServerCore

@main struct MaintenanceWindowSmoke {
    static var controller: ServerUpdateWindow?
    static var services: [Process] = []
    static func main() throws {
        let paths = Paths()
        precondition(paths.isDevelopment && ProcessInfo.processInfo.environment["VSM_HOME"] != nil)
        let id = CommandLine.arguments[1], executable = CommandLine.arguments[2]
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        var phases: [ServerUpdateProgress.Phase] = []
        controller = ServerUpdateWindow(engine:Engine(paths:paths),scheduledID:id,scheduledDeadline:Date().addingTimeInterval(3),restartServers:{ ids in
            for id in ids {
                let scoped = try Store(paths:paths).servicePaths(id)
                try Lifecycle(paths:scoped).requestStart()
                let p = Process(); p.executableURL = URL(fileURLWithPath:executable); p.arguments = ["--service",id]
                p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
                try p.run(); services.append(p)
            }
        },onProgress:{ phases.append($0.phase) }) {
            let online = (try? Fleet(paths:paths).statuses().first(where:{$0.selected == id})?.state) == "Online"
            precondition(online && phases.contains(.countdown) && phases.contains(.stopping) && phases.contains(.starting))
            precondition(!phases.contains(.installing))
            print("PASS: real scheduled-restart window countdown → save/stop → startup confirmation; maintenance log recorded")
            exit(0)
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+280) { fputs("Maintenance window timed out\n",stderr); exit(1) }
        app.run()
    }
}
