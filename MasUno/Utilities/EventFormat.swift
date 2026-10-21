import Foundation

enum EventFormat {
    /// "32 min", "1 hr", "2 hr 15 min"
    static func countdown(to date: Date, from now: Date = .now) -> String {
        let minutes = max(Int(date.timeIntervalSince(now) / 60), 0)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    /// "October 11, 2026 · 5:30 PM"
    static func longDate(_ date: Date) -> String {
        "\(date.formatted(.dateTime.month(.wide).day().year())) · \(date.formatted(date: .omitted, time: .shortened))"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        switch minutes {
        case ..<60: return "\(minutes) min"
        case 60: return "1 hour"
        default:
            let hours = Double(minutes) / 60
            return hours == hours.rounded() ? "\(Int(hours)) hours" : String(format: "%.1f hours", hours)
        }
    }
}
