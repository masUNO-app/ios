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
}
