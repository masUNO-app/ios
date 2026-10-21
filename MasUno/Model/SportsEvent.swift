import CoreLocation
import Foundation

enum Person {
    /// The signed-in user. There's no auth yet, so "You" is a fixed local identity.
    static let you = "You"
}

enum Sport: String, CaseIterable, Identifiable, Hashable {
    case basketball, tennis, soccer, volleyball
    // Non-sport categories only appear in the plans mock data from Figma.
    // MVP posting is limited to `Sport.postable`.
    case music, social, games

    var id: Self { self }
    var name: String { rawValue.capitalized }

    var emoji: String {
        switch self {
        case .basketball: "🏀"
        case .tennis: "🎾"
        case .soccer: "⚽️"
        case .volleyball: "🏐"
        case .music: "🎵"
        case .social: "☕️"
        case .games: "🎲"
        }
    }

    /// SF Symbol for the icon tile on plan cards (non-sport events).
    var symbol: String? {
        switch self {
        case .music: "music.note"
        case .social: "cup.and.saucer"
        case .games: "dice"
        default: nil
        }
    }

    var category: String {
        switch self {
        case .basketball, .tennis, .soccer, .volleyball: "Sports"
        case .music: "Music"
        case .social: "Social"
        case .games: "Games"
        }
    }

    static let postable: [Sport] = [.basketball, .tennis, .soccer, .volleyball]
}

enum SkillLevel: String, CaseIterable, Identifiable {
    case allLevels = "All levels"
    case casual = "Casual"
    case competitive = "Competitive"

    var id: Self { self }
}

struct Venue: Hashable, Identifiable {
    var name: String
    var street: String
    var city: String
    var latitude: Double
    var longitude: Double

    var id: String { name }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    /// "760 Market Street, San Francisco, CA 94107"
    var fullAddress: String { "\(street), \(city)" }

    /// "Dolores Park · 19th & Dolores St" (or just the street when the venue is an address)
    var titleLine: String { name == street ? street : "\(name) · \(street)" }
}

struct ChatMessage: Identifiable, Hashable {
    var id = UUID()
    var sender: String
    var text: String
    var sentAt: Date
}

struct SportsEvent: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var sport: Sport
    var host: String
    var start: Date
    var duration: TimeInterval
    /// Total players, including the host.
    var capacity: Int
    /// Everyone going, host first.
    var attendees: [String]
    var venue: Venue
    var skillLevel: SkillLevel = .allLevels
    var notes: String = ""
    var messages: [ChatMessage] = []
    var unreadCount: Int = 0
    /// Whether the current user bookmarked this event.
    var isBookmarked = false
    /// Mock count of other students watching this event (would come from the backend).
    var otherBookmarkCount = 0

    var spotsLeft: Int { max(capacity - attendees.count, 0) }
    var isFull: Bool { spotsLeft == 0 }
    var end: Date { start.addingTimeInterval(duration) }
    var hasEnded: Bool { end < .now }
    var isHostedByYou: Bool { host == Person.you }
    var isYouGoing: Bool { attendees.contains(Person.you) }
    var coordinate: CLLocationCoordinate2D { venue.coordinate }
    var guests: [String] { attendees.filter { $0 != host } }

    func role(of person: String) -> String { person == host ? "Host" : "Attendee" }

    /// "2/3 | 1 Spot left"
    var capacitySummary: String {
        let spots = spotsLeft == 1 ? "1 Spot left" : "\(spotsLeft) Spots left"
        return "\(attendees.count)/\(capacity) | \(isFull ? "Full" : spots)"
    }

    /// "Sports · 2/3 participants · 1 spot left"
    func metaLine(noun: String = "participants") -> String {
        let spots = isFull ? "Full" : (spotsLeft == 1 ? "1 spot left" : "\(spotsLeft) spots left")
        return "\(sport.category) · \(attendees.count)/\(capacity) \(noun) · \(spots)"
    }
}

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
