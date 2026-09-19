import Foundation

/// One fixed deadline; warning delivery never resets the clock.
public struct UpdateCountdown {
    public static let duration: TimeInterval = 15 * 60
    public static let warningMinutes = [15, 10, 5, 1]
    public let deadline: Date
    private var sent: Set<Int> = []
    public init(now: Date = Date()) { deadline = now.addingTimeInterval(Self.duration) }
    public func remaining(at now: Date) -> TimeInterval { max(0, deadline.timeIntervalSince(now)) }
    public mutating func warning(at now: Date) -> Int? {
        let seconds = remaining(at: now)
        guard seconds > 0 else { return nil }
        // If the machine slept, send only the most relevant warning, not a burst of stale ones.
        let due = Self.warningMinutes.filter { !sent.contains($0) && seconds <= Double($0 * 60) }
        guard !due.isEmpty else { return nil }
        sent.formUnion(due)
        return max(1, Int(ceil(seconds / 60)))
    }
}
