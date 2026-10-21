import Foundation

/// Presentation logic for "You're the host" (Figma: "Hosted events"). Stateless —
/// all data is derived from `EventStore`.
struct HostedEventsViewModel {
    func events(in store: EventStore) -> [SportsEvent] {
        store.hostedEvents
    }

    func upcoming(in store: EventStore) -> [SportsEvent] {
        events(in: store).filter { !$0.hasEnded }
    }

    func countLabel(in store: EventStore) -> String {
        let count = events(in: store).count
        return "\(count) hosted event\(count == 1 ? "" : "s")"
    }
}
