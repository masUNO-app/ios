import MapKit
import Observation
import SwiftUI

/// Game detail (SPEC §7.6.4): which 1.0 state you're in, and the join/leave/cancel intents.
@Observable
final class EventDetailViewModel {
    enum State: Equatable {
        case open, going, full, hosting, ended, cancelled
    }

    let eventID: SportsEvent.ID
    var confirmsLeave = false
    var confirmsCancel = false
    var showsWhoIsGoing = false
    var reportTarget: ReportTarget?

    init(eventID: SportsEvent.ID) {
        self.eventID = eventID
    }

    func event(in store: EventStore) -> SportsEvent? {
        store.event(eventID)
    }

    func state(of event: SportsEvent) -> State {
        if event.isCancelled { return .cancelled }
        if event.hasEnded { return .ended }
        if event.isHostedByYou { return .hosting }
        if event.isYouGoing { return .going }
        if event.isFull { return .full }
        return .open
    }

    // MARK: Presentation

    func chipText(for event: SportsEvent) -> String {
        switch state(of: event) {
        case .open: event.openLine
        case .going: String(localized: "You're in · \(event.statusLine)")
        case .full: String(localized: "Full")
        case .hosting: String(localized: "You're hosting · \(event.attendees.count) going")
        case .ended: String(localized: "This game has ended")
        case .cancelled: String(localized: "\(Person.display(event.host)) cancelled this game")
        }
    }

    func chipIcon(for event: SportsEvent) -> String? {
        state(of: event) == .going ? "checkmark.circle.fill" : nil
    }

    /// "Alex R. (host), Ricardo T., you" — without anyone you blocked.
    func goingNames(for event: SportsEvent, in store: EventStore) -> String {
        store.visibleAttendees(of: event).map { name in
            if name == Person.you {
                return name == event.host ? String(localized: "you (host)") : String(localized: "you")
            }
            let display = Person.display(name)
            return name == event.host ? String(localized: "\(display) (host)") : display
        }
        .joined(separator: ", ")
    }

    // MARK: Intents

    /// Shows "You're in" right away; rolls back if the server says the game filled.
    func join(in store: EventStore) {
        withAnimation { store.join(eventID) }
        #if DEBUG
        // `-raceJoin YES`: pretend someone else took the last spot first.
        if UserDefaults.standard.bool(forKey: "raceJoin") {
            Task {
                try? await Task.sleep(for: .seconds(1))
                withAnimation {
                    store.rollBackJoin(eventID, reason: .full)
                    // The other player's join, as the next refresh would show it.
                    store.mutate(eventID) { event in
                        while event.spotsLeft > 0 { event.attendees.append("Player \(event.attendees.count + 1)") }
                    }
                }
            }
        }
        #endif
    }

    func leave(in store: EventStore) {
        withAnimation { store.leave(eventID) }
    }

    func cancel(in store: EventStore) {
        withAnimation { store.cancel(eventID) }
    }

    /// Apple Maps with walking directions (Google Maps is 2.0, E19).
    func openInMaps(_ event: SportsEvent) {
        let location = CLLocation(latitude: event.venue.latitude, longitude: event.venue.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = event.venue.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
