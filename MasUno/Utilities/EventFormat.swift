import Foundation

enum EventFormat {
    /// "32 min", "1 hr", "2 hr 15 min", "2 days"
    static func countdown(to date: Date, from now: Date = .now) -> String {
        let minutes = max(Int(date.timeIntervalSince(now) / 60), 0)
        if minutes < 60 { return String(localized: "\(minutes) min") }
        if minutes >= 24 * 60 {
            let days = minutes / (24 * 60)
            return days == 1 ? String(localized: "1 day") : String(localized: "\(days) days")
        }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? String(localized: "\(hours) hr") : String(localized: "\(hours) hr \(rest) min")
    }

    /// "Today", "Tomorrow", "Fri, Oct 30"
    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInTomorrow(date) { return String(localized: "Tomorrow") }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "Today · 7:35 PM", "Fri, Oct 30 · 6:30 PM"
    static func dayAndTime(_ date: Date) -> String {
        "\(day(date)) · \(date.formatted(date: .omitted, time: .shortened))"
    }

    /// "Starts in 35 min · about 1 hour" (or "Started · about 1 hour" once it's underway).
    static func startsIn(_ game: Game, now: Date = .now) -> String {
        let length = String(localized: "about \(duration(game.durationMinutes))")
        if game.endsAt <= now { return String(localized: "Ended · \(length)") }
        guard game.startsAt > now else { return String(localized: "Started · \(length)") }
        return String(localized: "Starts in \(countdown(to: game.startsAt, from: now)) · \(length)")
    }

    /// "30 min", "1 hour", "1.5 hours"
    static func duration(_ minutes: Int) -> String {
        switch minutes {
        case ..<60: return String(localized: "\(minutes) min")
        case 60: return String(localized: "1 hour")
        default:
            let hours = Double(minutes) / 60
            return hours == hours.rounded()
                ? String(localized: "\(Int(hours)) hours")
                : String(localized: "\(hours.formatted(.number.precision(.fractionLength(1)))) hours")
        }
    }
}
