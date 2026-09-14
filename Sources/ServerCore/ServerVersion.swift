import Foundation
import Darwin

public enum ServerVersion {
    public static func installed(paths: Paths) -> String? {
        guard let manifest = try? String(contentsOf: paths.server.appendingPathComponent("steamapps/appmanifest_896660.acf")) else { return nil }
        return capture(#""buildid"\s*"([0-9]+)""#, in: manifest)
    }
    public static func latestBuild(in output: String) -> String? {
        // Branch records have no nested objects. Match public specifically, never a beta.
        capture(#""branches"\s*\{(?:\s*"[^\"]+"\s*\{[^{}]*\})*?\s*"public"\s*\{[^{}]*?"buildid"\s*"([0-9]+)""#, in: output)
    }
    private static func capture(_ expression: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: expression),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
    public static func updateAvailable(installed: String, latest: String) -> Bool {
        guard let local = UInt64(installed), let remote = UInt64(latest) else { return false }
        return remote > local
    }
    public static func check(paths: Paths) throws -> String {
        try paths.prepare()
        return try withLock(paths.file("version-check.lock")) {
            let files = FileManager.default
            let checker = paths.file("runtime/version-checker")
            // SteamCMD may update itself. Give checks a private copy so it cannot
            // replace libraries used by the running game server or its installer.
            if !files.fileExists(atPath: checker.path) {
                let source = paths.file("runtime/steamcmd")
                guard files.fileExists(atPath: source.appendingPathComponent("steamcmd").path) else {
                    throw MonitorError("Install the native server before checking for updates.")
                }
                do { try files.copyItem(at: source, to: checker) }
                catch { try? files.removeItem(at: checker); throw error }
            }
            let logURL = paths.logs.appendingPathComponent("version-check.log")
            for _ in 0..<2 {
                files.createFile(atPath: logURL.path, contents: Data(), attributes: [.posixPermissions: 0o600])
                let log = try FileHandle(forWritingTo: logURL)
                let process = Process()
                process.executableURL = checker.appendingPathComponent("steamcmd")
                process.currentDirectoryURL = checker
                var environment = ProcessInfo.processInfo.environment
                environment["DYLD_LIBRARY_PATH"] = checker.path
                environment["DYLD_FRAMEWORK_PATH"] = checker.path
                process.environment = environment
                process.arguments = ["+login", "anonymous", "+app_info_update", "1", "+app_info_print", "896660", "+quit"]
                process.standardInput = FileHandle.nullDevice; process.standardOutput = log; process.standardError = log
                do { try process.run() } catch { try? log.close(); throw error }
                let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: timeout)
                process.waitUntilExit(); timeout.cancel(); try? log.close()
                if process.terminationStatus == 0, let build = latestBuild(in: tail(logURL)) { return build }
            }
            throw MonitorError("Could not check Valve’s latest server build. Your server is unaffected. Try again later or open version-check.log.")
        }
    }
}
