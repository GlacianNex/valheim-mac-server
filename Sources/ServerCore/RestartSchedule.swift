import Foundation

public struct RestartSchedule: Codable, Equatable {
    public enum Frequency: String, Codable, CaseIterable { case daily, interval, weekdays }
    public enum Players: String, Codable, CaseIterable { case warn, skip, postpone }
    public var enabled = false
    public var frequency: Frequency = .daily
    public var everyDays = 2
    public var weekdays: Set<Int> = [2,3,4,5,6]
    public var hour = 3
    public var minute = 0
    public var anchor = Date()
    public var players: Players = .warn
    public init() {}
    public func validate() throws {
        guard (0...23).contains(hour), (0...59).contains(minute), (1...365).contains(everyDays),
              weekdays.allSatisfy({ (1...7).contains($0) }), frequency != .weekdays || !weekdays.isEmpty else {
            throw MonitorError("Choose a valid time, interval (1–365 days), and at least one weekday.")
        }
    }
    /// Local calendar days; DST gaps use the next valid time, repeated hours run once.
    public func occurrence(on date: Date, calendar: Calendar = .current) -> Date? {
        guard enabled else { return nil }
        let day = calendar.startOfDay(for: date)
        if frequency == .weekdays && !weekdays.contains(calendar.component(.weekday, from: day)) { return nil }
        if frequency == .interval {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: anchor), to: day).day ?? -1
            guard days >= 0, days % max(1, everyDays) == 0 else { return nil }
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day,
                             matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }
    public func next(after now: Date, calendar: Calendar = .current) -> Date? {
        guard enabled else { return nil }
        for offset in 0...366 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            if let date = occurrence(on: day, calendar: calendar), date > now { return date }
        }
        return nil
    }
    public func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year,.month,.day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0,c.month ?? 0,c.day ?? 0)
    }
}

public struct RestartReceipt: Codable {
    public var occurrence: String
    public var due: Date
    public var state: String
    public init(occurrence: String, due: Date, state: String) { self.occurrence = occurrence; self.due = due; self.state = state }
}

/// Clock-driven decisions only. Network and process operations live in the workflow.
public enum ScheduledRestartPolicy {
    public enum Decision: Equatable { case none, waiting, skip(String), run(Date) }
    public static func decide(schedule: RestartSchedule, receipt: RestartReceipt?, now: Date,
                              running: Bool, players: Int?, canWarn: Bool, calendar: Calendar = .current) -> Decision {
        guard schedule.enabled else { return .none }
        let lead: TimeInterval = schedule.players == .warn ? UpdateCountdown.duration : 0
        // Include tomorrow when its warning window crosses midnight.
        let candidates = [-1,0,1].compactMap { calendar.date(byAdding: .day, value: $0, to: now) }
            .compactMap { schedule.occurrence(on: $0, calendar: calendar) }.filter { $0 <= now.addingTimeInterval(lead) }.sorted()
        guard let due = candidates.last else { return .none }
        let key = schedule.key(for: due, calendar: calendar)
        let pending = receipt?.occurrence == key && receipt?.state == "waiting"
        if receipt?.occurrence == key && !pending { return .none }
        guard running else { return .skip("Server is stopped") }
        // A closed manager or sleeping Mac must not replay missed restarts on return.
        if now.timeIntervalSince(due) > 60 && !pending { return .skip("Missed while manager was unavailable") }
        switch schedule.players {
        case .skip: return players == 0 ? .run(now) : .skip("Players connected or count unavailable")
        case .postpone: return players == 0 ? .run(now) : .waiting
        case .warn:
            if canWarn {
                // Delayed/waiting runs still give a full warning period.
                return .run(pending || now > due.addingTimeInterval(-lead + 30) ? now.addingTimeInterval(lead) : due)
            }
            return players == 0 && now >= due ? .run(now) : .waiting
        }
    }
    public static func candidate(schedule: RestartSchedule, now: Date, calendar: Calendar = .current) -> Date? {
        let lead: TimeInterval = schedule.players == .warn ? UpdateCountdown.duration : 0
        return [-1,0,1].compactMap { calendar.date(byAdding: .day, value: $0, to: now) }
            .compactMap { schedule.occurrence(on: $0, calendar: calendar) }.filter { $0 <= now.addingTimeInterval(lead) }.max()
    }
}

public extension Store {
    func claimScheduledRestart(id: String, configuration: RestartSchedule, receipt: RestartReceipt) throws -> Bool {
        try update { db in
            guard db.profiles.contains(where:{$0.id == id}), db.restartSchedules?[id] == configuration,
                  configuration.enabled else { return false }
            if let current = db.restartReceipts?[id], current.occurrence == receipt.occurrence && current.state != "waiting" { return false }
            if db.restartReceipts == nil { db.restartReceipts = [:] }
            db.restartReceipts?[id] = receipt
            return true
        }
    }
}
