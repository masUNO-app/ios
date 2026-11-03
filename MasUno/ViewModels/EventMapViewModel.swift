import MapKit
import Observation
import SwiftUI

/// Presentation state and intents for the map: search, sport filter, pin
/// selection and camera position. Game data comes from `EventStore`.
@Observable
final class EventMapViewModel {
    var searchText = ""
    /// Empty means "all sports".
    var sportFilter: Set<Sport> = []
    var selectedID: SportsEvent.ID?
    /// Starts on you; campus if location is off or not allowed.
    var position: MapCameraPosition = .userLocation(fallback: .region(MockData.campusRegion))

    // MARK: Queries

    /// Games you can actually join: not cancelled, ended or full (SPEC §7.6.1).
    func mapEvents(in store: EventStore) -> [SportsEvent] {
        store.events.filter { event in
            !event.isCancelled && !event.isFull && !event.hasEnded
                && matchesSearch(event) && matchesFilter(event)
        }
    }

    var filterLabel: String {
        sportFilter.isEmpty ? String(localized: "Filter") : String(localized: "Filter · \(sportFilter.count)")
    }

    // MARK: Intents

    /// Bring a pin on screen and select it (e.g. a newly created game).
    func focus(on event: SportsEvent) {
        withAnimation {
            position = .region(MKCoordinateRegion(center: event.coordinate, span: MockData.campusRegion.span))
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

    func join(_ id: SportsEvent.ID, in store: EventStore) {
        withAnimation { store.join(id) }
    }

    #if DEBUG
    /// `-screen popup` opens the popup for the "After-work hoops" mock game.
    func openDebugPopup(in store: EventStore) {
        guard UserDefaults.standard.string(forKey: "screen") == "popup" else { return }
        selectedID = mapEvents(in: store).first { $0.title == "After-work hoops" }?.id
    }
    #endif

    // MARK: Filtering

    /// Title, sport, place or host first name.
    private func matchesSearch(_ event: SportsEvent) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [event.title, event.sport.name, event.venue.name, Person.firstName(event.host)]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func matchesFilter(_ event: SportsEvent) -> Bool {
        sportFilter.isEmpty || sportFilter.contains(event.sport)
    }
}
