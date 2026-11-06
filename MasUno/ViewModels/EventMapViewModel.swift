import MapKit
import Observation
import SwiftUI

/// Presentation state and intents for the map: search, sport filter, pin
/// selection and camera position. Game data comes from `GameStore`.
@Observable
final class EventMapViewModel {
    var searchText = ""
    /// Empty means "all sports".
    var sportFilter: Set<Activity> = []
    var selectedID: UUID?
    /// The game whose popup is on the map. Lags behind `selectedID` while the popup shrinks away.
    private(set) var popupID: UUID?
    /// Grows / shrinks the popup (animated inside its annotation).
    private(set) var isPopupShown = false
    /// Measured popup height, to sit it just above its pin.
    var popupHeight: CGFloat = 260
    /// Starts on campus, and moves to you once a fix shows you're near it (SPEC §7.6.1).
    var position: MapCameraPosition = LocationService.mockCoordinate.map { .region(EventMapViewModel.region(around: $0)) }
        ?? .region(Campus.region)
    /// Location is off or not allowed: shows the "Turn on location" banner.
    private(set) var isLocationDenied = false
    /// Only the first fix moves the map; after that it's yours to pan.
    private var hasCentered = false

    // MARK: Queries

    /// Games you can actually join: not cancelled, ended or full (SPEC §7.6.1).
    func mapEvents(in store: GameStore) -> [Game] {
        store.mapGames().filter { matchesSearch($0) && matchesFilter($0) }
    }

    /// Pins in drawing order: MapKit draws later annotations on top, so bumped games go last.
    func pinOrder(in store: GameStore, now: Date = .now) -> [Game] {
        let games = mapEvents(in: store)
        return games.filter { !$0.isBumped(now: now) } + games.filter { $0.isBumped(now: now) }
    }

    var filterLabel: String {
        sportFilter.isEmpty ? String(localized: "Filter") : String(localized: "Filter · \(sportFilter.count)")
    }

    // MARK: Intents

    /// Bring a pin on screen and select it (e.g. a newly created game).
    func focus(on event: Game) {
        withAnimation {
            position = .region(MKCoordinateRegion(center: event.coordinate, span: Campus.region.span))
        }
        selectedID = event.id
    }

    /// Opens or closes the popup to match the selected pin: it grows out of the pin, and
    /// shrinks back into it before it's removed.
    func selectionChanged(to id: UUID?) {
        if let id {
            popupID = id
            isPopupShown = false
            Task {
                // Let the annotation appear at its "closed" size first, then animate open.
                try? await Task.sleep(for: .milliseconds(30))
                if selectedID == id { isPopupShown = true }
            }
        } else {
            isPopupShown = false
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                if selectedID == nil { popupID = nil }
            }
        }
    }

    /// Anchors the popup annotation so its bottom sits 10 pt above the selected pin
    /// (and its "Soon" label). Same coordinate as the pin, so MapKit moves them together.
    func popupAnchor(for event: Game) -> UnitPoint {
        let pinHeight: CGFloat = (event.isSoon() || event.isBumped() ? 88 : 56) * 1.15
        return UnitPoint(x: 0.5, y: 1 + (pinHeight + 10) / max(popupHeight, 1))
    }

    /// Last visible region, so selecting a pin can keep the current zoom.
    private var visibleRegion: MKCoordinateRegion?

    /// Pans so the selected pin sits low and centered, leaving room for its popup above.
    func reveal(_ event: Game) {
        let span = visibleRegion?.span ?? Campus.region.span
        let center = CLLocationCoordinate2D(
            latitude: event.coordinate.latitude + span.latitudeDelta * 0.22,
            longitude: event.coordinate.longitude
        )
        withAnimation(.smooth) { position = .region(MKCoordinateRegion(center: center, span: span)) }
    }

    /// Tracks the visible region and closes the popup once its pin leaves the screen.
    func cameraChanged(to region: MKCoordinateRegion, selected: Game?) {
        visibleRegion = region
        guard let selected, !region.contains(selected.coordinate) else { return }
        withAnimation(.snappy) { selectedID = nil }
    }

    /// Asks for location the first time the map opens, then centers on you if you're near campus.
    /// Runs again each time the app comes back, in case location was turned on in Settings.
    func locate() async {
        guard LocationService.mockCoordinate == nil else { return }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if Task.isCancelled { return }
                if update.authorizationDenied || update.authorizationDeniedGlobally {
                    isLocationDenied = true
                    return
                }
                guard let location = update.location else { continue }
                isLocationDenied = false
                if !hasCentered, selectedID == nil, Campus.isNearby(location.coordinate) {
                    withAnimation { position = .region(Self.region(around: location.coordinate)) }
                }
                hasCentered = true
                return
            }
        } catch {
            // No fix: the map just stays where it is.
        }
    }

    /// Recenter on the mock location. The real location uses the native `MapUserLocationButton`.
    func centerOnMockLocation() {
        guard let mock = LocationService.mockCoordinate else { return }
        withAnimation {
            selectedID = nil
            position = .region(Self.region(around: mock))
        }
    }

    /// Recenters on the user: the mocked location if there is one, otherwise real GPS, falling back to campus.
    func centerOnUserLocation() {
        guard LocationService.mockCoordinate == nil else { return centerOnMockLocation() }
        withAnimation {
            selectedID = nil
            position = .userLocation(fallback: .region(Campus.region))
        }
    }

    private static func region(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, span: Campus.region.span)
    }

    func toggleSport(_ sport: Activity) {
        if sportFilter.contains(sport) {
            sportFilter.remove(sport)
        } else {
            sportFilter.insert(sport)
        }
    }

    func clearSportFilter() {
        sportFilter.removeAll()
    }

    func join(_ id: UUID, in store: GameStore) {
        Task { await store.join(id) }
    }

    #if DEBUG
    /// `-screen popup` opens the popup for "After-work hoops"; `popup-saved` for a bookmarked game.
    func openDebugPopup() {
        let id: UUID? = switch UserDefaults.standard.string(forKey: "screen") {
        case "popup": MockFixtures.GameID.open
        case "popup-saved": MockFixtures.GameID.lastSpot
        default: nil
        }
        guard let id else { return }
        // After the map has settled, so the open animation is visible in design review.
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            selectedID = id
            // `-popupCycle YES`: close it again, to review the close animation.
            if UserDefaults.standard.bool(forKey: "popupCycle") {
                try? await Task.sleep(for: .seconds(2))
                selectedID = nil
            }
            // `-popupPan YES`: pan the pin off screen, to review following and auto-close.
            if UserDefaults.standard.bool(forKey: "popupPan"), let region = visibleRegion {
                try? await Task.sleep(for: .seconds(1.5))
                var moved = region
                moved.center.longitude -= region.span.longitudeDelta * 0.9
                withAnimation(.linear(duration: 2.5)) { position = .region(moved) }
            }
        }
    }
    #endif

    // MARK: Filtering

    /// Title, sport, place or host first name.
    private func matchesSearch(_ event: Game) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [event.title, event.activity.name, event.place.name, event.host.firstName]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func matchesFilter(_ event: Game) -> Bool {
        sportFilter.isEmpty || sportFilter.contains(event.activity)
    }
}

private extension MKCoordinateRegion {
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        abs(coordinate.latitude - center.latitude) <= span.latitudeDelta / 2
            && abs(coordinate.longitude - center.longitude) <= span.longitudeDelta / 2
    }
}
