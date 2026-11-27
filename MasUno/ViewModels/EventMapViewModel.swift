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
            case .anyTime: String.app("Any day this week")
            case .today: String.app("Today, any time")
            case .tomorrow: String.app("Tomorrow, any time")
            }
        }
    }

    /// Filter games › How far, measured from you (or from campus when location is off).
    enum DistanceFilter: CaseIterable, Identifiable {
        case anywhere, walking, biking

        var id: Self { self }

        var label: String {
            switch self {
            case .anywhere: String.app("Any distance")
            case .walking: String.app("Walking distance · 20 min")
            case .biking: String.app("Biking distance · 20 min")
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

    /// Everything the map draws for one render, computed once.
    struct MapFrame {
        /// Joinable games, before search and filters.
        let open: [Game]
        /// After search and filters: the pins, the chip and the search list.
        let filtered: [Game]
        /// Pins as drawn, in drawing order.
        let groups: [PinGroup]
        /// Single pins whose faces to load, selection first.
        let attendeeDemand: [Game]
    }

    /// One pass over the store for a whole render of the map, rather than one per use. Not kept
    /// between renders, so it can't outlive its inputs.
    func frame(in store: GameStore, now: Date, mapSize: CGSize) -> MapFrame {
        let open = store.mapGames(now: now)
        let filtered = filter(open, now: now)
        let groups = group(order(filtered, now: now), mapSize: mapSize)
        return MapFrame(open: open, filtered: filtered, groups: groups, attendeeDemand: attendeePreview(from: groups))
    }

    /// Games you can actually join: not cancelled, ended or full (SPEC §7.6.1), that match the
    /// search and the filters.
    func mapEvents(in store: GameStore, now: Date = .now) -> [Game] {
        filter(store.mapGames(now: now), now: now)
    }

    /// Pins in drawing order: MapKit draws later annotations on top, so bumped games go last.
    func pinOrder(in store: GameStore, now: Date = .now) -> [Game] {
        order(mapEvents(in: store, now: now), now: now)
    }

    /// Pins as drawn: games close enough to cover each other at this zoom share one group pin.
    /// The selected game always keeps its own, for its popup.
    func pinGroups(in store: GameStore, now: Date = .now, mapSize: CGSize) -> [PinGroup] {
        group(pinOrder(in: store, now: now), mapSize: mapSize)
    }

    /// Face previews are only used by single pins. The settled region avoids starting/cancelling
    /// requests on every camera frame; selection is always first even during a programmatic pan.
    func attendeePreviewGames(in store: GameStore, now: Date = .now, mapSize: CGSize) -> [Game] {
        attendeePreview(from: pinGroups(in: store, now: now, mapSize: mapSize))
    }

    /// The search list: games with a spot that just opened first, then the soonest.
    func searchResults(in store: GameStore, now: Date = .now) -> [Game] {
        searchResults(from: mapEvents(in: store, now: now), now: now)
    }

    /// `games` in search-list order. Each game's key is worked out once rather than in every
    /// comparison, and positions are sorted rather than games, which are large to move. `sorted`
    /// is stable, so ties keep their order.
    func searchResults(from games: [Game], now: Date) -> [Game] {
        let keys = games.map { ($0.isBumped(now: now) ? 0 : 1, $0.startsAt) }
        return games.indices.sorted { keys[$0] < keys[$1] }.map { games[$0] }
    }

    /// Bumped games last, otherwise in the order given.
    private func order(_ games: [Game], now: Date) -> [Game] {
        var calm: [Game] = [], bumped: [Game] = []
        for game in games {
            if game.isBumped(now: now) { bumped.append(game) } else { calm.append(game) }
        }
        return calm + bumped
    }

    /// Pins closer than this on screen cover most of each other's head, so they share a pin.
    private static let overlap = CGSize(width: 40, height: 48)

    /// Groups pins already in drawing order.
    private func group(_ games: [Game], mapSize: CGSize) -> [PinGroup] {
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

    private func attendeePreview(from groups: [PinGroup]) -> [Game] {
        let singles = groups
            .filter { $0.games.count == 1 }
            .compactMap { $0.games.first }
        let selected = singles.first { $0.id == selectedID }
        let visible = singles.filter { game in
            game.id != selectedID && (settledRegion?.contains(game.coordinate) ?? false)
        }
        return selected.map { [$0] + visible } ?? visible
    }

    /// "Basketball near you" when every result is one sport; otherwise "Plans near you".
    func resultsTitle(for results: [Game]) -> String {
        let sports = Set(results.map(\.activity))
        if sports.count == 1, let sport = sports.first { return String.app("\(sport.name) near you") }
        return String.app("Plans near you")
    }

    /// What VoiceOver says when the results change: "Basketball near you, 3 games", or
    /// "No plans match that search".
    func resultsAnnouncement(for results: [Game]) -> String {
        guard !results.isEmpty else { return String.app("No plans match that search") }
        return resultsTitle(for: results) + ", " + String.app("\(results.count) plans")
    }

    /// "Today, 7:35 PM · 0.4 km · room for 4". The distance is left out when there's nowhere to measure from.
    func resultLine(for game: Game) -> String {
        var parts = [EventFormat.shortDayAndTime(game.startsAt)]
        if let origin = userCoordinate { parts.append(EventFormat.distance(from: origin, to: game.coordinate)) }
        parts.append(String.app("room for \(game.spotsLeft)"))
        return parts.joined(separator: " · ")
    }

    /// How many filters are on, for the badge on the Filter button.
    var activeFilterCount: Int {
        sportFilter.count + (whenFilter == .anyTime ? 0 : 1) + (distanceFilter == .anywhere ? 0 : 1) + (startingSoonOnly ? 1 : 0)
    }

    var filterLabel: String {
        activeFilterCount == 0 ? String.app("Filter") : String.app("Filter · \(activeFilterCount)")
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
        UnitPoint(x: 0.5, y: 1 + Self.popupLift / max(popupHeight, 1))
    }

    /// From the popup's bottom edge down to its pin's coordinate.
    private static var popupLift: CGFloat { PlanPopupCard<EmptyView, EmptyView>.lift }

    /// Last visible region, so selecting a pin can keep the current zoom.
    private var visibleRegion: MKCoordinateRegion?

    /// Pans so the selected pin sits low and centered, leaving room for its popup above. Then,
    /// if that would leave part of the popup outside `area` (in the map's points: the safe area,
    /// and one side of the fold on a partially open iPhone Duo), pans a little more to bring it in.
    func reveal(_ event: Game, mapSize: CGSize = .zero, area: CGRect = .null, popupWidth: CGFloat = 0) {
        let span = visibleRegion?.span ?? University.mapSpan
        var center = CLLocationCoordinate2D(
            latitude: event.coordinate.latitude + span.latitudeDelta * 0.13,
            longitude: event.coordinate.longitude
        )
        if mapSize.width > 0, mapSize.height > 0, !area.isEmpty {
            // Where that puts the pin: across the middle, 13% of the map below it.
            let pin = CGPoint(x: mapSize.width / 2, y: mapSize.height * 0.63)
            let shift = Self.popupShift(pin: pin, popup: CGSize(width: popupWidth, height: popupHeight), within: area)
            // Moving the pin right or down on screen moves the map's center west or north.
            center.longitude -= shift.dx * span.longitudeDelta / mapSize.width
            center.latitude += shift.dy * span.latitudeDelta / mapSize.height
        }
        withAnimation(.cameraMove) { position = .region(MKCoordinateRegion(center: center, span: span)) }
    }

    /// How far to move a pin at `pin` so its popup, centered above it, lands inside `area`:
    /// 16 pt in from the sides (as on a phone) and 8 pt below the top. Zero when it's already in.
    /// A popup wider than the area goes in its middle; one too tall keeps its top in view.
    static func popupShift(pin: CGPoint, popup: CGSize, within area: CGRect) -> CGVector {
        let lowest = area.minX + 16 + popup.width / 2
        let highest = area.maxX - 16 - popup.width / 2
        let x = lowest <= highest ? min(max(pin.x, lowest), highest) : area.midX
        let top = pin.y - popupLift - popup.height
        return CGVector(dx: x - pin.x, dy: max(0, area.minY + 8 - top))
    }

    /// The games behind the group pin you tapped, listed in a sheet.
    var groupedIDs: [UUID] = []

    /// Zoom the pins were last grouped at. Only updated once the camera stops, so pins don't
    /// merge and split while you pinch.
    private var settledSpan: MKCoordinateSpan?
    private var settledRegion: MKCoordinateRegion?

    func cameraSettled(on region: MKCoordinateRegion) {
        settledSpan = region.span
        settledRegion = region
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
            let location = try await LocationService.currentLocation()
            try Task.checkCancellation()
            isLocationDenied = false
            lastFix = location.coordinate
            centerIfNeeded()
        } catch LocationService.Failure.denied {
            isLocationDenied = true
        } catch {
            // No timely fix: the map stays on campus and remains usable.
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
        sportFilter.toggle(sport)
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
        withAnimation(.cameraMove) { position = .region(MKCoordinateRegion(center: region.center, span: span)) }
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
        case "popup", "guest-popup": MockFixtures.GameID.open
        case "popup-saved": MockFixtures.GameID.lastSpot
        // Auto-repost: the game a player just left, back at the top with "A spot just opened".
        case "popup-bumped": MockFixtures.GameID.bumped
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

    /// Search and filters. What doesn't change from game to game (the trimmed query, tomorrow,
    /// where distance is measured from) is worked out once per pass.
    func filter(_ games: [Game], now: Date) -> [Game] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let calendar = Calendar.current
        // Nil means no game is tomorrow, as when the date can't be worked out.
        let tomorrow = whenFilter == .tomorrow ? calendar.date(byAdding: .day, value: 1, to: now) : nil
        let limit = distanceFilter.meters
        // No origin means distance can't be measured, so it doesn't filter.
        let origin = limit == nil ? nil : (userCoordinate ?? campus?.center).map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        return games.filter { event in
            (query.isEmpty || matchesSearch(event, query: query))
                && matchesFilter(event, now: now, calendar: calendar, tomorrow: tomorrow, limit: limit, origin: origin)
        }
    }

    /// Title, sport, place or host first name.
    private func matchesSearch(_ event: Game, query: String) -> Bool {
        [event.title, event.activity.name, event.place.name, event.host.firstName]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func matchesFilter(
        _ event: Game, now: Date, calendar: Calendar, tomorrow: Date?, limit: CLLocationDistance?, origin: CLLocation?
    ) -> Bool {
        guard sportFilter.isEmpty || sportFilter.contains(event.activity) else { return false }
        if startingSoonOnly, !event.isSoon(now: now) { return false }
        switch whenFilter {
        case .anyTime: break
        case .today: if !calendar.isDate(event.startsAt, inSameDayAs: now) { return false }
        case .tomorrow:
            guard let tomorrow, calendar.isDate(event.startsAt, inSameDayAs: tomorrow) else { return false }
        }
        if let limit, let origin {
            let there = CLLocation(latitude: event.place.latitude, longitude: event.place.longitude)
            if origin.distance(from: there) > limit { return false }
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
