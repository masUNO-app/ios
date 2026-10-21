import Foundation
import Observation

/// In-memory source of truth. No backend yet — everything resets on launch.
@Observable
final class EventStore {
    var events: [SportsEvent]

    // Map UI state
    var searchText = ""
    /// Empty means "all sports".
    var sportFilter: Set<Sport> = []

    // Add/edit sheet
    var isAddingEvent = false
    var editingEventID: SportsEvent.ID?
    /// Set after creating an event so the map can jump to it.
    var lastCreatedID: SportsEvent.ID?

    /// Banner text for in-app notices (stand-in for push notifications).
    var notice: String?

    init(events: [SportsEvent] = MockData.events()) {
        self.events = events
    }

    // MARK: Queries

    /// The map only shows sports games you can actually join: open spots, not over.
    var mapEvents: [SportsEvent] {
        events.filter { Sport.postable.contains($0.sport) && !$0.isFull && !$0.hasEnded && matchesSearch($0) && matchesFilter($0) }
    }

    var bookmarkedEvents: [SportsEvent] {
        events.filter { $0.isBookmarked && !$0.hasEnded }.sorted { $0.start < $1.start }
    }

    /// Events you RSVP'd to as a guest.
    var registeredEvents: [SportsEvent] {
        events.filter { $0.isYouGoing && !$0.isHostedByYou }
    }

    var hostedEvents: [SportsEvent] {
        events.filter(\.isHostedByYou).sorted { $0.start < $1.start }
    }

    var editingEvent: SportsEvent? { editingEventID.flatMap(event) }

    func event(_ id: SportsEvent.ID) -> SportsEvent? {
        events.first { $0.id == id }
    }

    private func matchesSearch(_ event: SportsEvent) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [event.title, event.sport.name, event.venue.name, event.host]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func matchesFilter(_ event: SportsEvent) -> Bool {
        sportFilter.isEmpty || sportFilter.contains(event.sport)
    }

    // MARK: Actions

    /// First come, first served: RSVP takes the spot immediately.
    /// TODO(post-MVP): organizer approval (Accept/Decline join requests) — see the
    /// "Hosted events" Figma frame. Deliberately left out of the MVP.
    func rsvp(_ id: SportsEvent.ID) {
        mutate(id) { event in
            guard !event.isFull, !event.isYouGoing else { return }
            event.attendees.append(Person.you)
        }
    }

    /// Giving up a spot. If the game was full, it reappears on the map and
    /// everyone who bookmarked it gets notified.
    func leave(_ id: SportsEvent.ID) {
        guard let before = event(id), before.isYouGoing, !before.isHostedByYou else { return }
        mutate(id) { $0.attendees.removeAll { $0 == Person.you } }
        if before.isFull {
            // TODO(backend): send a push to bookmarked users instead of a local banner.
            notice = "A spot opened in \(before.title). \(before.otherBookmarkCount) bookmarked players notified."
        }
    }

    func toggleBookmark(_ id: SportsEvent.ID) {
        mutate(id) { $0.isBookmarked.toggle() }
    }

    /// Demo helper: someone drops out of a full game you bookmarked.
    func simulateDropOut() {
        guard let index = events.firstIndex(where: { $0.isFull && !$0.hasEnded && !$0.isYouGoing }) else {
            notice = "No full games to open up right now."
            return
        }
        let event = events[index]
        if let dropper = event.guests.last {
            events[index].attendees.removeAll { $0 == dropper }
        }
        notice = event.isBookmarked
            ? "🔔 A spot just opened in \(event.title)!"
            : "A spot opened in \(event.title). It's back on the map."
    }

    func sendMessage(_ text: String, to id: SportsEvent.ID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(id) { $0.messages.append(ChatMessage(sender: Person.you, text: trimmed, sentAt: .now)) }
    }

    func markRead(_ id: SportsEvent.ID) {
        mutate(id) { $0.unreadCount = 0 }
    }

    func startAdding(editing id: SportsEvent.ID? = nil) {
        editingEventID = id
        isAddingEvent = true
    }

    func save(_ draft: SportsEvent) {
        if let index = events.firstIndex(where: { $0.id == draft.id }) {
            events[index] = draft
        } else {
            events.append(draft)
            lastCreatedID = draft.id
        }
    }

    private func mutate(_ id: SportsEvent.ID, _ change: (inout SportsEvent) -> Void) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        change(&events[index])
    }
}
