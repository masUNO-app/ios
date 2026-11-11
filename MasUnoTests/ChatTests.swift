import Foundation
import Testing
@testable import MasUno

/// The mock follows `send_message` and friends (`docs/API.md`, Group chat), so the screen behaves the
/// same on `masuno-dev`.
@MainActor
struct MockChatRulesTests {
    let backend = MockBackend()
    let going = MockFixtures.GameID.going

    @Test func membersReadAndPost() async throws {
        let before = try await backend.fetchMessages(gameID: going, before: nil, limit: 50)
        let sent = try await backend.sendMessage(gameID: going, body: "  On my way  ", clientID: UUID())
        #expect(sent.body == "On my way")
        #expect(sent.sender.id == backend.me.id)
        #expect(try await backend.fetchMessages(gameID: going, before: nil, limit: 50).count == before.count + 1)
    }

    @Test func outsidersCanNeitherReadNorPost() async throws {
        let open = MockFixtures.GameID.open
        backend.receiveMessage(from: MockFixtures.alex, in: open, body: "Anyone bringing a ball?")
        #expect(try await backend.fetchMessages(gameID: open, before: nil, limit: 50).isEmpty)
        await #expect(throws: DomainError.notAllowed) {
            try await backend.sendMessage(gameID: open, body: "Me", clientID: UUID())
        }
    }

    @Test func retryWithTheSameClientIDPostsOnce() async throws {
        let clientID = UUID()
        let first = try await backend.sendMessage(gameID: going, body: "Hi", clientID: clientID)
        let again = try await backend.sendMessage(gameID: going, body: "Hi", clientID: clientID)
        #expect(first.id == again.id)
    }

    @Test func rulesComeBeforeTheFirstMessage() async throws {
        backend.resetChatRules()
        await #expect(throws: DomainError.chatRulesRequired) {
            try await backend.sendMessage(gameID: going, body: "Hi", clientID: UUID())
        }
        try await backend.acceptChatRules()
        _ = try await backend.sendMessage(gameID: going, body: "Hi", clientID: UUID())
    }

    @Test func switchedOffChatRefusesMessages() async throws {
        backend.chatEnabled = false
        #expect(try await backend.fetchAppConfig().chatEnabled == false)
        await #expect(throws: DomainError.chatDisabled) {
            try await backend.sendMessage(gameID: going, body: "Hi", clientID: UUID())
        }
    }

    @Test func textFilterLinksAndLengthApply() async throws {
        for body in ["pinche partido", "see https://example.com", "   ", String(repeating: "a", count: 1001)] {
            await #expect(throws: DomainError.invalidText) {
                try await backend.sendMessage(gameID: going, body: body, clientID: UUID())
            }
        }
    }

    @Test func chatClosesOnCancelAndADayAfterTheGame() async throws {
        let hosting = MockFixtures.GameID.hosting
        _ = try await backend.cancelGame(id: hosting)
        await #expect(throws: DomainError.cancelled) {
            try await backend.sendMessage(gameID: hosting, body: "Sorry all", clientID: UUID())
        }

        // The fixture ended 25 hours ago. Two hours earlier, its chat was still open.
        let ended = MockFixtures.GameID.ended
        backend.now = backend.now.addingTimeInterval(-2 * 3600)
        _ = try await backend.sendMessage(gameID: ended, body: "Good game", clientID: UUID())
        backend.now = backend.now.addingTimeInterval(2 * 3600)
        await #expect(throws: DomainError.ended) {
            try await backend.sendMessage(gameID: ended, body: "Again next week?", clientID: UUID())
        }
    }

    @Test func twentyMessagesAMinute() async throws {
        for index in 1...20 {
            _ = try await backend.sendMessage(gameID: going, body: "Message \(index)", clientID: UUID())
        }
        await #expect(throws: DomainError.rateLimited) {
            try await backend.sendMessage(gameID: going, body: "One more", clientID: UUID())
        }
        backend.now = backend.now.addingTimeInterval(61)
        _ = try await backend.sendMessage(gameID: going, body: "One more", clientID: UUID())
    }

    @Test func unreadCountsSkipYourOwnAndClearOnRead() async throws {
        try await backend.markRead(gameID: going)
        #expect(try await backend.fetchUnreadCounts()[going] == nil)
        backend.now = backend.now.addingTimeInterval(60)
        _ = try await backend.sendMessage(gameID: going, body: "Mine", clientID: UUID())
        backend.receiveMessage(from: MockFixtures.sam, in: going, body: "Theirs")
        #expect(try await backend.fetchUnreadCounts()[going] == 1)
        backend.now = backend.now.addingTimeInterval(60)
        try await backend.markRead(gameID: going)
        #expect(try await backend.fetchUnreadCounts()[going] == nil)
    }

    @Test func blockedSendersAreHidden() async throws {
        try await backend.block(userID: MockFixtures.maya.id)
        let messages = try await backend.fetchMessages(gameID: going, before: nil, limit: 50)
        #expect(!messages.contains { $0.sender.id == MockFixtures.maya.id })
        #expect(messages.contains { $0.sender.id == MockFixtures.sam.id })
    }

    @Test func messagesCanBeReportedButNotYourOwn() async throws {
        let messages = try await backend.fetchMessages(gameID: going, before: nil, limit: 50)
        let theirs = try #require(messages.first { $0.sender.id == MockFixtures.sam.id })
        let mine = try #require(messages.first { $0.sender.id == backend.me.id })
        try await backend.report(.message(theirs.id), reason: .harassment, note: nil)
        #expect(backend.reports.count == 1)
        await #expect(throws: DomainError.invalidInput) {
            try await backend.report(.message(mine.id), reason: .spam, note: nil)
        }
    }

    @Test func someoneElsePostingReachesListeners() async throws {
        var updates = backend.updates(gameID: going).makeAsyncIterator()
        // Give the stream a moment to attach before the other phone posts.
        try await Task.sleep(for: .milliseconds(20))
        backend.receiveMessage(from: MockFixtures.sam, in: going, body: "Here")
        #expect(await updates.next() == .message)
    }
}

/// E26: the timeline, optimistic sends with retry, live updates and unread counts.
@MainActor
struct ChatViewModelTests {
    let backend = MockBackend()
    let store: GameStore
    let going = MockFixtures.GameID.going
    let chat: ChatViewModel

    init() async {
        store = GameStore(
            games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend,
            defaults: UserDefaults(suiteName: "ChatViewModelTests.\(UUID().uuidString)")!
        )
        store.isChatEnabled = true
        await store.load()
        chat = ChatViewModel(gameID: going)
    }

    private func bodies() -> [String] {
        chat.rows(in: store).compactMap { row in
            switch row {
            case .message(let message, _): message.body
            case .pending(let pending): pending.body
            case .day, .activity: nil
            }
        }
    }

    @Test func openingLoadsTheTimelineAndMarksItRead() async throws {
        #expect(store.unreadCount(going) == 3)
        await chat.reload(in: store)
        await store.loadActivity(going)
        #expect(chat.state == .loaded)
        #expect(chat.messages.count == 4)
        #expect(store.unreadCount(going) == 0)

        let rows = chat.rows(in: store)
        guard case .day = rows.first else {
            Issue.record("The timeline starts with a day row")
            return
        }
        #expect(rows.contains { if case .activity = $0 { true } else { false } })
        // System rows from three hours ago come before this hour's messages.
        let firstMessage = rows.firstIndex { if case .message = $0 { true } else { false } }
        let lastActivity = rows.lastIndex { if case .activity = $0 { true } else { false } }
        #expect(try #require(lastActivity) < #require(firstMessage))
    }

    @Test func consecutiveMessagesShareOneNameLine() async {
        await chat.reload(in: store)
        backend.receiveMessage(from: MockFixtures.sam, in: going, body: "First")
        backend.receiveMessage(from: MockFixtures.sam, in: going, body: "Second")
        await chat.fetchNew(in: store)
        let shown = chat.rows(in: store).compactMap { row -> Bool? in
            if case .message(let message, let showsSender) = row, ["First", "Second"].contains(message.body) { return showsSender }
            return nil
        }
        #expect(shown == [true, false])
    }

    @Test func sendShowsBeforeTheServerAnswers() async {
        await chat.reload(in: store)
        backend.latency = .milliseconds(100)
        chat.draft = "  Running 5 late  "
        chat.send(in: store)
        #expect(chat.draft.isEmpty)
        #expect(chat.pending.map(\.body) == ["Running 5 late"])
        #expect(bodies().last == "Running 5 late")
        await chat.deliver(chat.pending[0].id, in: store)
        #expect(chat.pending.isEmpty)
        #expect(chat.messages.last?.body == "Running 5 late")
        #expect(bodies().filter { $0 == "Running 5 late" }.count == 1)
    }

    @Test func failedSendStaysWithARetryThatPostsOnce() async throws {
        await chat.reload(in: store)
        chat.draft = "Is the court free?"
        chat.send(in: store)
        let id = try #require(chat.pending.first?.id)
        backend.nextError = .offline
        await chat.deliver(id, in: store)
        #expect(chat.pending.first?.error == .offline)
        #expect(store.isOffline)

        await chat.deliver(id, in: store)
        await chat.deliver(id, in: store)
        #expect(chat.pending.isEmpty)
        #expect(chat.messages.filter { $0.body == "Is the court free?" }.count == 1)
    }

    @Test func unfriendlyTextAndLinksNeverLeaveTheComposer() async {
        chat.draft = "pinche cancha"
        chat.send(in: store)
        #expect(chat.draftError == TextFilter.message)
        chat.draft = "check www.example.com"
        chat.send(in: store)
        #expect(chat.draftError == TextFilter.linkMessage)
        #expect(chat.pending.isEmpty)
        #expect(chat.draft == "check www.example.com")
    }

    @Test func emptyDraftDoesNothing() {
        chat.draft = "  \n "
        #expect(!chat.canSend)
        chat.send(in: store)
        #expect(chat.pending.isEmpty)
    }

    @Test func firstMessageAsksForTheRulesThenSends() async throws {
        backend.resetChatRules()
        await store.load()
        await chat.reload(in: store)
        chat.draft = "Hi all"
        chat.send(in: store)
        let id = try #require(chat.pending.first?.id)
        await chat.deliver(id, in: store)
        #expect(chat.asksForRules)
        #expect(chat.pending.first?.error == .chatRulesRequired)

        await chat.acceptRules(in: store)
        #expect(!chat.asksForRules)
        #expect(store.profile?.chatRulesAcceptedAt != nil)
        await chat.deliver(id, in: store)
        #expect(chat.pending.isEmpty)
        #expect(chat.messages.last?.body == "Hi all")
    }

    @Test func liveMessagesArriveWithoutARefresh() async throws {
        let listening = Task { await chat.open(in: store) }
        try await waitUntil { chat.state == .loaded }
        // Give the channel a moment to attach before the other phone posts.
        try await Task.sleep(for: .milliseconds(50))
        backend.receiveMessage(from: MockFixtures.nina, in: going, body: "Saving you a spot")
        try await waitUntil { chat.messages.last?.body == "Saving you a spot" }
        #expect(store.unreadCount(going) == 0)
        listening.cancel()
    }

    @Test func pollingCatchesUpWhenTheChannelIsDown() async throws {
        await chat.reload(in: store)
        let polling = Task { await chat.poll(in: store, every: .milliseconds(20)) }
        backend.receiveMessage(from: MockFixtures.nina, in: going, body: "Anyone there?")
        try await waitUntil { chat.messages.last?.body == "Anyone there?" }
        polling.cancel()
    }

    @Test func blockingHidesTheirMessagesRightAway() async {
        await chat.reload(in: store)
        #expect(bodies().contains("I can bring a second ball"))
        backend.latency = .milliseconds(100)
        let blocking = Task { await store.block(MockFixtures.maya) }
        await Task.yield()
        #expect(!bodies().contains("I can bring a second ball"))
        await blocking.value
    }

    @Test func olderMessagesLoadAPageAtATime() async {
        for index in 1...60 {
            backend.now = backend.now.addingTimeInterval(1)
            backend.receiveMessage(from: MockFixtures.sam, in: going, body: "Message \(index)")
        }
        await chat.reload(in: store)
        #expect(chat.messages.count == ChatViewModel.pageSize)
        #expect(chat.hasOlder)
        #expect(chat.messages.last?.body == "Message 60")
        await chat.loadOlder(in: store)
        #expect(chat.messages.count == 64)
        #expect(!chat.hasOlder)
        #expect(Set(chat.messages.map(\.id)).count == 64)
    }

    @Test func failedFirstLoadOffersARetry() async {
        backend.nextError = .offline
        await chat.reload(in: store)
        #expect(chat.state == .failed(.offline))
        await chat.reload(in: store)
        #expect(chat.state == .loaded)
    }

    @Test func meCardsCountNewMessages() async {
        await store.markChatRead(going)
        backend.now = backend.now.addingTimeInterval(60)
        backend.receiveMessage(from: MockFixtures.sam, in: going, body: "New one")
        await store.refresh()
        #expect(store.unreadCount(going) == 1)
        store.isChatEnabled = false
        #expect(store.unreadCount(going) == 0)
    }

    @Test func chatIsOpenUntilADayAfterTheGame() throws {
        let game = try #require(store.game(going))
        #expect(game.isChatOpen(now: game.endsAt.addingTimeInterval(23 * 3600)))
        #expect(!game.isChatOpen(now: game.endsAt.addingTimeInterval(25 * 3600)))
        #expect(store.game(MockFixtures.GameID.open)?.isChatOpen() == false)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition())
    }
}

/// What the chat tables and RPCs send and take (`docs/API.md`, Group chat).
@MainActor
struct LiveChatContractTests {
    @Test func gameMessageRowBecomesAMessage() throws {
        let json = """
        [{"id":"8866dace-f67a-4d74-a2e9-f2ae6fcf2a66","event_id":"9e6ead38-803f-4d9a-a023-2ee54b5f2946",
          "sender_id":"b0000000-0000-4000-8000-00000000000b","sender_first_name":"Bruno","sender_last_initial":"Y",
          "sender_grad_year":2026,"body":"Llego en 10","client_id":"c145b8a9-4646-4694-bf35-5f4aa76d62d0",
          "created_at":"2026-11-10T19:48:49.015403-05:00"}]
        """
        let message = try #require(try JSONDecoder().decode([GameMessageRow].self, from: Data(json.utf8)).first).message
        #expect(message.sender.displayName == "Bruno Y.")
        #expect(message.body == "Llego en 10")
        #expect(message.clientID == UUID(uuidString: "c145b8a9-4646-4694-bf35-5f4aa76d62d0"))
        #expect(message.createdAt == ServerTime.date(from: "2026-11-11T00:48:49.015403Z"))
    }

    @Test func sendMessageSendsTheContractsParameters() throws {
        let params = SendMessageParams(gameID: UUID(), body: "Hola", clientID: UUID())
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any])
        #expect(Set(object.keys) == ["p_game_id", "p_body", "p_client_id"])
    }

    @Test func messageReportsGoToReportMessage() throws {
        let params = ReportParams(target: .message(UUID()), reason: .harassment, note: "  ")
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any])
        #expect(Set(object.keys) == ["p_message_id", "p_reason", "p_note"])
        #expect(object["p_note"] is NSNull)
    }

    @Test func channelNameMatchesTheServersLowercaseUUID() {
        let id = UUID(uuidString: "9E6EAD38-803F-4D9A-A023-2EE54B5F2946")!
        #expect(chatChannelName(gameID: id) == "game:9e6ead38-803f-4d9a-a023-2ee54b5f2946:chat")
    }

    @Test func chatIsOffUnlessTheServerSaysOn() throws {
        func config(_ json: String) throws -> AppConfig {
            AppConfig(rows: try JSONDecoder().decode([AppConfigRow].self, from: Data(json.utf8)))
        }
        #expect(!AppConfig.fallback.chatEnabled)
        #expect(try !config(#"[{"key":"support_email","value":"a@b.c"}]"#).chatEnabled)
        #expect(try !config(#"[{"key":"chat_enabled","value":false}]"#).chatEnabled)
        let on = try config(#"[{"key":"chat_enabled","value":true},{"key":"support_email","value":"a@b.c"}]"#)
        #expect(on.chatEnabled)
        #expect(on.supportEmail == "a@b.c")
    }

    @Test func myProfileCarriesChatConsentWhenTheServerHasIt() throws {
        let base = """
        "id":"a0000000-0000-4000-8000-00000000000a","first_name":"Alice","last_name":"Zamora","grad_year":2027,
        "university_id":"531a78f1-2cdf-479c-b692-7f8df08a4445","university_name":"Tec de Monterrey",
        "university_short_name":"Tec","university_email_domain":"tec.mx","center_lat":25.65,"center_lng":-100.29,
        "interests":["basketball"]
        """
        let activity = { (slug: String) in Activity.builtIn.first { $0.slug == slug } ?? Activity.builtIn[0] }
        let old = try JSONDecoder().decode(MyProfileRow.self, from: Data("{\(base)}".utf8))
        #expect(old.profile(activity: activity).chatRulesAcceptedAt == nil)
        let accepted = try JSONDecoder().decode(
            MyProfileRow.self, from: Data("{\(base),\"chat_rules_accepted_at\":\"2026-11-10T19:48:49.015403+00:00\"}".utf8)
        )
        #expect(accepted.profile(activity: activity).chatRulesAcceptedAt != nil)
    }

    @Test func chatErrorCodesTranslate() {
        #expect(DomainError(serverCode: "chat_rules_required") == .chatRulesRequired)
        #expect(DomainError(serverCode: "chat_disabled") == .chatDisabled)
        #expect(DomainError(serverCode: "rate_limited") == .rateLimited)
    }
}
