import Foundation
import Observation

/// Form state, validation and save/cancel for the game form (SPEC §7.6.2).
/// The same rules are enforced by the server (`create_game` / `update_game`, §8.5).
@Observable
final class GameFormViewModel {
    var sport: Sport
    var name: String { didSet { if name.count > Self.nameLimit { name = String(name.prefix(Self.nameLimit)) } } }
    var day: Date
    var time: Date
    var duration: TimeInterval
    var venue: Venue
    var meetUpSpot: String { didSet { if meetUpSpot.count > Self.meetUpLimit { meetUpSpot = String(meetUpSpot.prefix(Self.meetUpLimit)) } } }
    var players: Int
    /// Bump the game back to the top when a spot opens (see `SportsEvent.autoRepost`).
    var autoRepost: Bool
    var notes: String { didSet { if notes.count > Self.notesLimit { notes = String(notes.prefix(Self.notesLimit)) } } }

    /// Errors only show after the first Create/Save tap (Figma "Error" frame).
    var showsErrors = false
    /// Server-style failure that isn't tied to one field, e.g. the hosting limit.
    var formError: String?

    /// The game being edited, or nil when creating a new one.
    let editing: SportsEvent?

    static let nameLimit = 40
    static let meetUpLimit = 80
    static let notesLimit = 280
    static let maxUpcomingHosted = 3
    static let durations: [TimeInterval] = [1800, 3600, 5400, 7200, 10800]
    static let playerRange = 2...22

    init(editing: SportsEvent? = nil) {
        self.editing = editing
        let defaultStart = Calendar.current.date(bySettingHour: 17, minute: 30, second: 0, of: .now) ?? .now
        sport = editing?.sport ?? .basketball
        name = editing?.title ?? ""
        day = Calendar.current.startOfDay(for: editing?.start ?? .now)
        time = editing?.start ?? defaultStart
        duration = editing?.duration ?? 3600
        venue = editing?.venue ?? MockData.Venues.basketballCourts
        meetUpSpot = editing?.meetUpSpot ?? ""
        players = editing?.capacity ?? 6
        notes = editing?.notes ?? ""
        autoRepost = editing?.autoRepost ?? true
    }

    // MARK: Presentation

    var isEditing: Bool { editing != nil }
    var title: String { isEditing ? String(localized: "Edit game") : String(localized: "Add game") }
    var subtitle: String { isEditing ? String(localized: "Changes are shared with everyone going.") : String(localized: "Get a game going nearby.") }
    var saveButtonTitle: String { isEditing ? String(localized: "Save changes") : String(localized: "Create game") }

    /// Today through 6 days out (games start within 7 days).
    var dayOptions: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0...6).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    /// Editing can't go below the number already going.
    var minimumPlayers: Int {
        max(Self.playerRange.lowerBound, editing?.attendees.count ?? 1)
    }

    /// "6 players" or, when editing, "6 players · 3 going".
    var playersLabel: String {
        guard let editing else { return String(localized: "\(players) players") }
        return String(localized: "\(players) players · \(editing.attendees.count) going")
    }

    func dayLabel(_ date: Date) -> String {
        EventFormat.day(date)
    }

    var start: Date {
        let calendar = Calendar.current
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: clock.hour ?? 17, minute: clock.minute ?? 30, second: 0, of: day) ?? day
    }

    // MARK: Validation

    var nameError: String? {
        guard showsErrors else { return nil }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(localized: "Add a name so people know what they're joining.")
        }
        return TextFilter.isFriendly(name) ? nil : TextFilter.message
    }

    var meetUpError: String? {
        showsErrors && !TextFilter.isFriendly(meetUpSpot) ? TextFilter.message : nil
    }

    var notesError: String? {
        showsErrors && !TextFilter.isFriendly(notes) ? TextFilter.message : nil
    }

    var timeError: String? {
        guard showsErrors, start <= .now else { return nil }
        let time = start.formatted(date: .omitted, time: .shortened)
        return String(localized: "\(time) has already passed today. Pick a later time.")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && start > .now
            && [name, meetUpSpot, notes].allSatisfy(TextFilter.isFriendly)
    }

    // MARK: Intents

    /// Validates, then saves. Returns true when the sheet can close.
    func save(in store: EventStore) -> Bool {
        showsErrors = true
        formError = nil
        guard isValid else { return false }

        if !isEditing {
            let upcoming = store.hostedEvents.filter { !$0.hasEnded }.count
            guard upcoming < Self.maxUpcomingHosted else {
                // Server error `limit_reached`.
                formError = String(localized: "You can host up to 3 upcoming games. Cancel one to post another.")
                return false
            }
        }

        var event = editing ?? SportsEvent(
            title: "", sport: sport, host: Person.you, start: start, duration: duration,
            capacity: players, attendees: [Person.you], venue: venue
        )
        event.title = name.trimmingCharacters(in: .whitespaces)
        event.sport = sport
        event.start = start
        event.duration = duration
        event.venue = venue
        event.meetUpSpot = meetUpSpot.trimmingCharacters(in: .whitespaces)
        event.capacity = max(players, event.attendees.count)
        event.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        event.autoRepost = autoRepost
        // Raising capacity on a full game opens a spot too.
        let wasFull = editing?.isFull ?? false

        store.save(event)
        if wasFull, !event.isFull { store.autoRepostIfNeeded(event.id) }
        return true
    }

    /// Soft cancel (`cancel_game`): everyone going is told; the game leaves the map.
    func cancelGame(in store: EventStore) {
        guard let editing else { return }
        store.cancel(editing.id)
    }
}
