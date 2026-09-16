import Foundation
import Darwin

public final class Installer {
    public let paths: Paths
    public init(paths: Paths) { self.paths = paths }
    public static var needsRosetta: Bool {
        var arm: Int32 = 0; var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0)
        guard arm == 1 else { return false }
        return (try? command("/usr/bin/arch", ["-x86_64", "/usr/bin/true"]).code) != 0
    }
    public static func installRosetta() throws {
        try checkCommand("/usr/sbin/softwareupdate", ["--install-rosetta", "--agree-to-license"])
    }
    private func run(_ executable: URL, _ arguments: [String], log: FileHandle) throws -> Int32 {
        let process = Process(); process.executableURL = executable; process.arguments = arguments
        process.standardInput = FileHandle.nullDevice; process.standardOutput = log; process.standardError = log
        try process.run(); process.waitUntilExit(); return process.terminationStatus
    }
    /// macOS 27 lipo rejects multiple architectures in one -verify_arch invocation.
    /// Keep both checks mandatory before replacing the installed runtime.
    static func verifyArchitectures(_ file: URL) throws {
        for architecture in ["arm64", "x86_64"] {
            try checkCommand("/usr/bin/lipo", [file.path, "-verify_arch", architecture])
        }
    }
    public func install() throws {
        try paths.prepare()
        let runtimeLease = try RuntimeLease(paths: paths, exclusive: true)
        defer { withExtendedLifetime(runtimeLease) {} }
        for server in try Fleet(paths: paths).lifecycles() {
            if let record = server.record, server.owns(record) { throw MonitorError("Stop all servers before updating the shared runtime.") }
        }
        // The legacy lock also protects services started by an older app version.
        let fd = open(paths.file("service.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw MonitorError("Cannot lock server installation.") }; defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw MonitorError("Stop the server before installing or updating it.") }
        defer { flock(fd, LOCK_UN) }
        if let record = Lifecycle(paths: paths).record, Lifecycle(paths: paths).owns(record) { throw MonitorError("Stop the server before updating it.") }
        guard !Self.needsRosetta else { throw MonitorError("Valve's installer requires Rosetta on Apple Silicon. Use Install Rosetta in Setup, then retry. The Valheim server itself runs natively.") }
        try atomicWrite(Data(String(getpid()).utf8), to: paths.file("installing"))
        defer { try? FileManager.default.removeItem(at: paths.file("installing")) }
        let fm = FileManager.default
        let runtime = paths.file("runtime"), steam = runtime.appendingPathComponent("steamcmd")
        try fm.createDirectory(at: steam, withIntermediateDirectories: true)
        let logURL = paths.logs.appendingPathComponent("installation.log")
        fm.createFile(atPath: logURL.path, contents: Data("[Monitor] Preparing Valve’s download tool…\n".utf8), attributes: [.posixPermissions: 0o600])
        let log = try FileHandle(forWritingTo: logURL); try log.seekToEnd(); defer { try? log.close() }
        let script = steam.appendingPathComponent("steamcmd.sh")
        if !fm.fileExists(atPath: script.path) {
            let archive = runtime.appendingPathComponent("steamcmd.tar.gz")
            let result = try run(URL(fileURLWithPath: "/usr/bin/curl"), ["--fail", "--location", "--proto", "=https", "--tlsv1.2", "--retry", "3", "--connect-timeout", "20", "--max-time", "1800", "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz", "--output", archive.path], log: log)
            guard result == 0 else { throw MonitorError("Valve's installer could not be downloaded. Check your connection and retry. See installation.log.") }
            try checkCommand("/usr/bin/tar", ["-xzf", archive.path, "-C", steam.path])
            try? fm.removeItem(at: archive)
        }
        let staging = runtime.appendingPathComponent("server-download")
        let args = ["+force_install_dir", staging.path, "+login", "anonymous", "+app_update", "896660", "validate", "+quit"]
        // SteamCMD can exit once after updating itself. A second invocation completes bootstrap.
        try log.write(contentsOf: Data("\n[Monitor] Connecting to Valve…\n".utf8))
        var result = try run(script, args, log: log)
        if result != 0 { result = try run(script, args, log: log) }
        try log.write(contentsOf: Data("\n[Monitor] Checking the downloaded server…\n".utf8))
        let binary = staging.appendingPathComponent("valheim_server/Valheim")
        for library in ["steamclient.dylib", "libtier0_s.dylib", "libvstdlib_s.dylib", "libaudio.dylib"] {
            let file = steam.appendingPathComponent(library)
            guard fm.fileExists(atPath: file.path) else { throw MonitorError("Valve's downloader is missing \(library). Retry installation.") }
            try Self.verifyArchitectures(file)
        }
        guard result == 0, fm.isExecutableFile(atPath: binary.path), tail(logURL).contains("Success! App '896660' fully installed") else {
            throw MonitorError("Native server installation did not complete. Your previous installation is unchanged. Check installation.log and retry.")
        }
        try checkCommand("/usr/bin/codesign", ["--verify", "--deep", "--strict", binary.path])
        try Self.verifyArchitectures(binary)
        try log.write(contentsOf: Data("\n[Monitor] Finishing installation…\n".utf8))
        let backup = runtime.appendingPathComponent("server-previous")
        if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
        let hadServer = fm.fileExists(atPath: paths.server.path)
        if hadServer { try fm.moveItem(at: paths.server, to: backup) }
        do { try fm.moveItem(at: staging, to: paths.server) }
        catch { if hadServer { try? fm.moveItem(at: backup, to: paths.server) }; throw error }
        // Keep one previous runtime for recovery; world saves live elsewhere.
        try log.write(contentsOf: Data("\n[Monitor] Server installed. Ready to create or import a world.\n".utf8))
    }
}
