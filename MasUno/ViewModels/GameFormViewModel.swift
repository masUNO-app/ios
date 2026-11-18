import Foundation
import Observation

/// Form state, validation and save/cancel for the game form (SPEC §7.6.2).
/// The same rules are enforced by the server (`create_game` / `update_game`, §8.5).
@Observable
final class GameFormViewModel {
    /// The fields that can have a problem, in the order the form shows them.
    enum Field: Hashable, CaseIterable {
        case name, time, place, meetUp, notes
    }

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
    var title: String { isEditing ? String.app("Edit game") : String.app("Add game") }
    var subtitle: String { isEditing ? String.app("Changes are shared with everyone going.") : String.app("Get a game going nearby.") }
    var saveButtonTitle: String { isEditing ? String.app("Save changes") : String.app("Create game") }

    /// Today through 6 days out (games start within 7 days).
    var dayOptions: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0...6).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    /// Editing can't go below the number already going.
    var minimumPlayers: Int {
        max(Self.playerRange.lowerBound, editing?.goingCount ?? 1)
    }

    /// What the stepper allows.
    var playersRange: ClosedRange<Int> {
        minimumPlayers...Self.playerRange.upperBound
    }

    /// One step up or down, for VoiceOver's swipe; stays in `playersRange`.
    func stepPlayers(by step: Int) {
        players = min(max(players + step, playersRange.lowerBound), playersRange.upperBound)
    }

    /// "6 players".
    var playersLabel: String {
        String.app("\(players) players")
    }

    /// Under the count: "Including you", or "3 joined" once people have.
    var playersHint: String {
        guard let editing, editing.joinedCount > 0 else { return String.app("Including you") }
        return String.app("\(editing.joinedCount) joined")
    }

    /// "5:30 PM", for the Start time field.
    var timeLabel: String {
        EventFormat.time(time)
    }

    /// One-tap answers to "What would help someone new say yes?" (SPEC §7.7.3).
    var suggestions: [String] {
        [
            String.app("I have an extra ball"),
            String.app("Coming alone is fine"),
            String.app("Come for part of it"),
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
            return String.app("Add a name so people know what they're joining.")
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
        return String.app("\(time) has already passed today. Pick a later time.")
    }

    var placeError: String? {
        showsErrors && place == nil ? String.app("Pick where the game is.") : nil
    }

    func error(for field: Field) -> String? {
        switch field {
        case .name: nameError
        case .time: timeError
        case .place: placeError
        case .meetUp: meetUpError
        case .notes: notesError
        }
    }

    /// Where VoiceOver goes after a failed Create/Save: the first field with a problem.
    var firstInvalidField: Field? {
        Field.allCases.first { error(for: $0) != nil }
    }

    /// What VoiceOver says after a failed Create/Save: the first problem, and how many there are,
    /// or the server's message when no field has one.
    var errorSummary: String? {
        let errors = Field.allCases.compactMap(error(for:))
        guard let first = errors.first else { return formError }
        return errors.count == 1 ? first : String.app("\(errors.count) things to fix. \(first)")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && place != nil && (start > .now || editing?.startsAt == start)
            && [name, meetUpSpot, notes].allSatisfy(TextFilter.isFriendly)
    }

    // MARK: Intents

    /// Validates, then saves. Returns true when the sheet can close.
    func save(in store: GameStore) async -> Bool {
        guard !isSaving else { return false }
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
            guard !OperationCancellation.isCancellation(error) else { return false }
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
