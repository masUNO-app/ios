import Observation
import SwiftUI

/// Presentation state and intents for an event's group chat.
@Observable
final class GroupChatViewModel {
    var draft = ""

    private let eventID: SportsEvent.ID

    init(eventID: SportsEvent.ID) {
        self.eventID = eventID
    }

    func event(in store: EventStore) -> SportsEvent? {
        store.event(eventID)
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send(in store: EventStore) {
        store.sendMessage(draft, to: eventID)
        draft = ""
    }

    func markRead(in store: EventStore) {
        store.markRead(eventID)
    }
}
