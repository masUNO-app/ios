import Foundation
import Intents
import Testing
@testable import masUNO

/// "@Maya C." in group chat (NOTIF §3.5): typing, picking, editing, highlighting and the push.
struct MentionParsingTests {
    let maya = MockFixtures.maya
    let mario = PersonSummary(id: UUID(), firstName: "Mario", lastInitial: "Z", gradYear: 2027)
    let angel = PersonSummary(id: UUID(), firstName: "Ángel", lastInitial: "R", gradYear: 2028)

    @Test func aQueryIsTheFirstNameTypedAfterAnAtAtTheEnd() {
        #expect(Mention.query(in: "@") == "")
        #expect(Mention.query(in: "Hi @Ma") == "Ma")
        #expect(Mention.query(in: "Hi\n@ma") == "ma")
        #expect(Mention.query(in: "Hi") == nil)
        #expect(Mention.query(in: "Hi @Maya C. ") == nil, "A space ends it")
        #expect(Mention.query(in: "mail me at a@b") == nil, "An @ inside a word is an email")
        #expect(Mention.query(in: "@@") == nil)
        #expect(Mention.query(in: "@" + String(repeating: "a", count: 31)) == nil)
    }

    @Test func suggestionsFilterByFirstNameIgnoringCaseAndAccents() {
        let people = [maya, mario, angel]
        #expect(Mention.suggestions(for: "", among: people).map(\.id) == people.map(\.id))
        #expect(Mention.suggestions(for: "ma", among: people).map(\.id) == [maya.id, mario.id])
        #expect(Mention.suggestions(for: "MAY", among: people).map(\.id) == [maya.id])
        #expect(Mention.suggestions(for: "ang", among: people).map(\.id) == [angel.id])
        #expect(Mention.suggestions(for: "C", among: people).isEmpty, "Only the first name matches")
    }

    @Test func pickingReplacesWhatWasTypedWithTheName() {
        var draft = MentionDraft()
        var text = "Bring water @Ma"
        draft.insert(maya, into: &text)
        #expect(text == "Bring water @Maya C. ")
        #expect(draft.ids == [maya.id])
        text += "and the ball @"
        draft.insert(maya, into: &text)
        #expect(text == "Bring water @Maya C. and the ball @Maya C. ")
        #expect(draft.ids == [maya.id], "The same person counts once")
    }

    @Test func pickingWithoutAQueryChangesNothing() {
        var draft = MentionDraft()
        var text = "Bring water"
        draft.insert(maya, into: &text)
        #expect(text == "Bring water")
        #expect(draft.ids.isEmpty)
    }

    @Test func deletingOrEditingTheNameDropsTheMention() {
        var draft = MentionDraft()
        var text = "@"
        draft.insert(maya, into: &text)
        text += "see you"
        draft.reconcile(with: text)
        #expect(draft.ids == [maya.id])

        draft.reconcile(with: "@Maya C see you")
        #expect(draft.ids.isEmpty, "Deleting a character drops it")

        text = "@"
        draft.insert(maya, into: &text)
        draft.reconcile(with: "@Mayo C. see you")
        #expect(draft.ids.isEmpty, "Editing the name drops it")

        text = "@"
        draft.insert(maya, into: &text)
        draft.reconcile(with: "")
        #expect(draft.ids.isEmpty, "Clearing the text drops it")
    }

    @Test func twoPeopleWithTheSameNameNeedTheNameTwice() {
        let otherMaya = PersonSummary(id: UUID(), firstName: "Maya", lastInitial: "C", gradYear: 2029)
        var draft = MentionDraft()
        var text = "@"
        draft.insert(maya, into: &text)
        text += "@"
        draft.insert(otherMaya, into: &text)
        #expect(draft.ids == [maya.id, otherMaya.id])
        draft.reconcile(with: "@Maya C. hi")
        #expect(draft.ids == [maya.id])
    }

    @Test func rangesMarkEachMentionAndYours() throws {
        let me = UUID()
        let body = "@Emilio G. and @Maya C. bring cones, @Emilio G. too. @Sam L. no"
        let names = [me: "Emilio G.", maya.id: "Maya C.", MockFixtures.sam.id: "Sam L."]
        let found = Mention.ranges(in: body, mentions: [me, maya.id], names: names, me: me)
        #expect(found.map { String(body[$0.range]) } == ["@Emilio G.", "@Maya C.", "@Emilio G."])
        #expect(found.map(\.isMe) == [true, false, true])
    }

    @Test func rangesSkipUnknownNamesAndOverlaps() {
        let short = PersonSummary(id: UUID(), firstName: "Ana", lastInitial: "M", gradYear: 2027)
        let body = "@Ana M. hi"
        #expect(Mention.ranges(in: body, mentions: [short.id], names: [:], me: nil).isEmpty, "A name nobody knows stays plain")
        let found = Mention.ranges(in: body, mentions: [short.id, maya.id], names: [short.id: "Ana M.", maya.id: "Ana M."], me: maya.id)
        #expect(found.count == 1, "Two identical names mark the text once")
        #expect(found.first?.isMe == true)
    }
}

/// Mentions in the composer, on the mock backend.
@MainActor
struct MentionComposerTests {
    let backend = MockBackend()
    let store: GameStore
    let going = MockFixtures.GameID.going
    let chat: ChatViewModel

    init() async {
        store = GameStore(
            games: backend, profiles: backend, safety: backend, chat: backend, catalog: backend,
            defaults: UserDefaults(suiteName: "MentionComposerTests.\(UUID().uuidString)")!
        )
        store.isChatEnabled = true
        await store.load()
        await store.loadAttendees(going)
        chat = ChatViewModel(gameID: going)
    }

    @Test func suggestionsAreTheGamesPeopleButYou() async {
        await chat.reload(in: store)
        #expect(chat.mentionSuggestions(in: store).isEmpty, "Nothing until an @")
        chat.draft = "@"
        let everyone = chat.mentionSuggestions(in: store)
        #expect(Set(everyone.map(\.id)) == [MockFixtures.sam.id, MockFixtures.nina.id, MockFixtures.maya.id, MockFixtures.priya.id])
        #expect(everyone.first?.id == MockFixtures.sam.id, "The host comes first")
        chat.draft = "@ni"
        #expect(chat.mentionSuggestions(in: store).map(\.id) == [MockFixtures.nina.id])
    }

    @Test func blockedPeopleAreNotSuggested() async {
        await chat.reload(in: store)
        await store.block(MockFixtures.maya)
        chat.draft = "@M"
        #expect(chat.mentionSuggestions(in: store).isEmpty)
    }

    @Test func aPickedMentionIsSent() async throws {
        await chat.reload(in: store)
        chat.draft = "Courts are free @Ma"
        chat.mention(MockFixtures.maya)
        chat.draft += "come early"
        chat.draftDidChange()
        #expect(chat.mentions.ids == [MockFixtures.maya.id])
        chat.send(in: store)
        #expect(chat.mentions.ids.isEmpty, "Sending starts a new draft")
        #expect(chat.pending.first?.mentions == [MockFixtures.maya.id])
        await chat.deliver(try #require(chat.pending.first).id, in: store)
        let sent = try #require(chat.messages.last)
        #expect(sent.body == "Courts are free @Maya C. come early")
        #expect(sent.mentions == [MockFixtures.maya.id])
    }

    @Test func anEditedMentionIsNotSent() async throws {
        await chat.reload(in: store)
        chat.draft = "@"
        chat.mention(MockFixtures.maya)
        chat.draft = "@Maya come early"
        chat.draftDidChange()
        chat.send(in: store)
        await chat.deliver(try #require(chat.pending.first).id, in: store)
        #expect(try #require(chat.messages.last).mentions.isEmpty)
    }

    @Test func theMockKeepsOnlyWhatTheServerWould() async throws {
        let sent = try await backend.sendMessage(
            gameID: going, body: "@Maya C. @Sam L. @Alex R. @Emilio G.", clientID: UUID(),
            mentions: [MockFixtures.maya.id, MockFixtures.maya.id, MockFixtures.alex.id, backend.me.id,
                       MockFixtures.nina.id, MockFixtures.sam.id]
        )
        // Alex isn't in the game, Emilio is you, Nina isn't named in the text.
        #expect(sent.mentions == [MockFixtures.maya.id, MockFixtures.sam.id])
    }

    @Test func theMockChatHasAMessageMentioningYou() async throws {
        let messages = try await backend.fetchMessages(gameID: going, before: nil, limit: 50)
        let mention = try #require(messages.first { $0.mentions.contains(backend.me.id) })
        #expect(mention.body.contains(Mention.token(for: backend.me)))
    }
}

/// `send_message`'s new parameter and `game_messages`'s new column (`docs/API.md`, Group chat).
struct MentionContractTests {
    @Test func mentionsAreSentOnlyWhenThereAreSome() throws {
        let none = SendMessageParams(gameID: UUID(), body: "Hola", clientID: UUID())
        let plain = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(none)) as? [String: Any])
        #expect(Set(plain.keys) == ["p_game_id", "p_body", "p_client_id"], "Older servers take three parameters")

        let id = UUID(uuidString: "b0000000-0000-4000-8000-00000000000b")!
        let some = SendMessageParams(gameID: UUID(), body: "@Bruno Y. hola", clientID: UUID(), mentions: [id])
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(some)) as? [String: Any])
        #expect(Set(object.keys) == ["p_game_id", "p_body", "p_client_id", "p_mentions"])
        #expect((object["p_mentions"] as? [String])?.map { $0.lowercased() } == [id.uuidString.lowercased()])
    }

    @Test func messageRowsReadMentionsAndToleratePreMentionServers() throws {
        func row(_ extra: String) throws -> ChatMessage {
            let json = """
            [{"id":"8866dace-f67a-4d74-a2e9-f2ae6fcf2a66","event_id":"9e6ead38-803f-4d9a-a023-2ee54b5f2946",
              "sender_id":"b0000000-0000-4000-8000-00000000000b","sender_first_name":"Bruno","sender_last_initial":"Y",
              "sender_grad_year":2026,"body":"@Alice Z. llego en 10","client_id":"c145b8a9-4646-4694-bf35-5f4aa76d62d0",
              "created_at":"2026-11-10T19:48:49.015403-05:00"\(extra)}]
            """
            return try #require(try JSONDecoder().decode([GameMessageRow].self, from: Data(json.utf8)).first).message
        }
        #expect(try row(#","mentions":["a0000000-0000-4000-8000-00000000000a"]"#).mentions
            == [UUID(uuidString: "a0000000-0000-4000-8000-00000000000a")!])
        #expect(try row("").mentions.isEmpty)
    }
}

/// The extension's side: a mention push decodes, and asks iOS to treat it as one.
struct MentionNotificationTests {
    private func sample() throws -> [AnyHashable: Any] {
        let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "masUNONotifications/Samples/chat_mention.apns")
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [AnyHashable: Any])
    }

    @Test func aMentionArrivesAsChatMarkedAsAMention() throws {
        let payload = try #require(NotificationPayload(userInfo: try sample()))
        #expect(payload.kind == "chat_message", "Builds from before mentions still draw and route it")
        #expect(payload.mention)
        #expect(payload.routeURL()?.absoluteString.hasSuffix("/chat") == true)
        #expect(payload.communicationBody(fallback: "") == "Mentioned you: @Sam L. can you bring the ball?")
    }

    @Test func aMentionSetsTheDonationMetadata() throws {
        let payload = try #require(NotificationPayload(userInfo: try sample()))
        let metadata = try #require(payload.donationMetadata(recipients: 2))
        #expect(metadata.mentionsCurrentUser)
        #expect(metadata.notifyRecipientAnyway)
        #expect(metadata.recipientCount == 2)
    }

    @Test func anOrdinaryMessageHasNoMetadata() throws {
        let payload = try #require(NotificationPayload(userInfo: ["kind": "chat_message", "body": "Hi"]))
        #expect(!payload.mention)
        #expect(payload.donationMetadata(recipients: 3) == nil)
    }

    @Test func theFlagRoundTripsOnlyWhenSet() throws {
        let plain = try JSONEncoder().encode(NotificationPayload(kind: "chat_message"))
        #expect(try #require(try JSONSerialization.jsonObject(with: plain) as? [String: Any])["mention"] == nil)
        let marked = try JSONEncoder().encode(NotificationPayload(kind: "chat_message", mention: true))
        #expect(try JSONDecoder().decode(NotificationPayload.self, from: marked).mention)
    }
}
