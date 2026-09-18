import Foundation

public struct ServerUpdateProgress {
    public enum Phase { case preparing, stopping, installing, starting }
    public let phase: Phase
    public let message: String
    public let percent: Double?
    public init(_ phase: Phase, message: String, percent: Double? = nil) {
        self.phase = phase; self.message = message; self.percent = percent
    }
    public var title: String {
        switch phase {
        case .preparing: return "Preparing update…"
        case .stopping: return "Stopping…"
        case .starting: return "Starting…"
        case .installing:
            return "Updating" + (percent.map { " \(Int($0))%" } ?? "…")
        }
    }
}
