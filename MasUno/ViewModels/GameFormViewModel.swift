import Foundation
import Observation

/// Form state, validation and save/cancel for the game form (SPEC §7.6.2).
/// The same rules are enforced by the server (`create_game` / `update_game`, §8.5).
@Observable
final class GameFormViewModel {
    var sport: Activity
    var name: String { didSet { if name.count > GameDraft.titleLimit { name = String(name.prefix(GameDraft.titleLimit)) } } }
    var day: Date
    var time: Date
    /// Minutes, one of `GameDraft.durations`.
    var duration: Int
    /// Nil until the host picks one; there's no default place.
    var place: Place?
    var meetUpSpot: String { didSet { if meetUpSpot.count > GameDraft.meetPointLimit { meetUpSpot = String(meetUpSpot.prefix(GameDraft.meetPointLimit)) } } }
    var players: Int
    /// Bump the game back to the top when a spot opens (SPEC §7.6.11).
    var autoRepost: Bool
    var notes: String { didSet { if notes.count > GameDraft.notesLimit { notes = String(notes.prefix(GameDraft.notesLimit)) } } }

    /// Errors only show after the first Create/Save tap (Figma "Error" frame).
    var showsErrors = false
    /// Server failure that isn't tied to one field, e.g. the hosting limit.
    var formError: String?
    private(set) var isSaving = false

    /// The game being edited, or nil when creating a new one.
    let editing: Game?

    static let durations = GameDraft.durations
    static let playerRange = GameDraft.capacityRange

    /// - Parameter template: "Play again": a new game that starts from an earlier one's sport,
    ///   name, place and details. The day and time start fresh.
    init(editing: Game? = nil, template: Game? = nil) {
        self.editing = editing
        let source = editing ?? template
        let defaultStart = Calendar.current.date(bySettingHour: 17, minute: 30, second: 0, of: .now) ?? .now
        sport = source?.activity ?? Activity.builtIn[0]
        name = source?.title ?? ""
        day = Calendar.current.startOfDay(for: editing?.startsAt ?? .now)
        time = source?.startsAt ?? defaultStart
        duration = source?.durationMinutes ?? 60
        place = source?.place
        meetUpSpot = source?.meetPoint ?? ""
        players = source?.capacity ?? 6
        notes = source?.notes ?? ""
        autoRepost = source?.autoRepost ?? true
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
        max(Self.playerRange.lowerBound, editing?.goingCount ?? 1)
    }

    /// "6 players".
    var playersLabel: String {
        String(localized: "\(players) players")
    }

    /// Under the count: "Including you", or "3 joined" once people have.
    var playersHint: String {
        guard let editing, editing.joinedCount > 0 else { return String(localized: "Including you") }
        return String(localized: "\(editing.joinedCount) joined")
    }

    /// "5:30 PM", for the Start time field.
    var timeLabel: String {
        EventFormat.time(time)
    }

    /// One-tap answers to "What would help someone new say yes?" (SPEC §7.7.3).
    var suggestions: [String] {
        [
            String(localized: "I have an extra ball"),
            String(localized: "Coming alone is fine"),
            String(localized: "Come for part of it"),
        ]
        .filter { !notes.localizedCaseInsensitiveContains($0) }
    }

    /// Adds a suggestion to the end of the note, as its own sentence.
    func addSuggestion(_ text: String) {
        let current = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else {
            notes = "\(text)."
            return
        }
        let needsStop = !(current.hasSuffix(".") || current.hasSuffix("!") || current.hasSuffix("?"))
        notes = "\(current)\(needsStop ? "." : "") \(text)."
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
        guard showsErrors, start <= .now, editing?.startsAt != start else { return nil }
        let time = start.formatted(date: .omitted, time: .shortened)
        return String(localized: "\(time) has already passed today. Pick a later time.")
    }

    var placeError: String? {
        showsErrors && place == nil ? String(localized: "Pick where the game is.") : nil
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && place != nil && (start > .now || editing?.startsAt == start)
            && [name, meetUpSpot, notes].allSatisfy(TextFilter.isFriendly)
    }

    // MARK: Intents

    /// Validates, then saves. Returns true when the sheet can close.
    func save(in store: GameStore) async -> Bool {
        showsErrors = true
        formError = nil
        guard isValid, let place else { return false }
        let meetPoint = meetUpSpot.trimmingCharacters(in: .whitespaces)
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = GameDraft(
            activity: sport,
            title: name.trimmingCharacters(in: .whitespaces),
            startsAt: start,
            durationMinutes: duration,
            capacity: players,
            notes: notes.isEmpty ? nil : notes,
            place: place,
            meetPoint: meetPoint.isEmpty ? nil : meetPoint,
            autoRepost: autoRepost
        )
        isSaving = true
        defer { isSaving = false }
        do {
            if let editing {
                try await store.updateGame(id: editing.id, draft)
            } else {
                try await store.createGame(draft)
            }
            return true
        } catch {
            formError = (error as? DomainError ?? .offline).message
            return false
        }
    }

    /// Soft cancel (`cancel_game`): everyone going is told; the game leaves the map.
    func cancelGame(in store: GameStore) {
        guard let editing else { return }
        Task { await store.cancelGame(editing.id) }
    }
}
