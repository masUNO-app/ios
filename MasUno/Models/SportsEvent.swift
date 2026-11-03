import CoreLocation
import Foundation

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

    /// SPEC §7.2 status: "3 going · 3 spots left", "3 going · 1 spot left", "Full".
    var statusLine: String {
        if isFull { return String(localized: "Full") }
        let spots = spotsLeft == 1 ? String(localized: "1 spot left") : String(localized: "\(spotsLeft) spots left")
        return String(localized: "\(attendees.count) going · \(spots)")
    }

    /// "Sports · 2/3 participants · 1 spot left"
    func metaLine(noun: String = "participants") -> String {
        let spots = isFull ? "Full" : (spotsLeft == 1 ? "1 spot left" : "\(spotsLeft) spots left")
        return "\(sport.category) · \(attendees.count)/\(capacity) \(noun) · \(spots)"
    }
}
