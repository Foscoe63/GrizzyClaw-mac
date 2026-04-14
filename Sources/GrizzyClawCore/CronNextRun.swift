import Foundation
import SwifCron

/// Next fire time for standard 5-field cron strings (same format as Python `croniter` + `SchedulerDialog`).
public enum CronNextRun {
    /// Returns the next scheduled instant strictly after `from`, or `nil` if the expression is invalid.
    public static func nextDate(cron: String, from: Date = Date()) -> Date? {
        let trimmed = cron.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let c = try SwifCron(trimmed)
            return try c.next(from: from)
        } catch {
            return nil
        }
    }
}
