import Foundation
import Testing
@testable import masUNO

/// Holds individual transports past a privacy invalidation, including transports that ignore
/// cancellation, so old pages and send acknowledgements cannot restore a revoked timeline.
@MainActor
private final class PrivacyChatRepository: ChatRepository {
    let backend: MockBackend
    var latest: (() async throws -> [ChatMessage])?
    var incremental: (() async throws -> [ChatMessage])?
    var older: (() async throws -> [ChatMessage])?
    var send: ((String, UUID) async throws -> ChatMessage)?

    init(_ backend: MockBackend) { self.backend = backend }

    func fetchMessages(gameID: UUID, before: Date?, limit: Int) async throws -> [ChatMessage] {
        if let latest { return try await latest() }
        return try await backend.fetchMessages(gameID: gameID, before: before, limit: limit)
    }

    func fetchMessages(gameID: UUID, before cursor: ChatMessageCursor, limit: Int) async throws -> [ChatMessage] {
        if let older { return try await older() }
        return try await backend.fetchMessages(gameID: gameID, before: cursor, limit: limit)
    }

    func fetchMessages(gameID: UUID, since: Date) async throws -> [ChatMessage] {
        if let incremental { return try await incremental() }
        return try await backend.fetchMessages(gameID: gameID, since: since)
    }

    func sendMessage(gameID: UUID, body: String, clientID: UUID) async throws -> ChatMessage {
        if let send { return try await send(body, clientID) }
        return try await backend.sendMessage(gameID: gameID, body: body, clientID: clientID)
    }

    func acceptChatRules() async throws { try await backend.acceptChatRules() }
    func markRead(gameID: UUID) async throws { try await backend.markRead(gameID: gameID) }
    func fetchUnreadCounts() async throws -> [UUID: Int] { try await backend.fetchUnreadCounts() }
    func updates(gameID: UUID) -> AsyncStream<ChatUpdate> { backend.updates(gameID: gameID) }
}

@MainActor
struct ChatPrivacyTests {
    private let backend = MockBackend()
    private let repository: PrivacyChatRepository
    private let store: GameStore
    private let going = MockFixtures.GameID.going
    private let chat = ChatViewModel(gameID: MockFixtures.GameID.going)

    init() async {
        repository = PrivacyChatRepository(backend)
        store = GameStore(
            games: backend, profiles: backend, safety: backend, chat: repository, catalog: backend,
            defaults: UserDefaults(suiteName: "ChatPrivacyTests.\(UUID().uuidString)")!
        )
        store.isChatEnabled = true
        await store.load()
    }

    @Test func incomingPeerBlockDropsCachedOlderPagesWithoutKnowingBlockerIdentity() async {
        for index in 0..<60 {
            backend.now = backend.now.addingTimeInterval(1)
            backend.receiveMessage(from: MockFixtures.maya, in: going, body: "Older private message \(index)")
        }
        await chat.reload(in: store)
        await chat.loadOlder(in: store)
        #expect(chat.messages.count == 64)

        backend.simulateBlock(by: MockFixtures.maya.id)
        await store.refresh()
        #expect(!store.isBlocked(MockFixtures.maya.id))
        // Until the authoritative replacement loads, no cached message or activity is shown.
        #expect(chat.rows(in: store).isEmpty)
        await chat.fetchNew(in: store)
        #expect(chat.hasLoaded)
        #expect(!chat.hasOlder)
        #expect(!chat.messages.contains { $0.sender.id == MockFixtures.maya.id })
        #expect(chat.messages.contains { $0.sender.id == MockFixtures.sam.id })
    }

    @Test func latestReadStartedBeforeBlockCannotRestoreHiddenMessages() async throws {
        let oldPage = try await backend.fetchMessages(gameID: going, before: nil, limit: 50)
        let gate = NotificationTestGate()
        repository.latest = { await gate.wait(); return oldPage }
        let stale = Task { await chat.reload(in: store) }
        await gate.waitUntilEntered()

        backend.simulateBlock(by: MockFixtures.maya.id)
        await store.refresh()
        repository.latest = nil
        await chat.reload(in: store)
        gate.open()
        await stale.value
        #expect(chat.hasLoaded)
        #expect(!chat.messages.contains { $0.sender.id == MockFixtures.maya.id })
        #expect(chat.messages.contains { $0.sender.id == MockFixtures.sam.id })
    }

    @Test func incrementalReadStartedBeforeBlockCannotRestoreHiddenMessages() async throws {
        await chat.reload(in: store)
        let oldPage = try await backend.fetchMessages(gameID: going, before: nil, limit: 50)
        let gate = NotificationTestGate()
        repository.incremental = { await gate.wait(); return oldPage }
        let stale = Task { await chat.fetchNew(in: store) }
        await gate.waitUntilEntered()

        backend.simulateBlock(by: MockFixtures.maya.id)
        await store.refresh()
        await chat.fetchNew(in: store)
        gate.open()
        await stale.value
        #expect(!chat.messages.contains { $0.sender.id == MockFixtures.maya.id })
        #expect(chat.messages.contains { $0.sender.id == MockFixtures.sam.id })
    }

    @Test func olderReadStartedBeforeBlockCannotRestoreHiddenMessages() async throws {
        let oldPage = try await backend.fetchMessages(gameID: going, before: nil, limit: 50)
        for index in 0..<60 {
            backend.now = backend.now.addingTimeInterval(1)
            backend.receiveMessage(from: MockFixtures.nina, in: going, body: "Newer message \(index)")
        }
        await chat.reload(in: store)
        #expect(chat.hasOlder)
        let gate = NotificationTestGate()
        repository.older = { await gate.wait(); return oldPage }
        let stale = Task { await chat.loadOlder(in: store) }
        await gate.waitUntilEntered()

        backend.simulateBlock(by: MockFixtures.maya.id)
        await store.refresh()
        await chat.reload(in: store)
        gate.open()
        await stale.value
        #expect(!chat.messages.contains { $0.sender.id == MockFixtures.maya.id })
        #expect(!chat.isLoadingOlder)
    }

    @Test func peerPrivacyRefreshPreservesOwnDraftAndStableRetryID() async throws {
        await chat.reload(in: store)
        let gate = NotificationTestGate()
        repository.send = { [backend, going] body, clientID in
            await gate.wait()
            return ChatMessage(id: UUID(), gameID: going, sender: backend.me, body: body,
                               clientID: clientID, createdAt: backend.now)
        }
        chat.draft = "On my way"
        chat.send(in: store)
        let pendingID = try #require(chat.pending.first?.id)
        let stale = Task { await chat.deliver(pendingID, in: store) }
        await gate.waitUntilEntered()
        chat.draft = "Bringing water too"

        backend.simulateBlock(by: MockFixtures.maya.id)
        await store.refresh()
        chat.synchronize(in: store)
        #expect(chat.draft == "Bringing water too")
        #expect(chat.pending.first?.id == pendingID)
        #expect(chat.pending.first?.error == .unknown("send_outcome_unknown"))
        await chat.reload(in: store)
        repository.send = nil
        await chat.deliver(pendingID, in: store)
        gate.open()
        await stale.value
        #expect(chat.pending.isEmpty)
        #expect(chat.messages.filter { $0.clientID == pendingID }.count == 1)
    }

    @Test func hostBlockRevokesCachedChatAndLateSendAcknowledgement() async throws {
        await chat.reload(in: store)
        let gate = NotificationTestGate()
        repository.send = { [backend, going] body, clientID in
            await gate.wait()
            return ChatMessage(id: UUID(), gameID: going, sender: backend.me, body: body,
                               clientID: clientID, createdAt: backend.now)
        }
        chat.draft = "On my way"
        chat.send(in: store)
        let pendingID = try #require(chat.pending.first?.id)
        let stale = Task { await chat.deliver(pendingID, in: store) }
        await gate.waitUntilEntered()

        backend.simulateBlock(by: MockFixtures.sam.id)
        await store.refresh()
        chat.synchronize(in: store)
        #expect(store.game(going)?.isGoing != true)
        #expect(chat.messages.isEmpty)
        #expect(chat.pending.isEmpty)
        #expect(chat.rows(in: store).isEmpty)
        gate.open()
        await stale.value
        #expect(chat.messages.isEmpty)
        #expect(chat.pending.isEmpty)

        chat.draft = "Still there?"
        chat.send(in: store)
        #expect(chat.pending.isEmpty)
    }
}
