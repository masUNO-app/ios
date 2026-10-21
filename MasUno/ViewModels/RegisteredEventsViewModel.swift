import SwiftUI

/// Presentation logic for "Your plans" (Figma: "Registered events"). Stateless —
/// all data is derived from `EventStore`.
struct RegisteredEventsViewModel {
    func events(in store: EventStore) -> [SportsEvent] {
        store.registeredEvents
    }

    func upcoming(in store: EventStore) -> [SportsEvent] {
        events(in: store).filter { !$0.hasEnded }.sorted { $0.start < $1.start }
    }

    func past(in store: EventStore) -> [SportsEvent] {
        events(in: store).filter(\.hasEnded).sorted { $0.start > $1.start }
    }

    func countLabel(in store: EventStore) -> String {
        let count = events(in: store).count
        return "\(count) registered event\(count == 1 ? "" : "s")"
    }

    func leave(_ id: SportsEvent.ID, in store: EventStore) {
        withAnimation { store.leave(id) }
    }
}
