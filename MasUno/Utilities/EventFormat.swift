import CoreLocation
import Foundation

enum EventFormat {
    /// "32 min", "1 hr", "2 hr 15 min", "2 days"
    static func countdown(to date: Date, from now: Date = .now) -> String {
        let minutes = max(Int(date.timeIntervalSince(now) / 60), 0)
        if minutes < 60 { return String.app("\(minutes) min") }
        if minutes >= 24 * 60 {
            let days = minutes / (24 * 60)
            return days == 1 ? String.app("1 day") : String.app("\(days) days")
        }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? String.app("\(hours) hr") : String.app("\(hours) hr \(rest) min")
    }

    /// "Today", "Tomorrow", "Fri, Oct 30"
    static func day(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String.app("Today") }
        if calendar.isDateInTomorrow(date) { return String.app("Tomorrow") }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(LanguageSettings.shared.locale))
    }

    /// "7:35 PM"
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(LanguageSettings.shared.locale))
    }

    /// "Today · 7:35 PM", "Fri, Oct 30 · 6:30 PM"
    static func dayAndTime(_ date: Date) -> String {
        "\(day(date)) · \(time(date))"
    }

    /// One line on a card: "Today, 7:35 PM · starts in 35 min", "Tomorrow, 6:00 PM · about 1 hour",
    /// "Sun, Nov 8 · 10:00 AM". A comma after Today and Tomorrow keeps it to one "·" per line.
    static func cardTime(_ game: Game, now: Date = .now) -> String {
        let calendar = Calendar.current
        let isNear = calendar.isDateInToday(game.startsAt) || calendar.isDateInTomorrow(game.startsAt)
        guard isNear else { return dayAndTime(game.startsAt) }
        let start = "\(day(game.startsAt)), \(time(game.startsAt))"
        if game.hasEnded(now: now) { return start }
        if game.isSoon(now: now) { return String.app("\(start) · starts in \(countdown(to: game.startsAt, from: now))") }
        return String.app("\(start) · about \(duration(game.durationMinutes))")
    }

    /// A cancelled game's card: "Was today, 7:35 PM", "Was Sun, Nov 8 · 10:00 AM".
    static func cancelledTime(_ game: Game) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(game.startsAt) { return String.app("Was today, \(time(game.startsAt))") }
        if calendar.isDateInTomorrow(game.startsAt) { return String.app("Was tomorrow, \(time(game.startsAt))") }
        return String.app("Was \(dayAndTime(game.startsAt))")
    }

    /// A search result: "Today, 7:35 PM", "Sat, 9:00 AM".
    static func shortDayAndTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) || calendar.isDateInTomorrow(date) { return "\(day(date)), \(time(date))" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).locale(LanguageSettings.shared.locale))), \(time(date))"
    }

    /// "Starts in 35 min · about 1 hour" (or "Started · about 1 hour" once it's underway).
    static func startsIn(_ game: Game, now: Date = .now) -> String {
        let length = String.app("about \(duration(game.durationMinutes))")
        if game.endsAt <= now { return String.app("Ended · \(length)") }
        guard game.startsAt > now else { return String.app("Started · \(length)") }
        return String.app("Starts in \(countdown(to: game.startsAt, from: now)) · \(length)")
    }

    /// "30 min", "1 hour", "1.5 hours"
    static func duration(_ minutes: Int) -> String {
        switch minutes {
        case ..<60: return String.app("\(minutes) min")
        case 60: return String.app("1 hour")
        default:
            let hours = Double(minutes) / 60
            return hours == hours.rounded()
                ? String.app("\(Int(hours)) hours")
                : String.app("\(hours.formatted(.number.precision(.fractionLength(1)).locale(LanguageSettings.shared.locale))) hours")
        }
    }

    /// "0.4 km" or "0.2 mi", whichever the phone's region uses.
    static func distance(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> String {
        let meters = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
        // Always one unit and one decimal: `.road` switches to feet and yards up close.
        let isMetric = Locale.current.measurementSystem == .metric
        return Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: isMetric ? .kilometers : .miles)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))).locale(LanguageSettings.shared.locale))
    }
}
