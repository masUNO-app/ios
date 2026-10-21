import Foundation
import Observation

/// Form state and save logic for the Add/Edit event sheet.
@Observable
final class AddEventViewModel {
    var sport: Sport
    var name: String
    var day: Date
    var time: Date
    var duration: TimeInterval
    var venue: Venue
    var players: Int
    var skill: SkillLevel
    var notes: String

    /// The event being edited, or nil when creating a new one.
    let editing: SportsEvent?

    static let durations: [TimeInterval] = [1800, 3600, 5400, 7200, 10800]
    static let playerCounts = Array(2...22)

    init(editing: SportsEvent? = nil) {
        self.editing = editing
        let defaultStart = Calendar.current.date(bySettingHour: 17, minute: 30, second: 0, of: .now) ?? .now
        sport = editing?.sport ?? .basketball
        name = editing?.title ?? ""
        day = Calendar.current.startOfDay(for: editing?.start ?? .now)
        time = editing?.start ?? defaultStart
        duration = editing?.duration ?? 3600
        venue = editing?.venue ?? MockData.Venues.postable[0]
        players = editing?.capacity ?? 6
        skill = editing?.skillLevel ?? .allLevels
        notes = editing?.notes ?? ""
    }

    // MARK: Presentation

    var title: String { editing == nil ? "Add event" : "Edit event" }
    var subtitle: String { editing == nil ? "Get a game going nearby." : "Update the details for your group." }
    var saveButtonTitle: String { editing == nil ? "Create event" : "Save changes" }

    var isNameValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Games are posted up to 2 days ahead (today, tomorrow, the day after).
    var dayOptions: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0...2).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    var sportOptions: [Sport] {
        // Keep a non-sport category selectable when editing one of the Figma mock events.
        Sport.postable.contains(sport) ? Sport.postable : [sport] + Sport.postable
    }

    func dayLabel(_ date: Date) -> String {
        let label = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if Calendar.current.isDateInToday(date) { return "Today · \(label)" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow · \(label)" }
        return label
    }

    // MARK: Intents

    /// Builds the event from the form and persists it in the store.
    func save(in store: EventStore) {
        let calendar = Calendar.current
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        let start = calendar.date(bySettingHour: clock.hour ?? 17, minute: clock.minute ?? 30, second: 0, of: day) ?? day
        let title = name.trimmingCharacters(in: .whitespaces)

        var event = editing ?? SportsEvent(
            title: title, sport: sport, host: Person.you, start: start, duration: duration,
            capacity: players, attendees: [Person.you], venue: venue
        )
        event.title = title
        event.sport = sport
        event.start = start
        event.duration = duration
        event.venue = venue
        event.capacity = max(players, event.attendees.count)
        event.skillLevel = skill
        event.notes = notes

        store.save(event)
    }
}
