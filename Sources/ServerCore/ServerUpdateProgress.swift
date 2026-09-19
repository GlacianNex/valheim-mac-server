import Foundation

public struct ServerUpdateProgress {
    public enum Phase { case countdown, preparing, stopping, installing, starting }
    public let phase: Phase
    public let message: String
    public let percent: Double?
    public init(_ phase: Phase, message: String, percent: Double? = nil) {
        self.phase = phase; self.message = message; self.percent = percent
    }
    public var title: String {
        switch phase {
        case .countdown: return message
        case .preparing: return "Preparing…"
        case .stopping: return "Stopping…"
        case .starting: return "Starting…"
        case .installing:
            return "Updating" + (percent.map { " \(Int($0))%" } ?? "…")
        }
    }
}

public enum ServerUpdatePolicy {
    public static func serversAreEmpty(_ servers: [ServerStatus]) -> Bool {
        servers.allSatisfy { !$0.running || ($0.state == "Online" && $0.players == "0") }
    }
    public static let checkInterval: TimeInterval = 600
    public static func shouldStart(enabled: Bool, installed: String?, latest: String?, busy: Bool, lastAttempt: String?) -> Bool {
        guard enabled, !busy, let installed, let latest, latest != lastAttempt else { return false }
        return ServerVersion.updateAvailable(installed: installed, latest: latest)
    }
}
