import Foundation
import IOKit.ps

public struct ScheduleTime: Codable, Hashable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public static func < (left: ScheduleTime, right: ScheduleTime) -> Bool {
        (left.hour, left.minute) < (right.hour, right.minute)
    }
}

public enum Schedule: Codable, Hashable, Sendable {
    case manual
    case hourly(minute: Int)
    /// Saved by earlier versions. `normalized` converts it to `weekdays`.
    case daily(hour: Int, minute: Int)
    /// Saved by earlier versions. `normalized` converts it to `weekdays`.
    case weekly(weekday: Int, hour: Int, minute: Int)
    case interval(minutes: Int)
    /// `days` follows launchd: 0 is Sunday, 6 is Saturday.
    case weekdays(days: [Int], times: [ScheduleTime])
    /// `days` are 1 to 31. Days a month doesn't have are skipped that month.
    case monthDays(days: [Int], times: [ScheduleTime])

    public static let allWeekdays = Array(0...6)

    public var normalized: Schedule {
        switch self {
        case .daily(let hour, let minute):
            .weekdays(days: Self.allWeekdays, times: [ScheduleTime(hour: hour, minute: minute)])
        case .weekly(let weekday, let hour, let minute):
            .weekdays(days: [weekday], times: [ScheduleTime(hour: hour, minute: minute)])
        default:
            self
        }
    }

    /// One launchd `StartCalendarInterval` entry per day and time combination.
    public var calendarEntries: [[String: Int]] {
        switch normalized {
        case .hourly(let minute):
            return [["Minute": minute]]
        case .weekdays(let days, let times):
            let uniqueDays = Set(days).sorted()
            // Every day needs no Weekday key, which keeps the agent small.
            let dayEntries: [[String: Int]] = uniqueDays.count == 7 ? [[:]] : uniqueDays.map { ["Weekday": $0] }
            return Self.combine(uniqueDays.isEmpty ? [] : dayEntries, times)
        case .monthDays(let days, let times):
            return Self.combine(Set(days).sorted().map { ["Day": $0] }, times)
        default:
            return []
        }
    }

    private static func combine(_ days: [[String: Int]], _ times: [ScheduleTime]) -> [[String: Int]] {
        days.flatMap { day in
            Set(times).sorted().map { time in
                day.merging(["Hour": time.hour, "Minute": time.minute]) { _, new in new }
            }
        }
    }

    /// Nil for manual and interval schedules: launchd counts intervals from when it
    /// loaded the agent, so the exact time can't be worked out here.
    public func nextRun(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        calendarEntries.compactMap { entry in
            var components = DateComponents()
            components.day = entry["Day"]
            components.hour = entry["Hour"]
            components.minute = entry["Minute"]
            components.second = 0
            // Calendar counts weekdays from 1, launchd from 0.
            components.weekday = entry["Weekday"].map { $0 + 1 }
            return calendar.nextDate(after: date, matching: components, matchingPolicy: .strict)
        }.min()
    }
}

public enum PowerState {
    public static func isOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return false }
        return (source as String) == kIOPSBatteryPowerValue
    }
}
