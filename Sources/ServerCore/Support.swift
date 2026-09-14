import Foundation
import Darwin

public struct MonitorError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public struct Paths {
    public let root: URL
    public static var defaultRoot: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Valheim Server Monitor").standardizedFileURL }
    public init(root: URL? = nil) {
        self.root = (root ?? ProcessInfo.processInfo.environment["VSM_HOME"].map { URL(fileURLWithPath: $0) }
            ?? Self.defaultRoot).standardizedFileURL
    }
    public var logs: URL { root.appendingPathComponent("logs") }
    public var server: URL { root.appendingPathComponent("runtime/server") }
    public var executable: URL { server.appendingPathComponent("valheim_server/Valheim") }
    public func file(_ name: String) -> URL { root.appendingPathComponent(name) }
    public func prepare() throws {
        for url in [root, logs] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
    }
    public var isDevelopment: Bool { root != Self.defaultRoot || ProcessInfo.processInfo.environment["VSM_HOME"] != nil }
}
public func atomicWrite(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}
public func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(value)
}
public func withLock<T>(_ url: URL, _ body: () throws -> T) throws -> T {
    let fd = open(url.path, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0 else { throw MonitorError("Cannot open the application lock.") }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw MonitorError("Cannot lock application data.") }
    defer { flock(fd, LOCK_UN) }
    return try body()
}
public struct CommandResult { public let code: Int32; public let output: String }
@discardableResult public func command(_ executable: String, _ args: [String], environment: [String: String]? = nil) throws -> CommandResult {
    let task = Process(); task.executableURL = URL(fileURLWithPath: executable); task.arguments = args
    if let environment { task.environment = environment }
    let pipe = Pipe(); task.standardOutput = pipe; task.standardError = pipe; task.standardInput = FileHandle.nullDevice
    try task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
    return CommandResult(code: task.terminationStatus, output: String(decoding: data, as: UTF8.self))
}
public func checkCommand(_ executable: String, _ args: [String]) throws {
    let result = try command(executable, args)
    guard result.code == 0 else { throw MonitorError(result.output.isEmpty ? "Command failed: \(URL(fileURLWithPath: executable).lastPathComponent)" : result.output) }
}
public func tail(_ url: URL, bytes: Int = 250_000) -> String {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
    defer { try? handle.close() }
    let end = (try? handle.seekToEnd()) ?? 0
    try? handle.seek(toOffset: end > UInt64(bytes) ? end - UInt64(bytes) : 0)
    return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
}
