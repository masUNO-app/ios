import MapKit
import Observation
import SwiftUI

/// Presentation state and intents for the event map: search, sport filter,
/// pin selection and camera position. Event data comes from `EventStore`.
@Observable
final class EventMapViewModel {
    var searchText = ""
    /// Empty means "all sports".
    var sportFilter: Set<Sport> = []
    var selectedID: SportsEvent.ID?
    var position: MapCameraPosition = .region(MockData.initialRegion)

    // MARK: Queries

    /// The map only shows sports games you can actually join: open spots, not over.
    func mapEvents(in store: EventStore) -> [SportsEvent] {
        store.events.filter { event in
            Sport.postable.contains(event.sport) && !event.isFull && !event.hasEnded
                && matchesSearch(event) && matchesFilter(event)
        }
    }

    func bookmarkedEvents(in store: EventStore) -> [SportsEvent] {
        store.bookmarkedEvents
    }

    var filterLabel: String {
        sportFilter.isEmpty ? "Filters" : "Filters · \(sportFilter.count)"
    }

    // MARK: Intents

    /// Bring a pin on screen and select it (bookmarks, newly created events).
    func focus(on event: SportsEvent) {
        withAnimation {
            position = .region(MKCoordinateRegion(center: event.coordinate, span: MockData.initialRegion.span))
        }
        selectedID = event.id
    }

    func toggleSport(_ sport: Sport) {
        if sportFilter.contains(sport) {
            sportFilter.remove(sport)
        } else {
            sportFilter.insert(sport)
        }
    }

    func clearSportFilter() {
        sportFilter.removeAll()
    }

    func rsvp(_ id: SportsEvent.ID, in store: EventStore) {
        withAnimation { store.rsvp(id) }
    }

    func toggleBookmark(_ id: SportsEvent.ID, in store: EventStore) {
        store.toggleBookmark(id)
    }

    func simulateDropOut(in store: EventStore) {
        withAnimation { store.simulateDropOut() }
    }

    #if DEBUG
    /// `-screen popup` opens the popup for the 760 Market Street mock game.
    func openDebugPopup(in store: EventStore) {
        guard UserDefaults.standard.string(forKey: "screen") == "popup" else { return }
        selectedID = mapEvents(in: store).first { $0.venue == MockData.Venues.market760 }?.id
    }
    #endif

    // MARK: Filtering

    private func matchesSearch(_ event: SportsEvent) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [event.title, event.sport.name, event.venue.name, event.host]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func matchesFilter(_ event: SportsEvent) -> Bool {
        sportFilter.isEmpty || sportFilter.contains(event.sport)
    }
}
