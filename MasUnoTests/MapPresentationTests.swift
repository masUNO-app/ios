import Foundation
import MapKit
import Testing
@testable import masUNO

@MainActor
struct MapPresentationTests {
    private func store() async -> GameStore {
        let backend = MockBackend()
        let store = GameStore(
            games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend,
            defaults: UserDefaults(suiteName: "MapPresentationTests.\(UUID().uuidString)")!
        )
        await store.load()
        return store
    }

    @Test func pinsAndSearchUseTheSameExpirySnapshot() async throws {
        let store = await store()
        let game = try #require(store.game(MockFixtures.GameID.open))
        let vm = EventMapViewModel()
        let before = game.endsAt.addingTimeInterval(-1)
        let after = game.endsAt.addingTimeInterval(1)
        #expect(vm.mapEvents(in: store, now: before).contains { $0.id == game.id })
        #expect(vm.searchResults(in: store, now: before).contains { $0.id == game.id })
        #expect(!vm.mapEvents(in: store, now: after).contains { $0.id == game.id })
        #expect(!vm.searchResults(in: store, now: after).contains { $0.id == game.id })
    }

    @Test func offscreenGamesDoNotRequestFacePreviewsButSelectionIsPrioritized() async throws {
        let store = await store()
        let game = try #require(store.game(MockFixtures.GameID.open))
        let vm = EventMapViewModel()
        let now = game.startsAt.addingTimeInterval(-1)
        let size = CGSize(width: 400, height: 800)
        vm.cameraSettled(on: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)
        ))
        #expect(vm.attendeePreviewGames(in: store, now: now, mapSize: size).isEmpty)
        vm.selectedID = game.id
        #expect(vm.attendeePreviewGames(in: store, now: now, mapSize: size).map(\.id) == [game.id])
    }

    @Test func filteredGamesDoNotEnrichPinsEvenIfPreviouslySelected() async throws {
        let store = await store()
        let game = try #require(store.game(MockFixtures.GameID.open))
        let vm = EventMapViewModel()
        vm.selectedID = game.id
        vm.sportFilter = [MockFixtures.activity(game.activity.slug == "tennis" ? "soccer" : "tennis")]
        let demand = vm.attendeePreviewGames(in: store, now: game.startsAt.addingTimeInterval(-1), mapSize: CGSize(width: 400, height: 800))
        #expect(!demand.contains { $0.id == game.id })
    }

    // MARK: One pass per render (OPT-03, OPT-04)

    /// A game away from the fixtures, for the filter cases.
    private func game(
        _ title: String, _ sport: String = "basketball", host: PersonSummary, startsAt: Date,
        latitude: Double = MockFixtures.tec.centerLatitude, longitude: Double = MockFixtures.tec.centerLongitude,
        repostedAt: Date? = nil
    ) -> Game {
        Game(id: UUID(), host: host, activity: MockFixtures.activity(sport), title: title,
             startsAt: startsAt, durationMinutes: 60, endsAt: startsAt.addingTimeInterval(3600),
             capacity: 6, goingCount: 2, place: Place(name: "Court", address: "", latitude: latitude, longitude: longitude),
             autoRepost: true, repostedAt: repostedAt, createdAt: startsAt.addingTimeInterval(-86_400), hasBlockedAttendee: false)
    }

    /// The fixtures plus `count` games in a spiral out to about 5.5 km from campus: four sports,
    /// starts spread over two days with many ties, every fifth one bumped.
    private func crowdedStore(count: Int = 150) async throws -> (store: GameStore, now: Date) {
        let backend = MockBackend()
        let games = ControlledGames(backend)
        let store = GameStore(games: games, profiles: backend, safety: backend, chat: backend, catalog: backend,
                              defaults: UserDefaults(suiteName: "MapPresentationTests.\(UUID().uuidString)")!)
        await store.load()
        let now = backend.now
        let sports = ["basketball", "tennis", "soccer", "volleyball"]
        let extra = (0..<count).map { index in
            let radius = 0.05 * (Double(index + 1) / Double(count)).squareRoot()
            let angle = Double(index) * 2.39996
            return game(
                "Crowd \(index)", sports[index % sports.count], host: backend.me,
                startsAt: now.addingTimeInterval(Double(index % 16) * 3 * 3600 + 600),
                latitude: MockFixtures.tec.centerLatitude + radius * sin(angle),
                longitude: MockFixtures.tec.centerLongitude + radius * cos(angle),
                repostedAt: index % 5 == 0 ? now.addingTimeInterval(-600) : nil
            )
        }
        let fixtures = try await backend.fetchMapGames()
        games.mapRead = { fixtures + extra }
        await store.refreshMap()
        return (store, now)
    }

    /// The map's search and filters before OPT-04, run per game, to check the faster pass against.
    private func legacyMapEvents(_ vm: EventMapViewModel, in store: GameStore, now: Date) -> [Game] {
        store.mapGames(now: now).filter { event in
            let query = vm.searchText.trimmingCharacters(in: .whitespaces)
            if !query.isEmpty, ![event.title, event.activity.name, event.place.name, event.host.firstName]
                .contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return false }
            guard vm.sportFilter.isEmpty || vm.sportFilter.contains(event.activity) else { return false }
            if vm.startingSoonOnly, !event.isSoon(now: now) { return false }
            switch vm.whenFilter {
            case .anyTime: break
            case .today: if !Calendar.current.isDate(event.startsAt, inSameDayAs: now) { return false }
            case .tomorrow:
                guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now),
                      Calendar.current.isDate(event.startsAt, inSameDayAs: tomorrow) else { return false }
            }
            let origin = vm.userCoordinate ?? MockFixtures.tec.center
            if let limit = vm.distanceFilter.meters {
                let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
                let there = CLLocation(latitude: event.place.latitude, longitude: event.place.longitude)
                if here.distance(from: there) > limit { return false }
            }
            return true
        }
    }

    enum Setup: String, CaseIterable {
        case plain, grouped, selected, filtered, searching, tomorrow, soon
    }

    @Test(arguments: Setup.allCases) func frameMatchesTheSeparateQueries(setup: Setup) async throws {
        let (store, now) = try await crowdedStore()
        let vm = EventMapViewModel()
        vm.setCampus(MockFixtures.tec)
        let size = CGSize(width: 402, height: 874)
        if setup != .plain {
            // Zoomed out far enough that pins merge.
            vm.cameraSettled(on: MKCoordinateRegion(
                center: MockFixtures.tec.center, span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            ))
        }
        switch setup {
        case .plain, .grouped: break
        case .selected: vm.selectedID = MockFixtures.GameID.open
        case .filtered:
            vm.selectedID = MockFixtures.GameID.open
            vm.sportFilter = [MockFixtures.activity("basketball"), MockFixtures.activity("soccer")]
            vm.whenFilter = .today
            vm.distanceFilter = .walking
        case .searching:
            vm.searchText = "  crowd 1 "
            vm.distanceFilter = .biking
        case .tomorrow: vm.whenFilter = .tomorrow
        case .soon: vm.startingSoonOnly = true
        }

        let frame = vm.frame(in: store, now: now, mapSize: size)
        #expect(!frame.filtered.isEmpty)
        #expect(frame.open.map(\.id) == store.mapGames(now: now).map(\.id))
        #expect(frame.filtered.map(\.id) == vm.mapEvents(in: store, now: now).map(\.id))
        #expect(frame.filtered.map(\.id) == legacyMapEvents(vm, in: store, now: now).map(\.id))
        #expect(frame.groups.map { $0.games.map(\.id) } == vm.pinGroups(in: store, now: now, mapSize: size).map { $0.games.map(\.id) })
        #expect(frame.attendeeDemand.map(\.id) == vm.attendeePreviewGames(in: store, now: now, mapSize: size).map(\.id))
        #expect(vm.searchResults(from: frame.filtered, now: now).map(\.id) == vm.searchResults(in: store, now: now).map(\.id))
        if setup == .filtered { #expect(frame.filtered.count < frame.open.count) }
        if setup == .grouped || setup == .selected { #expect(frame.groups.contains { $0.games.count > 1 }) }
        if setup == .selected {
            let selected = try #require(frame.groups.first { $0.id == MockFixtures.GameID.open })
            #expect(selected.games.count == 1)
            #expect(frame.attendeeDemand.first?.id == MockFixtures.GameID.open)
        }

        // Before OPT-04: bumped pins were split out with two passes, and the search list sorted
        // with the key worked out in every comparison.
        let legacyOrder = frame.filtered.filter { !$0.isBumped(now: now) } + frame.filtered.filter { $0.isBumped(now: now) }
        #expect(vm.pinOrder(in: store, now: now).map(\.id) == legacyOrder.map(\.id))
        let legacySearch = frame.filtered.sorted {
            ($0.isBumped(now: now) ? 0 : 1, $0.startsAt) < ($1.isBumped(now: now) ? 0 : 1, $1.startsAt)
        }
        #expect(vm.searchResults(from: frame.filtered, now: now).map(\.id) == legacySearch.map(\.id))
    }

    @Test func searchTrimsSpacesAndABlankQueryMatchesEverything() {
        let host = MockBackend().me
        let now = Date.now
        let games = [
            game("After-work hoops", host: host, startsAt: now.addingTimeInterval(600)),
            game("Doubles", "tennis", host: host, startsAt: now.addingTimeInterval(600)),
        ]
        let vm = EventMapViewModel()
        vm.searchText = "   "
        #expect(vm.filter(games, now: now).map(\.id) == games.map(\.id))
        vm.searchText = "  HOOPS "
        #expect(vm.filter(games, now: now).map(\.id) == [games[0].id])
        vm.searchText = " tennis"
        #expect(vm.filter(games, now: now).map(\.id) == [games[1].id])
    }

    @Test func distanceIsMeasuredFromCampusWhenThereIsNoFix() {
        let host = MockBackend().me
        let now = Date.now
        let campus = MockFixtures.tec
        // About 1, 3 and 8 km north of campus: a degree of latitude is about 111 km.
        let games = [0.009, 0.027, 0.072].map {
            game("Court", host: host, startsAt: now.addingTimeInterval(600), latitude: campus.centerLatitude + $0)
        }
        let vm = EventMapViewModel()
        #expect(vm.userCoordinate == nil)
        // Nowhere to measure from yet: distance doesn't filter.
        vm.distanceFilter = .walking
        #expect(vm.filter(games, now: now).count == 3)
        vm.setCampus(campus)
        #expect(vm.filter(games, now: now).map(\.id) == [games[0].id])
        vm.distanceFilter = .biking
        #expect(vm.filter(games, now: now).map(\.id) == [games[0].id, games[1].id])
        vm.distanceFilter = .anywhere
        #expect(vm.filter(games, now: now).count == 3)
    }

    @Test func todayAndTomorrowFollowTheCalendarAcrossMidnight() throws {
        let host = MockBackend().me
        let calendar = Calendar.current
        let now = try #require(calendar.date(bySettingHour: 23, minute: 50, second: 0, of: .now))
        let lateToday = now.addingTimeInterval(5 * 60)
        let earlyTomorrow = now.addingTimeInterval(15 * 60)
        let lateTomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: lateToday))
        let dayAfter = try #require(calendar.date(byAdding: .day, value: 1, to: earlyTomorrow))
        let games = [lateToday, earlyTomorrow, lateTomorrow, dayAfter].map { game("Court", host: host, startsAt: $0) }
        let vm = EventMapViewModel()
        vm.whenFilter = .today
        #expect(vm.filter(games, now: now).map(\.id) == [games[0].id])
        vm.whenFilter = .tomorrow
        #expect(vm.filter(games, now: now).map(\.id) == [games[1].id, games[2].id])
        vm.whenFilter = .anyTime
        #expect(vm.filter(games, now: now).count == 4)
    }

    @Test func bumpedGamesListFirstThenSoonestAndTiesKeepTheirOrder() async throws {
        let backend = MockBackend()
        let now = backend.now
        let bumped = now.addingTimeInterval(-600)
        let soon = now.addingTimeInterval(600), later = now.addingTimeInterval(1800)
        let games = [
            game("A", host: backend.me, startsAt: soon),
            game("B", host: backend.me, startsAt: later, repostedAt: bumped),
            game("C", host: backend.me, startsAt: soon),
            game("D", host: backend.me, startsAt: later, repostedAt: bumped),
            game("E", host: backend.me, startsAt: later.addingTimeInterval(600), repostedAt: bumped),
            game("F", host: backend.me, startsAt: now.addingTimeInterval(300), repostedAt: now.addingTimeInterval(-3 * 3600)),
        ]
        let vm = EventMapViewModel()
        #expect(vm.searchResults(from: games, now: now).map(\.title) == ["B", "D", "E", "F", "A", "C"])

        let repository = ControlledGames(backend)
        repository.mapRead = { games }
        let store = GameStore(games: repository, profiles: backend, safety: backend, chat: backend, catalog: backend,
                              defaults: UserDefaults(suiteName: "MapPresentationTests.\(UUID().uuidString)")!)
        await store.load()
        // Pins: calm ones in the order given, then bumped ones on top.
        #expect(vm.pinOrder(in: store, now: now).map(\.title) == ["A", "C", "F", "B", "D", "E"])
    }
}
