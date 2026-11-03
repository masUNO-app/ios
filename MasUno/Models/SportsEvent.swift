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
    /// Optional "where exactly" note, e.g. "North court bleachers".
    var meetUpSpot: String = ""
    var notes: String = ""
    var isCancelled = false
    var messages: [ChatMessage] = []
    var unreadCount: Int = 0

    var spotsLeft: Int { max(capacity - attendees.count, 0) }
    var isFull: Bool { spotsLeft == 0 }
    var end: Date { start.addingTimeInterval(duration) }
    var hasEnded: Bool { end < .now }
    var isHostedByYou: Bool { host == Person.you }
    var isYouGoing: Bool { attendees.contains(Person.you) }
    var coordinate: CLLocationCoordinate2D { venue.coordinate }
    var guests: [String] { attendees.filter { $0 != host } }

    /// Starts within the hour — the map labels these pins "Soon".
    func isSoon(now: Date = .now) -> Bool {
        let minutes = start.timeIntervalSince(now) / 60
        return minutes >= 0 && minutes <= 60
    }

    func role(of person: String) -> String { person == host ? "Host" : "Attendee" }

    /// "4 spots left", "1 spot left", "Full".
    var spotsLine: String {
        if isFull { return String(localized: "Full") }
        return spotsLeft == 1 ? String(localized: "1 spot left") : String(localized: "\(spotsLeft) spots left")
    }

    /// "Open · 4 spots left" / "Full".
    var openLine: String {
        isFull ? spotsLine : String(localized: "Open · \(spotsLine)")
    }

    /// SPEC §7.2 status: "3 going · 3 spots left", "3 going · 1 spot left", "Full".
    var statusLine: String {
        isFull ? spotsLine : String(localized: "\(attendees.count) going · \(spotsLine)")
    }
}
