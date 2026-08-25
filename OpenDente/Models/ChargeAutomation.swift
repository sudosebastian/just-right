import Foundation

/// A long-running battery calibration cycle inspired by AlDente's calibration mode.
/// The phase is persisted so a cycle can resume after the app restarts.
enum CalibrationPhase: String, Codable, CaseIterable, Equatable {
    case chargingToFull
    case holdingAtFull
    case dischargingToLow
    case rechargingToFull

    var displayName: String {
        switch self {
        case .chargingToFull:   return "Charging to 100%"
        case .holdingAtFull:    return "Holding at 100%"
        case .dischargingToLow: return "Discharging to 15%"
        case .rechargingToFull: return "Recharging to 100%"
        }
    }

    var shortName: String {
        switch self {
        case .chargingToFull:   return "Charge"
        case .holdingAtFull:    return "Hold"
        case .dischargingToLow: return "Discharge"
        case .rechargingToFull: return "Recharge"
        }
    }

    var stepNumber: Int {
        switch self {
        case .chargingToFull:   return 1
        case .holdingAtFull:    return 2
        case .dischargingToLow: return 3
        case .rechargingToFull: return 4
        }
    }
}

/// Pure scheduling logic, kept separate from the charging manager for deterministic tests.
enum ChargeSchedule {
    static let triggerWindowMinutes = 15

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func shouldStart(
        enabled: Bool,
        weekdays: Set<Int>,
        hour: Int,
        minute: Int,
        now: Date,
        lastTriggeredDay: String?,
        calendar: Calendar = .current
    ) -> Bool {
        guard enabled else { return false }

        let weekday = calendar.component(.weekday, from: now)
        guard weekdays.contains(weekday) else { return false }

        let today = dayKey(for: now, calendar: calendar)
        guard lastTriggeredDay != today else { return false }

        let currentMinute = calendar.component(.hour, from: now) * 60
            + calendar.component(.minute, from: now)
        let scheduledMinute = min(23, max(0, hour)) * 60 + min(59, max(0, minute))

        return currentMinute >= scheduledMinute
            && currentMinute < scheduledMinute + triggerWindowMinutes
    }

    static func nextOccurrence(
        weekdays: Set<Int>,
        hour: Int,
        minute: Int,
        after date: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard !weekdays.isEmpty else { return nil }

        for dayOffset in 0...7 {
            guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: candidateDay)
            components.hour = min(23, max(0, hour))
            components.minute = min(59, max(0, minute))
            components.second = 0

            guard let candidate = calendar.date(from: components),
                  weekdays.contains(calendar.component(.weekday, from: candidate)) else { continue }

            if candidate > date { return candidate }
        }

        return nil
    }
}
