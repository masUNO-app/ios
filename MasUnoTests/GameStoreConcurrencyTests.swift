import Foundation
import MapKit
import Testing
@testable import masUNO

/// Also used by `MapPresentationTests` to put many games on the map.
@MainActor
final class ControlledGames: GameRepository {
    let backend: MockBackend
    var mapRead: (() async throws -> [Game])?
    var batchRead: (([UUID]) async throws -> [Game])?
    var batchCalls = 0
    var changeSink: AsyncStream<GameChanges>.Continuation?
    let changesReady = NotificationTestGate()
    var gameRead: ((UUID) async throws -> Game)?
    var peopleRead: ((UUID) async throws -> [Attendee])?
    var activityRead: ((UUID) async throws -> [GameActivityEntry])?
    var joinWrite: ((UUID) async throws -> Game)?
    var bookmarkWrite: ((UUID, Bool) async throws -> Game)?
    var createWrite: ((GameDraft) async throws -> Game)?
    var mapCalls = 0
    init(_ backend: MockBackend) { self.backend = backend }
    func fetchMapGames() async throws -> [Game] { mapCalls += 1; if let mapRead { return try await mapRead() }; return try await backend.fetchMapGames() }
    func fetchGuestGames(campus: UUID) async throws -> [Game] { try await backend.fetchGuestGames(campus: campus) }
    func fetchMyGames() async throws -> [Game] { try await backend.fetchMyGames() }
    func fetchGame(id: UUID) async throws -> Game { if let gameRead { return try await gameRead(id) }; return try await backend.fetchGame(id: id) }
    func fetchGames(ids: [UUID]) async throws -> [Game] { batchCalls += 1; if let batchRead { return try await batchRead(ids) }; return try await backend.fetchGames(ids: ids) }
    func fetchBookmarkedGames() async throws -> [Game] { try await backend.fetchBookmarkedGames() }
    func fetchAttendees(gameID: UUID) async throws -> [Attendee] { if let peopleRead { return try await peopleRead(gameID) }; return try await backend.fetchAttendees(gameID: gameID) }
    func fetchActivity(gameID: UUID) async throws -> [GameActivityEntry] { if let activityRead { return try await activityRead(gameID) }; return try await backend.fetchActivity(gameID: gameID) }
    func createGame(_ draft: GameDraft) async throws -> Game { if let createWrite { return try await createWrite(draft) }; return try await backend.createGame(draft) }
    func updateGame(id: UUID, _ draft: GameDraft) async throws -> Game { try await backend.updateGame(id: id, draft) }
    func cancelGame(id: UUID) async throws -> Game { try await backend.cancelGame(id: id) }
    func joinGame(id: UUID) async throws -> Game { if let joinWrite { return try await joinWrite(id) }; return try await backend.joinGame(id: id) }
    func leaveGame(id: UUID) async throws -> Game { try await backend.leaveGame(id: id) }
    func setBookmark(id: UUID, on: Bool) async throws -> Game { if let bookmarkWrite { return try await bookmarkWrite(id, on) }; return try await backend.setBookmark(id: id, on: on) }
    func setSpotAlert(id: UUID, on: Bool) async throws -> Game { try await backend.setSpotAlert(id: id, on: on) }
    func importBookmarks(ids: [UUID], alertIDs: [UUID]) async throws { try await backend.importBookmarks(ids: ids, alertIDs: alertIDs) }
    func changes(campus: UUID) -> AsyncStream<GameChanges> {
        AsyncStream { continuation in changeSink = continuation; changesReady.open() }
    }
}

@MainActor
struct GameStoreConcurrencyTests {
    let backend = MockBackend()
    private let games: ControlledGames
    let store: GameStore
    init() async {
        games = ControlledGames(backend)
        store = GameStore(games: games, profiles: backend, safety: backend, chat: backend, catalog: backend,
                          defaults: UserDefaults(suiteName: "StoreConcurrency.\(UUID().uuidString)")!)
        store.isChatEnabled = true
        await store.load()
    }

    @Test func oldAttendeesCannotRepopulateAClearedSession() async throws {
        let id = MockFixtures.GameID.going
        let people = try await backend.fetchAttendees(gameID: id)
        let gate = NotificationTestGate()
        games.peopleRead = { _ in await gate.wait(); return people }
        let old = Task { await store.loadAttendees(id) }
        await gate.waitUntilEntered()
        let session = store.sessionID
        store.reset()
        #expect(store.sessionID != session)
        gate.open()
        await old.value
        #expect(store.attendees(of: id).isEmpty)
        #expect(store.profile == nil)
    }

    @Test func lateAttendeeReplyCannotRestoreAnIncomingBlockedIdentity() async throws {
        let id = MockFixtures.GameID.going
        let stale = try await backend.fetchAttendees(gameID: id)
        let gate = NotificationTestGate()
        games.peopleRead = { _ in await gate.wait(); return stale }
        let old = Task { await store.loadAttendees(id) }
        await gate.waitUntilEntered()
        games.peopleRead = nil
        backend.simulateBlock(by: MockFixtures.maya.id)
        await store.refresh()
        gate.open()
        await old.value
        #expect(!store.attendees(of: id).contains { $0.id == MockFixtures.maya.id })
        await store.loadAttendees(id)
        #expect(!store.attendees(of: id).contains { $0.id == MockFixtures.maya.id })
        #expect(store.attendees(of: id).contains { $0.id == MockFixtures.sam.id })
    }

    @Test func lateActivityReplyCannotRestoreAnIncomingBlockedIdentity() async throws {
        let id = MockFixtures.GameID.going
        let stale = try await backend.fetchActivity(gameID: id)
        let gate = NotificationTestGate()
        games.activityRead = { _ in await gate.wait(); return stale }
        let old = Task { await store.loadActivity(id) }
        await gate.waitUntilEntered()
        games.activityRead = nil
        backend.simulateBlock(by: MockFixtures.maya.id)
        await store.refresh()
        gate.open()
        await old.value
        #expect(!store.activity(of: id).contains { $0.actor?.id == MockFixtures.maya.id })
    }

    @Test func lateGameReplyCannotRestoreAnIncomingBlockedHost() async throws {
        let id = MockFixtures.GameID.open
        let stale = try await backend.fetchGame(id: id)
        let gate = NotificationTestGate()
        games.gameRead = { _ in await gate.wait(); return stale }
        let old = Task { await store.loadGame(id) }
        await gate.waitUntilEntered()
        games.gameRead = nil
        backend.simulateBlock(by: MockFixtures.alex.id)
        await store.refresh()
        gate.open()
        await old.value
        #expect(store.game(id) == nil)
        #expect(store.isMissing(id))
    }

    @Test func delayedJoinReplyCannotRestoreMembershipRemovedByAHostBlock() async throws {
        let id = MockFixtures.GameID.open
        let gate = NotificationTestGate()
        games.joinWrite = { [backend] id in
            let game = try await backend.joinGame(id: id)
            await gate.wait()
            return game
        }
        let joining = Task { await store.join(id) }
        await gate.waitUntilEntered()
        backend.simulateBlock(by: MockFixtures.alex.id)
        await store.refresh()
        #expect(store.game(id) == nil)
        gate.open()
        await joining.value
        #expect(store.game(id) == nil)
        #expect(!store.goingGames().contains { $0.id == id })
        #expect(!store.asksForNotificationPrimer)
        backend.simulateUnblock(by: MockFixtures.alex.id)
        await store.refresh()
        #expect(store.game(id)?.myRole == nil)
        #expect(store.game(id)?.goingCount == 2)
    }

    @Test func delayedBookmarkReplyCannotRestoreAnIncomingBlockedHost() async throws {
        let id = MockFixtures.GameID.open
        let gate = NotificationTestGate()
        games.bookmarkWrite = { [backend] id, on in
            let game = try await backend.setBookmark(id: id, on: on)
            await gate.wait()
            return game
        }
        store.toggleSaved(id)
        await gate.waitUntilEntered()
        backend.simulateBlock(by: MockFixtures.alex.id)
        await store.refresh()
        #expect(store.game(id) == nil)
        gate.open()
        await store.waitForBookmarkWrites()
        #expect(store.game(id) == nil)
        #expect(!store.savedGames().contains { $0.id == id })
    }

    @Test func oldAccountMapCannotReplaceGuestMap() async throws {
        let data = try await backend.fetchMapGames()
        let gate = NotificationTestGate()
        games.mapRead = { await gate.wait(); return data }
        let old = Task { await store.refreshMap() }
        await gate.waitUntilEntered()
        await store.loadGuest(campus: MockFixtures.tec)
        gate.open()
        await old.value
        #expect(store.isGuest)
        #expect(store.profile == nil)
        #expect(store.mapGames().allSatisfy { $0.hidesPeople })
    }

    @Test func oldReadCannotUndoAConfirmedJoin() async throws {
        let id = MockFixtures.GameID.open
        let stale = try await backend.fetchGame(id: id)
        let gate = NotificationTestGate()
        games.gameRead = { _ in await gate.wait(); return stale }
        let old = Task { await store.loadGame(id) }
        await gate.waitUntilEntered()
        await store.join(id)
        #expect(store.game(id)?.myRole == .player)
        gate.open()
        await old.value
        #expect(store.game(id)?.myRole == .player)
        #expect(store.game(id)?.goingCount == stale.goingCount + 1)
    }

    @Test func leaveWaitsForAnInFlightJoinAndKeepsTheFinalIntent() async throws {
        let id = MockFixtures.GameID.open
        let gate = NotificationTestGate()
        games.joinWrite = { [backend] id in
            let joined = try await backend.joinGame(id: id)
            await gate.wait()
            return joined
        }
        let joining = Task { await store.join(id) }
        await gate.waitUntilEntered()
        #expect(store.game(id)?.isGoing == true)
        let leaving = Task { await store.leave(id) }
        gate.open()
        await joining.value
        await leaving.value
        #expect(store.game(id)?.isGoing == false)
        #expect(try await backend.fetchGame(id: id).isGoing == false)
    }

    @Test func unrelatedSuccessDoesNotClearAMapOfflineFailure() async {
        games.mapRead = { throw DomainError.offline }
        await store.refreshMap()
        #expect(store.isOffline)
        await store.refreshMyGames()
        #expect(store.isOffline)
        games.mapRead = nil
        await store.refreshMap()
        #expect(!store.isOffline)
    }

    @Test func invitesAreDeferredUntilRequested() async {
        #expect(store.invites.isEmpty)
        await store.loadInvites()
        #expect(store.invites.count == 3)
    }

    @Test func failedReadAcknowledgementStaysLocallyReadUntilReconciled() async {
        let id = MockFixtures.GameID.going
        backend.nextError = .offline
        await store.markChatRead(id)
        #expect(store.unreadCount(id) == 0)
        backend.nextError = .offline
        await store.refreshUnread()
        #expect(store.unreadCount(id) == 0)
        await store.refreshUnread()
        #expect(store.unreadCount(id) == 0)
        #expect(!store.isOffline)
    }

    @Test func lateCreateCannotPopulateTheGuestSession() async throws {
        let gate = NotificationTestGate()
        let template = try #require(store.game(MockFixtures.GameID.open))
        var draft = GameDraft(template)
        draft.title = "Session scoped create"
        games.createWrite = { [backend] draft in
            let created = try await backend.createGame(draft)
            await gate.wait()
            return created
        }
        let creating = Task { try await store.createGame(draft) }
        await gate.waitUntilEntered()
        await store.loadGuest(campus: MockFixtures.tec)
        gate.open()
        do { try await creating.value; Issue.record("Expected stale create to be discarded") }
        catch { #expect(OperationCancellation.isCancellation(error)) }
        #expect(store.lastCreatedID == nil)
        #expect(!store.asksForNotificationPrimer)
        #expect(store.isGuest)
    }
    @Test func concurrentMapRefreshesShareOneRepositoryCall() async throws {
        let data = try await backend.fetchMapGames()
        let before = games.mapCalls
        let gate = NotificationTestGate()
        games.mapRead = { await gate.wait(); return data }
        let first = Task { await store.refreshMap() }
        await gate.waitUntilEntered()
        let entered = NotificationTestGate()
        let second = Task { entered.open(); await store.refreshMap() }
        await entered.wait()
        gate.open()
        await first.value
        await second.value
        #expect(games.mapCalls == before + 1)
    }

    @Test func mapRefreshPreservesRepositoryOrdering() async throws {
        let data = try await backend.fetchMapGames()
        let expected = data.map { $0.id }
        games.mapRead = { data }
        for _ in 0..<5 {
            await store.refreshMap()
            let actual = store.mapGames(now: backend.now).map { $0.id }
            #expect(actual == expected)
        }
    }

    @Test func oldMapCannotRemoveAGameCreatedDuringTheRead() async throws {
        let data = try await backend.fetchMapGames()
        let gate = NotificationTestGate()
        games.mapRead = { await gate.wait(); return data }
        let old = Task { await store.refreshMap() }
        await gate.waitUntilEntered()
        let template = try #require(store.game(MockFixtures.GameID.open))
        var draft = GameDraft(template)
        draft.title = "Created while refreshing"
        draft.startsAt = .now.addingTimeInterval(7200)
        try await store.createGame(draft)
        let created = try #require(store.lastCreatedID)
        gate.open()
        await old.value
        #expect(store.mapGames().contains { $0.id == created })
    }

    @Test func retainedNavigationSurvivesEvictionUntilReleased() async {
        let id = MockFixtures.GameID.open
        store.retainGames([id])
        games.mapRead = { [] }
        await store.refreshMap()
        await store.loadGame(id)
        let later = Date.now.addingTimeInterval(3600)
        store.pruneUnusedGames(now: later)
        #expect(store.game(id) != nil)
        store.retainGames([])
        store.pruneUnusedGames(now: later)
        #expect(store.game(id) == nil)
    }

    @Test func realtimeBurstDrainsInvalidationsThatArriveDuringARead() async {
        await games.changesReady.wait()
        let first = NotificationTestGate()
        let second = NotificationTestGate()
        var reads = 0
        games.batchRead = { [backend] ids in
            reads += 1
            if reads == 1 { await first.wait() } else { await second.wait() }
            return try await backend.fetchGames(ids: ids)
        }
        for _ in 0..<100 { games.changeSink?.yield(.games([MockFixtures.GameID.going])) }
        await first.waitUntilEntered()
        #expect(reads == 1)
        games.changeSink?.yield(.games([MockFixtures.GameID.going]))
        first.open()
        await second.waitUntilEntered()
        #expect(reads == 2)
        second.open()
        store.reset()
    }

    @Test(arguments: [100, 500]) func groupingPreservesEveryGameAtScale(count: Int) async throws {
        let template = try #require(store.game(MockFixtures.GameID.open))
        var synthetic: [Game] = []
        for index in 0..<count {
            let latitude: Double = 25.0 + Double(index / 25) * 0.001
            let longitude: Double = -100.0 + Double(index % 25) * 0.001
            let place = Place(name: "Court", address: "", latitude: latitude, longitude: longitude)
            let game = Game(id: UUID(), host: template.host, activity: template.activity, title: "Synthetic \(index)",
                            startsAt: template.startsAt, durationMinutes: 60, endsAt: template.endsAt,
                            capacity: 4, goingCount: 1, place: place, autoRepost: true,
                            createdAt: .now, hasBlockedAttendee: false)
            synthetic.append(game)
        }
        let data = synthetic
        games.mapRead = { data }
        await store.refreshMap()
        let vm = EventMapViewModel()
        vm.cameraSettled(on: MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 25.01, longitude: -99.99),
                         span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
        let start = ContinuousClock.now
        let groups = vm.pinGroups(in: store, now: template.startsAt, mapSize: CGSize(width: 400, height: 800))
        let duration = ContinuousClock.now - start
        let groupedGames = groups.flatMap { $0.games }
        let groupedIDs = Set(groupedGames.map { $0.id })
        let expectedIDs = Set(data.map { $0.id })
        #expect(groupedIDs == expectedIDs)
        #expect(groupedGames.count == count)
        print("Map grouping synthetic \(count) games: \(duration), \(groups.count) groups (Debug simulator; not a device budget)")
    }

}
