import Foundation
import Testing
@testable import masUNO

@MainActor
struct MockBlockPrivacyTests {
    let backend = MockBackend()

    @Test(arguments: [false, true])
    func hostPlayerBlocksRemoveThePlayerInEitherDirection(incoming: Bool) async throws {
        let hosted = MockFixtures.GameID.hosting
        if incoming { backend.simulateBlock(by: MockFixtures.alex.id) }
        else { try await backend.block(userID: MockFixtures.alex.id) }

        let game = try await backend.fetchGame(id: hosted)
        #expect(game.goingCount == 2)
        #expect(!game.hasBlockedAttendee)
        #expect(try await backend.fetchAttendees(gameID: hosted).map(\.id) == [backend.me.id, MockFixtures.diego.id])
        #expect(!(try await backend.fetchActivity(gameID: hosted)).contains { $0.actor?.id == MockFixtures.alex.id })
        #expect(try await backend.fetchBlockedPeople().isEmpty == incoming)

        if incoming { backend.simulateUnblock(by: MockFixtures.alex.id) }
        else { try await backend.unblock(userID: MockFixtures.alex.id) }
        #expect(try await backend.fetchGame(id: hosted).goingCount == 2)
        #expect(!(try await backend.fetchAttendees(gameID: hosted)).contains { $0.id == MockFixtures.alex.id })
    }

    @Test(arguments: [false, true])
    func playerLosesHostGameAndIsNotRejoinedOnUnblock(incoming: Bool) async throws {
        let id = MockFixtures.GameID.going
        if incoming { backend.simulateBlock(by: MockFixtures.sam.id) }
        else { try await backend.block(userID: MockFixtures.sam.id) }
        await #expect(throws: DomainError.notFound) { try await backend.fetchGame(id: id) }
        #expect(!(try await backend.fetchMyGames()).contains { $0.id == id })
        #expect(try await backend.fetchMessages(gameID: id, before: nil, limit: 50).isEmpty)

        if incoming { backend.simulateUnblock(by: MockFixtures.sam.id) }
        else { try await backend.unblock(userID: MockFixtures.sam.id) }
        let game = try await backend.fetchGame(id: id)
        #expect(game.myRole == nil)
        #expect(game.goingCount == 4)
        #expect(!(try await backend.fetchAttendees(gameID: id)).contains { $0.id == backend.me.id })
    }

    @Test(arguments: [false, true])
    func peerBlocksHideEveryIdentityWithoutChangingAttendance(incoming: Bool) async throws {
        let id = MockFixtures.GameID.going
        if incoming { backend.simulateBlock(by: MockFixtures.maya.id) }
        else { try await backend.block(userID: MockFixtures.maya.id) }
        let game = try await backend.fetchGame(id: id)
        #expect(game.goingCount == 5)
        #expect(game.myRole == .player)
        #expect(game.hasBlockedAttendee == !incoming)
        #expect(!(try await backend.fetchAttendees(gameID: id)).contains { $0.id == MockFixtures.maya.id })
        #expect(!(try await backend.fetchActivity(gameID: id)).contains { $0.actor?.id == MockFixtures.maya.id })
        let messages = try await backend.fetchMessages(gameID: id, before: nil, limit: 50)
        #expect(!messages.contains { $0.sender.id == MockFixtures.maya.id })
        #expect(messages.contains { $0.sender.id == MockFixtures.sam.id })
    }

    @Test func incomingPeerBlockDoesNotBecomeAJoinPresenceOracle() async throws {
        let id = MockFixtures.GameID.open
        backend.simulateBlock(by: MockFixtures.ricardo.id)
        #expect(try await backend.fetchBlockedPeople().isEmpty)
        #expect(try await backend.fetchGame(id: id).hasBlockedAttendee == false)
        #expect(try await backend.joinGame(id: id).myRole == .player)
        #expect(!(try await backend.fetchAttendees(gameID: id)).contains { $0.id == MockFixtures.ricardo.id })
    }

    @Test func blockedHostRemovalKeepsHistoryAndReopensAFullUpcomingGame() async throws {
        let hosted = MockFixtures.GameID.hosting
        backend.fillGame(id: hosted)
        try await backend.block(userID: MockFixtures.alex.id)
        let game = try await backend.fetchGame(id: hosted)
        #expect(game.goingCount == game.capacity - 1)
        #expect(game.repostedAt == backend.now)
        #expect(try await backend.fetchMapGames().contains { $0.id == hosted })
        try await backend.unblock(userID: MockFixtures.alex.id)
        // The completed game remains historical attendance; only active RSVPs are removed.
        #expect(try await backend.fetchGame(id: MockFixtures.GameID.ended).myRole == .player)
        #expect(try await backend.fetchGame(id: MockFixtures.GameID.ended).goingCount == 3)
    }
}

@MainActor
struct GameStoreBlockPrivacyTests {
    let backend = MockBackend()
    let store: GameStore

    init() async {
        store = GameStore(
            games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend,
            defaults: UserDefaults(suiteName: "BlockPrivacy.\(UUID().uuidString)")!
        )
        store.isChatEnabled = true
        await store.load()
    }

    @Test func confirmedHostBlockReconcilesCountsAndJoinGates() async {
        let id = MockFixtures.GameID.hosting
        await store.loadAttendees(id)
        await store.loadActivity(id)
        await store.block(MockFixtures.alex)
        #expect(store.game(id)?.goingCount == 2)
        #expect(store.game(id)?.hasBlockedAttendee == false)
        #expect(!store.attendees(of: id).contains { $0.id == MockFixtures.alex.id })
        #expect(!store.activity(of: id).contains { $0.actor?.id == MockFixtures.alex.id })
        #expect(store.game(MockFixtures.GameID.open) == nil)
        await store.unblock(MockFixtures.alex)
        #expect(store.game(id)?.goingCount == 2)
        #expect(!store.attendees(of: id).contains { $0.id == MockFixtures.alex.id })
        #expect(store.game(MockFixtures.GameID.open) != nil)
    }

    @Test func failedBlockRestoresTheJoinGateAndRosterWithoutASecondRead() async {
        let id = MockFixtures.GameID.open
        await store.loadAttendees(id)
        backend.nextError = .offline
        await store.block(MockFixtures.ricardo)
        #expect(store.blockedPeople.isEmpty)
        #expect(store.game(id)?.hasBlockedAttendee == false)
        #expect(store.attendees(of: id).contains { $0.id == MockFixtures.ricardo.id })
        #expect(store.notice == DomainError.offline.message)
    }

    @Test func foregroundRefreshReauthorizesCachedDetailAndSavedGames() async {
        let id = MockFixtures.GameID.open
        await store.loadAttendees(id)
        await store.loadActivity(id)
        store.retainGames([id])
        store.toggleSaved(id)
        await store.waitForBookmarkWrites()
        backend.simulateBlock(by: MockFixtures.alex.id)
        await store.refresh()
        #expect(store.game(id) == nil)
        #expect(store.isMissing(id))
        #expect(!store.savedGames().contains { $0.id == id })
        #expect(store.attendees(of: id).isEmpty)
        #expect(store.activity(of: id).isEmpty)
        #expect(store.blockedPeople.isEmpty)
    }

    @Test func incomingPeerBlockRefreshesCachedAttendanceAndActivity() async {
        let id = MockFixtures.GameID.going
        await store.loadAttendees(id)
        await store.loadActivity(id)
        #expect(store.attendees(of: id).contains { $0.id == MockFixtures.maya.id })
        #expect(store.activity(of: id).contains { $0.actor?.id == MockFixtures.maya.id })
        let revision = store.privacyRevision
        backend.simulateBlock(by: MockFixtures.maya.id)
        await store.refresh()
        #expect(store.privacyRevision > revision)
        #expect(store.game(id)?.goingCount == 5)
        #expect(store.game(id)?.hasBlockedAttendee == false)
        #expect(!store.attendees(of: id).contains { $0.id == MockFixtures.maya.id })
        #expect(store.attendees(of: id).contains { $0.id == MockFixtures.sam.id })
        #expect(!store.activity(of: id).contains { $0.actor?.id == MockFixtures.maya.id })
        #expect(store.activity(of: id).contains { $0.actor?.id == MockFixtures.sam.id })
    }

    @Test func identityFreeRealtimeInvalidationRefreshesPreviouslyLoadedNames() async throws {
        let id = MockFixtures.GameID.going
        await store.loadAttendees(id)
        await store.loadActivity(id)
        for _ in 0..<100 where backend.gameChangeListenerCount == 0 { await Task.yield() }
        #expect(backend.gameChangeListenerCount > 0)
        let revision = store.privacyRevision
        backend.simulateBlock(by: MockFixtures.maya.id)
        for _ in 0..<100 {
            if store.privacyRevision > revision,
               store.attendees(of: id).contains(where: { $0.id == MockFixtures.sam.id }),
               !store.attendees(of: id).contains(where: { $0.id == MockFixtures.maya.id }),
               store.activity(of: id).contains(where: { $0.actor?.id == MockFixtures.sam.id }),
               !store.activity(of: id).contains(where: { $0.actor?.id == MockFixtures.maya.id }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.privacyRevision > revision)
        #expect(!store.attendees(of: id).contains { $0.id == MockFixtures.maya.id })
        #expect(!store.activity(of: id).contains { $0.actor?.id == MockFixtures.maya.id })
        #expect(store.game(id)?.goingCount == 5)
    }
}
