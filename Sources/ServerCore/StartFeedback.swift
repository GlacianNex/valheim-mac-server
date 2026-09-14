import Foundation

/// Bridges the interval between the user's click and launchd reporting the service.
public struct StartFeedback {
    public private(set) var requestedAt: Date?
    private var acknowledgedAt: Date?
    public var pending: Bool { requestedAt != nil }
    public init() {}
    public mutating func begin(now: Date = Date()) { requestedAt = now; acknowledgedAt = nil }
    public mutating func commandFinished(success: Bool, now: Date = Date()) {
        if success { acknowledgedAt = now } else { clear() }
    }
    /// Returns true when launchd accepted the request but startup cannot be confirmed.
    public mutating func observe(running: Bool, now: Date = Date()) -> Bool {
        guard pending else { return false }
        if running { clear(); return false }
        if let acknowledgedAt, now.timeIntervalSince(acknowledgedAt) >= 30 {
            clear(); return true
        }
        return false
    }
    private mutating func clear() { requestedAt = nil; acknowledgedAt = nil }
}
