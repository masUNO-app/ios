import MapKit
import Observation
import SwiftUI

/// Presentation state and intents for the map: search, the Filter games sheet, pin
/// selection and camera position. Game data comes from `GameStore`.
@Observable
final class EventMapViewModel {
    /// Filter games › When.
    enum WhenFilter: CaseIterable, Identifiable {
        case anyTime, today, tomorrow

        var id: Self { self }

        var label: String {
            switch self {
            case .anyTime: String(localized: "Any day this week")
            case .today: String(localized: "Today, any time")
            case .tomorrow: String(localized: "Tomorrow, any time")
            }
        }
    }

    /// Filter games › How far, measured from you (or from campus when location is off).
    enum DistanceFilter: CaseIterable, Identifiable {
        case anywhere, walking, biking

        var id: Self { self }

        var label: String {
            switch self {
            case .anywhere: String(localized: "Any distance")
            case .walking: String(localized: "Walking distance · 20 min")
            case .biking: String(localized: "Biking distance · 20 min")
            }
        }

        /// About 20 minutes at a walk or on a bike.
        var meters: CLLocationDistance? {
            switch self {
            case .anywhere: nil
            case .walking: 1_600
            case .biking: 5_000
            }
        }
    }

    var searchText = ""
    /// Empty means "all sports".
    var sportFilter: Set<Activity> = []
    var whenFilter = WhenFilter.anyTime
    var distanceFilter = DistanceFilter.anywhere
    /// Only games starting in the next hour.
    var startingSoonOnly = false
    var selectedID: UUID?
    /// The game whose popup is on the map. Lags behind `selectedID` while the popup shrinks away.
    private(set) var popupID: UUID?
    /// Grows / shrinks the popup (animated inside its annotation).
    private(set) var isPopupShown = false
    /// Measured popup height, to sit it just above its pin.
    var popupHeight: CGFloat = 340
    /// Opens on your campus, and moves to you once a fix shows you're near it (SPEC §7.6.1).
    var position: MapCameraPosition = LocationService.mockCoordinate.map { .region(EventMapViewModel.region(around: $0)) }
        ?? .automatic
    /// Set from the signed-in profile (a demo campus for review accounts).
    private var campus: University?
    private var lastFix: CLLocationCoordinate2D?
    /// Location is off or not allowed: shows the "Turn on location" banner.
    private(set) var isLocationDenied = false
    /// Only the first fix moves the map; after that it's yours to pan.
    private var hasCentered = false

    // MARK: Queries

    /// Games you can actually join: not cancelled, ended or full (SPEC §7.6.1), that match the
    /// search and the filters.
    func mapEvents(in store: GameStore, now: Date = .now) -> [Game] {
        store.mapGames(now: now).filter { matchesSearch($0) && matchesFilter($0, now: now) }
    }

    /// Pins in drawing order: MapKit draws later annotations on top, so bumped games go last.
    func pinOrder(in store: GameStore, now: Date = .now) -> [Game] {
        let games = mapEvents(in: store, now: now)
        return games.filter { !$0.isBumped(now: now) } + games.filter { $0.isBumped(now: now) }
    }

    /// Pins closer than this on screen cover most of each other's head, so they share a pin.
    private static let overlap = CGSize(width: 40, height: 48)

    /// Pins as drawn: games close enough to cover each other at this zoom share one group pin.
    /// The selected game always keeps its own, for its popup.
    func pinGroups(in store: GameStore, now: Date = .now, mapSize: CGSize) -> [PinGroup] {
        let games = pinOrder(in: store, now: now)
        guard let span = settledSpan, mapSize.width > 0, mapSize.height > 0 else {
            return games.map { PinGroup(games: [$0]) }
        }
        let pointsPerLongitude = mapSize.width / span.longitudeDelta
        let pointsPerLatitude = mapSize.height / span.latitudeDelta

        var groups: [PinGroup] = []
        for game in games {
            let joins = game.id == selectedID ? nil : groups.firstIndex { group in
                let first = group.games[0]
                return first.id != selectedID
                    && abs(first.coordinate.longitude - game.coordinate.longitude) * pointsPerLongitude < Self.overlap.width
                    && abs(first.coordinate.latitude - game.coordinate.latitude) * pointsPerLatitude < Self.overlap.height
            }
            if let joins {
                groups[joins].games.append(game)
            } else {
                groups.append(PinGroup(games: [game]))
            }
        }
        return groups
    }

    /// The search list: games with a spot that just opened first, then the soonest.
    func searchResults(in store: GameStore, now: Date = .now) -> [Game] {
        mapEvents(in: store, now: now).sorted {
            ($0.isBumped(now: now) ? 0 : 1, $0.startsAt) < ($1.isBumped(now: now) ? 0 : 1, $1.startsAt)
        }
    }

    /// "Basketball near you" when every result is one sport; otherwise "Games near you".
    func resultsTitle(for results: [Game]) -> String {
        let sports = Set(results.map(\.activity))
        if sports.count == 1, let sport = sports.first { return String(localized: "\(sport.name) near you") }
        return String(localized: "Games near you")
    }

    /// "Today, 7:35 PM · 0.4 km · room for 4". The distance is left out when there's nowhere to measure from.
    func resultLine(for game: Game) -> String {
        var parts = [EventFormat.shortDayAndTime(game.startsAt)]
        if let origin = userCoordinate { parts.append(EventFormat.distance(from: origin, to: game.coordinate)) }
        parts.append(String(localized: "room for \(game.spotsLeft)"))
        return parts.joined(separator: " · ")
    }

    /// How many filters are on, for the badge on the Filter button.
    var activeFilterCount: Int {
        sportFilter.count + (whenFilter == .anyTime ? 0 : 1) + (distanceFilter == .anywhere ? 0 : 1) + (startingSoonOnly ? 1 : 0)
    }

    var filterLabel: String {
        activeFilterCount == 0 ? String(localized: "Filter") : String(localized: "Filter · \(activeFilterCount)")
    }

    /// Where you are, if the phone has said: the mocked spot in design review, otherwise the last fix.
    var userCoordinate: CLLocationCoordinate2D? {
        LocationService.mockCoordinate ?? lastFix
    }

    // MARK: Intents

    /// Bring a pin on screen and select it (e.g. a newly created game).
    func focus(on event: Game) {
        withAnimation {
            position = .region(MKCoordinateRegion(center: event.coordinate, span: University.mapSpan))
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

    /// The selected game left the map (cancelled, deleted, filled): its popup goes at once,
    /// without shrinking into a pin that's no longer there.
    func dropSelection() {
        popupID = nil
        isPopupShown = false
        selectedID = nil
    }

    /// Anchors the popup annotation so its tail ends just above the selected pin's head.
    /// Same coordinate as the pin, so MapKit moves them together.
    func popupAnchor(for event: Game) -> UnitPoint {
        UnitPoint(x: 0.5, y: 1 + (EventPin.selectedHeight + 6) / max(popupHeight, 1))
    }

    /// Last visible region, so selecting a pin can keep the current zoom.
    private var visibleRegion: MKCoordinateRegion?

    /// Pans so the selected pin sits low and centered, leaving room for its popup above.
    func reveal(_ event: Game) {
        let span = visibleRegion?.span ?? University.mapSpan
        let center = CLLocationCoordinate2D(
            latitude: event.coordinate.latitude + span.latitudeDelta * 0.13,
            longitude: event.coordinate.longitude
        )
        withAnimation(.smooth) { position = .region(MKCoordinateRegion(center: center, span: span)) }
    }

    /// The games behind the group pin you tapped, listed in a sheet.
    var groupedIDs: [UUID] = []

    /// Zoom the pins were last grouped at. Only updated once the camera stops, so pins don't
    /// merge and split while you pinch.
    private var settledSpan: MKCoordinateSpan?

    func cameraSettled(on region: MKCoordinateRegion) {
        settledSpan = region.span
    }

    /// Tracks the visible region and closes the popup once its pin leaves the screen.
    func cameraChanged(to region: MKCoordinateRegion, selected: Game?) {
        visibleRegion = region
        guard let selected, !region.contains(selected.coordinate) else { return }
        withAnimation(.snappy) { selectedID = nil }
    }

    /// The campus arrived (the profile can load after the map appears).
    func setCampus(_ campus: University?) {
        self.campus = campus
        centerIfNeeded()
    }

    /// Campus first, so the map is never blank; then you, once and only if you're near it.
    private func centerIfNeeded() {
        guard !hasCentered, selectedID == nil, LocationService.mockCoordinate == nil, let campus else { return }
        if let lastFix, campus.isNearby(lastFix) {
            withAnimation { position = .region(Self.region(around: lastFix)) }
        } else {
            position = .region(campus.region)
        }
        if lastFix != nil { hasCentered = true }
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
                lastFix = location.coordinate
                centerIfNeeded()
                return
            }
        } catch {
            // No fix: the map just stays where it is.
        }
    }

    /// Recenter on the mock location.
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
            position = .userLocation(fallback: campus.map { .region($0.region) } ?? .automatic)
        }
    }

    private static func region(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, span: University.mapSpan)
    }

    func toggleSport(_ sport: Activity) {
        if sportFilter.contains(sport) {
            sportFilter.remove(sport)
        } else {
            sportFilter.insert(sport)
        }
    }

    /// Filter games › Reset.
    func resetFilters() {
        sportFilter.removeAll()
        whenFilter = .anyTime
        distanceFilter = .anywhere
        startingSoonOnly = false
    }

    /// "Look farther away" on an empty map: drop the distance limit and zoom out.
    func lookFartherAway() {
        distanceFilter = .anywhere
        let region = visibleRegion ?? campus?.region
        guard let region else { return }
        let span = MKCoordinateSpan(
            latitudeDelta: min(region.span.latitudeDelta * 3, 1.5),
            longitudeDelta: min(region.span.longitudeDelta * 3, 1.5)
        )
        withAnimation(.smooth) { position = .region(MKCoordinateRegion(center: region.center, span: span)) }
    }

    #if DEBUG
    /// `-screen popup` opens the popup for "After-work hoops"; `popup-saved` for a bookmarked game.
    /// `groups` zooms out until pins merge; `groups-list` then opens the biggest group's list.
    func openDebugPopup(in store: GameStore) {
        if let screen = UserDefaults.standard.string(forKey: "screen"), screen.hasPrefix("groups") {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard let region = visibleRegion else { return }
                let span = MKCoordinateSpan(latitudeDelta: region.span.latitudeDelta * 4, longitudeDelta: region.span.longitudeDelta * 4)
                withAnimation { position = .region(MKCoordinateRegion(center: region.center, span: span)) }
                guard screen == "groups-list" else { return }
                try? await Task.sleep(for: .seconds(2))
                groupedIDs = mapEvents(in: store).prefix(3).map(\.id)
            }
            return
        }
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

    private func matchesFilter(_ event: Game, now: Date) -> Bool {
        guard sportFilter.isEmpty || sportFilter.contains(event.activity) else { return false }
        if startingSoonOnly, !event.isSoon(now: now) { return false }
        switch whenFilter {
        case .anyTime: break
        case .today: if !Calendar.current.isDate(event.startsAt, inSameDayAs: now) { return false }
        case .tomorrow:
            guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now),
                  Calendar.current.isDate(event.startsAt, inSameDayAs: tomorrow) else { return false }
        }
        if let limit = distanceFilter.meters, let origin = userCoordinate ?? campus?.center {
            let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            let there = CLLocation(latitude: event.place.latitude, longitude: event.place.longitude)
            if here.distance(from: there) > limit { return false }
        }
        return true
    }
}

/// One pin on the map: a game, or several that would cover each other.
struct PinGroup: Identifiable {
    var games: [Game]

    /// The first game's: a pin keeps its identity as others merge into it.
    var id: UUID { games[0].id }

    /// The middle of the games it stands for.
    var coordinate: CLLocationCoordinate2D {
        let count = Double(games.count)
        return CLLocationCoordinate2D(
            latitude: games.map(\.coordinate.latitude).reduce(0, +) / count,
            longitude: games.map(\.coordinate.longitude).reduce(0, +) / count
        )
    }
}

private extension MKCoordinateRegion {
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        abs(coordinate.latitude - center.latitude) <= span.latitudeDelta / 2
            && abs(coordinate.longitude - center.longitude) <= span.longitudeDelta / 2
    }
}
