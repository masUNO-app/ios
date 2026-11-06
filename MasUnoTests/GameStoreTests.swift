import Foundation
import Testing
@testable import MasUno

@MainActor
struct GameStoreTests {
    let backend = MockBackend()
    let store: GameStore

    init() async {
        let suite = "GameStoreTests.\(UUID().uuidString)"
        store = GameStore(
            games: backend, profiles: backend, safety: backend, catalog: backend,
            defaults: UserDefaults(suiteName: suite)!
        )
        await store.load()
    }

    @Test func loadFillsEveryList() {
        #expect(store.mapState == .loaded)
        #expect(store.myGamesState == .loaded)
        #expect(store.profile?.firstName == "Emilio")
        #expect(store.mapGames().contains { $0.id == MockFixtures.GameID.open })
        #expect(store.goingGames().map(\.id) == [MockFixtures.GameID.going])
        #expect(store.hostedGames().map(\.id) == [MockFixtures.GameID.hosting])
        #expect(store.pastGames().map(\.id) == [MockFixtures.GameID.ended])
    }

    // MARK: Optimistic join and leave

    @Test func joinShowsBeforeTheServerAnswers() async {
        backend.latency = .milliseconds(100)
        let id = MockFixtures.GameID.open
        let joining = Task { await store.join(id) }
        await Task.yield()
        #expect(store.game(id)?.status() == .going)
        #expect(store.game(id)?.goingCount == 3)
        await joining.value
        #expect(store.game(id)?.status() == .going)
        #expect(store.notice == nil)
    }

    @Test func losingTheLastSpotRollsBackWithTheRightMessage() async {
        let id = MockFixtures.GameID.lastSpot
        backend.fillGame(id: id)
        await store.join(id)
        #expect(store.notice == "Someone just took the last spot.")
        #expect(store.game(id)?.myRole == nil)
        // Reloaded after the failure, so the screen shows Full.
        #expect(store.game(id)?.status() == .full)
    }

    @Test func offlineJoinRollsBackAndSaysSo() async {
        let id = MockFixtures.GameID.open
        backend.nextError = .offline
        await store.join(id)
        #expect(store.game(id)?.myRole == nil)
        #expect(store.game(id)?.goingCount == 2)
        #expect(store.notice == DomainError.offline.message)
        #expect(store.isOffline)
    }

    @Test func joinWithSomeoneBlockedNeverCallsTheServer() async {
        let id = MockFixtures.GameID.open
        await store.loadAttendees(id)
        await store.block(MockFixtures.ricardo)
        await store.join(id)
        #expect(store.notice == "Someone you blocked is going.")
        #expect(store.game(id)?.myRole == nil)
    }

    @Test func failedLeaveRestoresYourSpot() async {
        let id = MockFixtures.GameID.going
        backend.nextError = .ended
        await store.leave(id)
        #expect(store.game(id)?.myRole == .player)
        #expect(store.notice == DomainError.ended.message)
    }

    @Test func leavingUpdatesAttendees() async {
        let id = MockFixtures.GameID.going
        await store.loadAttendees(id)
        #expect(store.attendees(of: id).count == 5)
        await store.leave(id)
        #expect(store.attendees(of: id).count == 4)
        #expect(store.goingGames().isEmpty)
    }

    // MARK: Blocking

    @Test func blockHidesEverythingBeforeTheServerAnswers() async {
        backend.latency = .milliseconds(100)
        let id = MockFixtures.GameID.open
        await store.loadAttendees(MockFixtures.GameID.hosting)
        let blocking = Task { await store.block(MockFixtures.alex) }
        await Task.yield()
        #expect(store.game(id) == nil)
        #expect(!store.mapGames().contains { $0.id == id })
        #expect(!store.attendees(of: MockFixtures.GameID.hosting).contains { $0.id == MockFixtures.alex.id })
        #expect(store.blockedPeople == [MockFixtures.alex])
        await blocking.value
    }

    @Test func failedBlockPutsThemBack() async {
        backend.nextError = .offline
        await store.block(MockFixtures.alex)
        #expect(store.blockedPeople.isEmpty)
        #expect(store.game(MockFixtures.GameID.open) != nil)
        #expect(store.notice == DomainError.offline.message)
    }

    @Test func unblockBringsGamesBack() async {
        await store.block(MockFixtures.alex)
        await store.unblock(MockFixtures.alex)
        #expect(store.blockedPeople.isEmpty)
        #expect(store.game(MockFixtures.GameID.open) != nil)
    }

    // MARK: Loads

    @Test func failedFirstLoadOffersRetry() async {
        let fresh = GameStore(games: backend, profiles: backend, safety: backend, catalog: backend)
        backend.nextError = .offline
        await fresh.refreshMap()
        #expect(fresh.mapState == .failed(.offline))
        #expect(fresh.isOffline)
        await fresh.refreshMap()
        #expect(fresh.mapState == .loaded)
        #expect(!fresh.isOffline)
    }

    @Test func failedRefreshKeepsTheLastGames() async {
        backend.nextError = .offline
        await store.refreshMap()
        #expect(store.mapState == .loaded)
        #expect(store.isOffline)
        #expect(!store.mapGames().isEmpty)
    }

    @Test func missingGameIsReported() async {
        let id = UUID()
        await store.loadGame(id)
        #expect(store.isMissing(id))
        #expect(!store.isMissing(MockFixtures.GameID.open))
    }

    @Test func sessionProblemsAreReported() async {
        var reported = false
        store.onSessionProblem = { reported = true }
        backend.suspend()
        await store.join(MockFixtures.GameID.open)
        #expect(reported)
        #expect(store.game(MockFixtures.GameID.open)?.myRole == nil)
    }

    // MARK: Hosting

    @Test func createdGameIsOnTheMapAndInHosting() async throws {
        let draft = GameDraft(
            activity: MockFixtures.activity("padel"), title: "New game",
            startsAt: backend.now.addingTimeInterval(7200), durationMinutes: 60, capacity: 4,
            place: MockFixtures.Places.park
        )
        try await store.createGame(draft)
        #expect(store.lastCreatedID != nil)
        #expect(store.mapGames().first?.title == "New game")
        #expect(store.hostedGames().count == 2)
    }

    @Test func formErrorsAreThrown() async {
        let draft = GameDraft(
            activity: MockFixtures.activity("padel"), title: "",
            startsAt: backend.now.addingTimeInterval(7200), durationMinutes: 60, capacity: 4,
            place: MockFixtures.Places.park
        )
        await #expect(throws: DomainError.invalidInput) { try await store.createGame(draft) }
    }

    @Test func cancelKeepsTheGameMarkedCancelled() async {
        await store.cancelGame(MockFixtures.GameID.hosting)
        #expect(store.game(MockFixtures.GameID.hosting)?.isCancelled == true)
        #expect(store.hostedGames().isEmpty)
    }

    @Test func meetPointUpdatesAndLogs() async throws {
        let id = MockFixtures.GameID.hosting
        try await store.updateMeetPoint(id, to: "South gate")
        #expect(store.game(id)?.meetPoint == "South gate")
        #expect(store.activity(of: id).last?.kind == .meetPointUpdated)
    }

    // MARK: Saved

    @Test func savedGamesSurviveARelaunch() async {
        let suite = UserDefaults(suiteName: "GameStoreTests.\(UUID().uuidString)")!
        let first = GameStore(games: backend, profiles: backend, safety: backend, catalog: backend, defaults: suite)
        await first.load()
        first.toggleSaved(MockFixtures.GameID.lastSpot)
        #expect(first.savedGames().map(\.id) == [MockFixtures.GameID.lastSpot])

        let relaunched = GameStore(games: backend, profiles: backend, safety: backend, catalog: backend, defaults: suite)
        await relaunched.load()
        #expect(relaunched.isSaved(MockFixtures.GameID.lastSpot))
        #expect(relaunched.savedGames().map(\.id) == [MockFixtures.GameID.lastSpot])
    }

    @Test func resetClearsTheAccount() async {
        store.reset()
        #expect(store.profile == nil)
        #expect(store.mapGames().isEmpty)
        #expect(store.mapState == .idle)
    }
}

@MainActor
struct AutoRepostTests {
    let backend = MockBackend()
    let store: GameStore

    init() async {
        store = GameStore(
            games: backend, profiles: backend, safety: backend, catalog: backend,
            defaults: UserDefaults(suiteName: "AutoRepostTests.\(UUID().uuidString)")!
        )
        await store.load()
    }

    @Test func bumpedPinDrawsLast() {
        let order = EventMapViewModel().pinOrder(in: store, now: backend.now)
        #expect(order.last?.id == MockFixtures.GameID.bumped)
    }

    @Test func pinStopsBeingBumpedAfterTwoHours() {
        let later = backend.now.addingTimeInterval(2 * 3600 + 1)
        let order = EventMapViewModel().pinOrder(in: store, now: later)
        #expect(order.last?.id != MockFixtures.GameID.bumped || order.count == 1)
        #expect(store.game(MockFixtures.GameID.bumped)?.isBumped(now: later) == false)
    }

    /// E25's "Done when": a player leaves a full game and the host's card sees the repost.
    @Test func playerLeavingAFullGameRepostsItForTheHost() async {
        let id = MockFixtures.GameID.hosting
        backend.fillGame(id: id)
        backend.simulateDropOut(id: id)
        await store.refreshMyGames()
        #expect(store.game(id)?.repostedAt == backend.now)
        #expect(store.game(id)?.isBumped(now: backend.now) == true)
    }
}

@MainActor
struct OfflineStateTests {
    let backend = MockBackend()

    private func makeStore() -> GameStore {
        GameStore(
            games: backend, profiles: backend, safety: backend, catalog: backend,
            defaults: UserDefaults(suiteName: "OfflineStateTests.\(UUID().uuidString)")!
        )
    }

    /// E14's "Done when": airplane mode never leaves a screen spinning.
    @Test func gameThatCantLoadOfflineIsNotStuckLoading() async {
        let store = makeStore()
        backend.nextError = .offline
        await store.loadGame(MockFixtures.GameID.open)
        #expect(store.game(MockFixtures.GameID.open) == nil)
        #expect(!store.isMissing(MockFixtures.GameID.open))
        #expect(store.isOffline)
        await store.loadGame(MockFixtures.GameID.open)
        #expect(store.game(MockFixtures.GameID.open) != nil)
        #expect(!store.isOffline)
    }

    @Test func failedMyGamesOffersRetryThenRecovers() async {
        let store = makeStore()
        backend.nextError = .offline
        await store.refreshMyGames()
        #expect(store.myGamesState == .failed(.offline))
        await store.refreshMyGames()
        #expect(store.myGamesState == .loaded)
    }
}
