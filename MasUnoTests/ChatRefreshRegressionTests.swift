import Foundation
import Testing
@testable import masUNO

/// Scripted reads make cancellation and response ordering independent of the shared mock's nextError.
@MainActor
private final class ScriptedChatRepository: ChatRepository {
    let backend: MockBackend
    var latestCalls = 0
    var acknowledgementCalls = 0
    var acknowledge: (() async throws -> Void)?
    var latest: (() async throws -> [ChatMessage])?
    var incremental: (() async throws -> [ChatMessage])?

    init(_ backend: MockBackend) { self.backend = backend }

    func fetchMessages(gameID: UUID, before: Date?, limit: Int) async throws -> [ChatMessage] {
        latestCalls += 1
        if let latest { return try await latest() }
        return try await backend.fetchMessages(gameID: gameID, before: before, limit: limit)
    }
    func fetchMessages(gameID: UUID, before cursor: ChatMessageCursor, limit: Int) async throws -> [ChatMessage] {
        try await backend.fetchMessages(gameID: gameID, before: cursor, limit: limit)
    }
    func fetchMessages(gameID: UUID, since: Date) async throws -> [ChatMessage] {
        if let incremental { return try await incremental() }
        return try await backend.fetchMessages(gameID: gameID, since: since)
    }
    func sendMessage(gameID: UUID, body: String, clientID: UUID, mentions: [UUID]) async throws -> ChatMessage {
        try await backend.sendMessage(gameID: gameID, body: body, clientID: clientID, mentions: mentions)
    }
    func acceptChatRules() async throws { try await backend.acceptChatRules() }
    func markRead(gameID: UUID) async throws {
        acknowledgementCalls += 1
        if let acknowledge { try await acknowledge() }
        else { try await backend.markRead(gameID: gameID) }
    }
    func fetchUnreadCounts() async throws -> [UUID: Int] { try await backend.fetchUnreadCounts() }
    func updates(gameID: UUID) -> AsyncStream<ChatUpdate> { backend.updates(gameID: gameID) }
}

@MainActor
private final class ChatReadGate {
    private var started = false
    private var entered: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<[ChatMessage], Never>?

    func read() async -> [ChatMessage] {
        await withCheckedContinuation { continuation in
            completion = continuation
            started = true
            let waiting = entered
            entered = []
            for waiter in waiting { waiter.resume() }
        }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { entered.append($0) }
    }
    func finish(_ messages: [ChatMessage] = []) {
        let held = completion
        completion = nil
        held?.resume(returning: messages)
    }
}

@MainActor
struct ChatRefreshRegressionTests {
    let backend = MockBackend()
    private let repository: ScriptedChatRepository
    let store: GameStore
    let chat = ChatViewModel(gameID: MockFixtures.GameID.going)

    init() async {
        repository = ScriptedChatRepository(backend)
        store = GameStore(
            games: backend, profiles: backend, safety: backend, chat: repository, catalog: backend,
            defaults: UserDefaults(suiteName: "ChatRefreshRegression.\(UUID().uuidString)")!
        )
        store.isChatEnabled = true
        await store.load()
    }

    @Test func aNewReadDuringAcknowledgementIsNotLost() async {
        let gate = NotificationTestGate()
        repository.acknowledge = { await gate.wait() }
        let first = Task { await store.markChatRead(MockFixtures.GameID.going) }
        await gate.waitUntilEntered()
        let entered = NotificationTestGate()
        let second = Task { entered.open(); await store.markChatRead(MockFixtures.GameID.going) }
        await entered.wait()
        gate.open()
        await first.value
        await second.value
        #expect(repository.acknowledgementCalls == 2)
        #expect(store.unreadCount(MockFixtures.GameID.going) == 0)
    }

    @Test func cancelledRefreshKeepsASuccessfulEmptyConversation() async {
        repository.latest = { [] }
        await chat.reload(in: store)
        repository.latest = { throw CancellationError() }
        await chat.reload(in: store)
        #expect(chat.state == .loaded)
        #expect(chat.hasLoaded)
        #expect(chat.messages.isEmpty)
        #expect(chat.refreshError == nil)
        #expect(!store.isOffline)
    }

    @Test func cancelledURLRefreshIsNotOffline() async {
        repository.latest = { [] }
        await chat.reload(in: store)
        repository.latest = { throw URLError(.cancelled) }
        await chat.reload(in: store)
        #expect(chat.state == .loaded)
        #expect(chat.refreshError == nil)
        #expect(!store.isOffline)
    }

    @Test func initialFailureStillOffersRetry() async {
        repository.latest = { throw DomainError.offline }
        await chat.reload(in: store)
        #expect(chat.state == .failed(.offline))
        #expect(!chat.hasLoaded)
        repository.latest = { [] }
        await chat.reload(in: store)
        #expect(chat.state == .loaded)
        #expect(chat.hasLoaded)
    }

    @Test func realRefreshFailureKeepsLoadedStateAndAnActionableError() async {
        repository.latest = { [] }
        await chat.reload(in: store)
        repository.latest = { throw DomainError.offline }
        await chat.reload(in: store)
        #expect(chat.state == .loaded)
        #expect(chat.refreshError == .offline)
        repository.latest = { [] }
        await chat.reload(in: store)
        #expect(chat.refreshError == nil)
        #expect(!store.isOffline)
    }

    @Test func concurrentReloadsShareTheRequest() async {
        let gate = ChatReadGate()
        repository.latest = { await gate.read() }
        let first = Task { await chat.reload(in: store) }
        await gate.waitUntilStarted()
        let secondEntered = NotificationTestGate()
        let second = Task {
            secondEntered.open()
            await chat.reload(in: store)
        }
        await secondEntered.wait()
        gate.finish()
        await first.value
        await second.value
        #expect(repository.latestCalls == 1)
        #expect(chat.state == .loaded)
    }

    @Test func cancellingOneWaiterDoesNotCancelAnotherConsumersRead() async {
        let gate = ChatReadGate()
        repository.latest = { await gate.read() }
        let first = Task { await chat.reload(in: store) }
        await gate.waitUntilStarted()
        let secondEntered = NotificationTestGate()
        let second = Task {
            secondEntered.open()
            await chat.reload(in: store)
        }
        await secondEntered.wait()
        first.cancel()
        gate.finish()
        await first.value
        await second.value
        #expect(repository.latestCalls == 1)
        #expect(chat.state == .loaded)
        #expect(!store.isOffline)
    }

    @Test func cancelledOnlyWaiterDoesNotPublishEvenIfTransportIgnoresCancellation() async {
        let gate = ChatReadGate()
        repository.latest = { await gate.read() }
        let task = Task { await chat.reload(in: store) }
        await gate.waitUntilStarted()
        task.cancel()
        gate.finish()
        await task.value
        #expect(chat.state == .idle)
        #expect(!chat.hasLoaded)
        #expect(!store.isOffline)
    }

    @Test func replyFromPreviousSessionCannotPublishMessages() async throws {
        let old = try await backend.fetchMessages(gameID: MockFixtures.GameID.going, before: nil, limit: 50)
        let gate = ChatReadGate()
        repository.latest = { await gate.read() }
        let task = Task { await chat.reload(in: store) }
        await gate.waitUntilStarted()
        store.reset()
        gate.finish(old)
        await task.value
        #expect(chat.messages.isEmpty)
        #expect(chat.rows(in: store).isEmpty)
    }

    @Test func olderPagesProgressAcrossMoreThanOnePageAtTheSameTimestamp() async {
        for index in 0..<70 {
            backend.receiveMessage(from: MockFixtures.sam, in: MockFixtures.GameID.going, body: "Same time \(index)")
        }
        await chat.reload(in: store)
        #expect(chat.messages.count == 50)
        await chat.loadOlder(in: store)
        #expect(chat.messages.count == 74)
        #expect(Set(chat.messages.map(\.id)).count == 74)
        #expect(!chat.hasOlder)
    }

    @Test func incrementalAuthenticationFailureReachesSessionHandling() async {
        await chat.reload(in: store)
        var problems = 0
        store.onSessionProblem = { problems += 1 }
        repository.incremental = { throw DomainError.notAuthenticated }
        await chat.fetchNew(in: store)
        #expect(problems == 1)
        #expect(chat.state == .loaded)
    }
}

@MainActor
struct LiveRequestCancellationTests {
    @Test func cancellationErrorSurvivesTheRepositoryBoundary() async {
        do {
            let _: Int = try await liveRequest { throw CancellationError() }
            Issue.record("Expected cancellation")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test func cancelledURLSurvivesTheRepositoryBoundary() async {
        do {
            let _: Int = try await liveRequest { throw URLError(.cancelled) }
            Issue.record("Expected cancellation")
        } catch {
            #expect((error as? URLError)?.code == .cancelled)
        }
    }

    @Test func actualConnectivityFailureStillBecomesOffline() async {
        do {
            let _: Int = try await liveRequest { throw URLError(.notConnectedToInternet) }
            Issue.record("Expected offline")
        } catch {
            #expect(error as? DomainError == .offline)
        }
    }

    @Test func cursorKeepsOriginalMicrosecondTimestamp() throws {
        let json = """
        {"id":"8866dace-f67a-4d74-a2e9-f2ae6fcf2a66","event_id":"9e6ead38-803f-4d9a-a023-2ee54b5f2946",
        "sender_id":"b0000000-0000-4000-8000-00000000000b","sender_first_name":"Bruno","sender_last_initial":"Y",
        "sender_grad_year":2026,"body":"Here","client_id":"c145b8a9-4646-4694-bf35-5f4aa76d62d0",
        "created_at":"2026-11-10T19:48:49.015403-05:00"}
        """
        let message = try JSONDecoder().decode(GameMessageRow.self, from: Data(json.utf8)).message
        #expect(ChatMessageCursor(message).serverCreatedAt == "2026-11-10T19:48:49.015403-05:00")
    }
}
