import Foundation
import Observation

/// In-memory source of truth. No backend yet — everything resets on launch.
/// Swapped for Emilio's `GameStore` once the live repositories land (B6, B7).
///
/// Model layer of the MVVM stack: holds the games and every domain action
/// that mutates them. Screen/presentation state lives in `ViewModels/`.
@Observable
final class EventStore {
    var events: [SportsEvent]
    var profile: Profile

    /// Short toast text (failed actions, confirmations).
    var notice: String?

    /// Set after creating a game so the map can jump to it.
    var lastCreatedID: SportsEvent.ID?

    init(events: [SportsEvent] = MockData.events(), profile: Profile = MockData.profile) {
        self.events = events
        self.profile = profile
    }

    // MARK: Queries

    func event(_ id: SportsEvent.ID) -> SportsEvent? {
        events.first { $0.id == id }
    }

    /// Games you joined as a guest.
    var goingEvents: [SportsEvent] {
        events.filter { $0.isYouGoing && !$0.isHostedByYou }.sorted { $0.start < $1.start }
    }

    var hostedEvents: [SportsEvent] {
        events.filter { $0.isHostedByYou && !$0.isCancelled }.sorted { $0.start < $1.start }
    }

    // MARK: Actions

    /// First come, first served: joining takes the spot immediately.
    func join(_ id: SportsEvent.ID) {
        mutate(id) { event in
            guard !event.isFull, !event.isYouGoing, !event.isCancelled else { return }
            event.attendees.append(Person.you)
        }
    }

    /// Why a join the phone already showed was undone (server errors from `join_game`).
    enum JoinFailure {
        case full, blocked

        var message: String {
            switch self {
            case .full: String(localized: "Someone just took the last spot.")
            case .blocked: String(localized: "Someone you blocked is going.")
            }
        }
    }

    /// Undoes an optimistic join and says why.
    func rollBackJoin(_ id: SportsEvent.ID, reason: JoinFailure) {
        mutate(id) { $0.attendees.removeAll { $0 == Person.you } }
        notice = reason.message
    }

    func leave(_ id: SportsEvent.ID) {
        guard let event = event(id), event.isYouGoing, !event.isHostedByYou else { return }
        mutate(id) { $0.attendees.removeAll { $0 == Person.you } }
    }

    /// Soft cancel: the game stays visible to people going, marked cancelled.
    func cancel(_ id: SportsEvent.ID) {
        mutate(id) { $0.isCancelled = true }
        notice = String(localized: "Game cancelled. We let everyone going know.")
    }

    func sendMessage(_ text: String, to id: SportsEvent.ID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(id) { $0.messages.append(ChatMessage(sender: Person.you, text: trimmed, sentAt: .now)) }
    }

    func markRead(_ id: SportsEvent.ID) {
        mutate(id) { $0.unreadCount = 0 }
    }

    func save(_ draft: SportsEvent) {
        if let index = events.firstIndex(where: { $0.id == draft.id }) {
            events[index] = draft
        } else {
            events.append(draft)
            lastCreatedID = draft.id
        }
    }

    func mutate(_ id: SportsEvent.ID, _ change: (inout SportsEvent) -> Void) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        change(&events[index])
    }
}
