import Foundation
import Testing
@testable import masUNO

/// Every live repository against `masuno-dev`, signed in as the QA account (B7, E24). Skipped unless
/// `MASUNO_LIVE_PASSWORD` is set, so CI and normal runs never touch the network:
///
///     TEST_RUNNER_MASUNO_LIVE_PASSWORD=… xcodebuild test … -only-testing:masUNOTests/LiveIntegrationTests
///
/// It writes to dev: joins and leaves a demo game, posts and cancels a game, blocks and unblocks a
/// demo host, files one report, and leaves one chat message in a demo game. The chat test needs
/// `chat_enabled` on in dev. Debug's keys in `Config.xcconfig` must point at dev. It doesn't sign
/// out: a global sign-out would end the next test's session too.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MASUNO_LIVE_PASSWORD"] != nil))
struct LiveIntegrationTests {
    private static let email = "official.masuno.app+qa1@gmail.com"

    private func signedIn() async throws -> LiveBackend {
        let live = try #require(LiveBackend.make(), "Config.xcconfig has no Debug keys")
        let password = try #require(ProcessInfo.processInfo.environment["MASUNO_LIVE_PASSWORD"])
        try await live.auth.signIn(email: Self.email, password: password)
        if live.auth.state == .needsProfile {
            try await live.auth.completeProfile(ProfileInput(
                firstName: "Quinn", lastName: "Tester", gradYear: 2027, interests: [Activity.builtIn[0]]
            ))
        }
        if live.auth.state == .needsGuidelines { try await live.auth.acceptGuidelines() }
        guard case .signedIn = live.auth.state else {
            Issue.record("Not signed in: \(live.auth.state)")
            throw DomainError.notAuthenticated
        }
        return live
    }

    @Test func referenceDataAndProfile() async throws {
        let live = try await signedIn()

        #expect(try await live.catalog.fetchActivities().map(\.slug).contains("basketball"))
        #expect(try await live.catalog.fetchUniversities().contains { $0.shortName == "Tec" })

        let profile = try #require(try await live.profiles.fetchMyProfile())
        #expect(profile.university.shortName == "Demo", "Allowlisted accounts land on the demo campus")
        #expect(!profile.interests.isEmpty)

        var input = ProfileInput(firstName: profile.firstName, lastName: profile.lastName, gradYear: profile.gradYear, interests: profile.interests)
        input.gradYear = profile.gradYear == 2027 ? 2028 : 2027
        let edited = try await live.profiles.updateProfile(input)
        #expect(edited.gradYear == input.gradYear)
        #expect(edited.university.id == profile.university.id, "Edits never change the campus")
    }

    @Test func mapJoinLeaveAndGroupChat() async throws {
        let live = try await signedIn()

        let map = try await live.games.fetchMapGames()
        #expect(!map.isEmpty, "The demo campus should have games from the daily refresh")
        #expect(map.allSatisfy { !$0.isCancelled && !$0.isFull && !$0.hasEnded() })
        let sorted = map.map { $0.repostedAt ?? $0.createdAt }
        #expect(sorted == sorted.sorted(by: >), "Newest bump first")

        let target = try #require(map.first { $0.myRole == nil && $0.spotsLeft > 0 })
        #expect(try await live.games.fetchGame(id: target.id).id == target.id)
        #expect(try await live.games.fetchGames(ids: [target.id, UUID()]).map(\.id) == [target.id])
        #expect(try await live.games.fetchGames(ids: []).isEmpty)
        await #expect(throws: DomainError.notFound) { try await live.games.fetchGame(id: UUID()) }

        let joined = try await live.games.joinGame(id: target.id)
        #expect(joined.myRole == .player)
        #expect(joined.goingCount == target.goingCount + 1)
        #expect(try await live.games.joinGame(id: target.id).goingCount == joined.goingCount, "Joining is idempotent")
        #expect(try await live.games.fetchMyGames().contains { $0.id == target.id })

        let who = try await live.games.fetchAttendees(gameID: target.id)
        #expect(who.first?.role == .host)
        guard case .signedIn(let me) = live.auth.state else { return }
        #expect(who.contains { $0.id == me && $0.role == .player })
        #expect(try await live.games.fetchActivity(gameID: target.id).contains { $0.kind == .joined })

        let left = try await live.games.leaveGame(id: target.id)
        #expect(left.myRole == nil)
        #expect(left.goingCount == target.goingCount)
    }

    @Test func hostEditAndCancel() async throws {
        let live = try await signedIn()
        let campus = try #require(try await live.profiles.fetchMyProfile()).university

        let draft = GameDraft(
            activity: Activity.builtIn[2], title: "B7 integration test", startsAt: .now.addingTimeInterval(3 * 3600),
            durationMinutes: 60, capacity: 6, notes: nil,
            place: Place(name: "Test field", address: "Demo campus", latitude: campus.centerLatitude, longitude: campus.centerLongitude),
            meetPoint: nil
        )
        let created = try await live.games.createGame(draft)
        #expect(created.myRole == .host)
        #expect(created.goingCount == 1)
        #expect(created.activity.slug == "soccer")
        #expect(abs(created.startsAt.timeIntervalSince(draft.startsAt)) < 0.001)

        var edit = GameDraft(created)
        edit.meetPoint = "North gate"
        let updated = try await live.games.updateGame(id: created.id, edit)
        #expect(updated.meetPoint == "North gate")
        #expect(updated.materialChangeAt != nil)

        await #expect(throws: DomainError.notAllowed) { try await live.games.leaveGame(id: created.id) }
        var bad = edit
        bad.title = "pinche juego"
        await #expect(throws: DomainError.invalidText) { try await live.games.updateGame(id: created.id, bad) }

        let cancelled = try await live.games.cancelGame(id: created.id)
        #expect(cancelled.isCancelled)
        #expect(try await live.games.cancelGame(id: created.id).isCancelled, "Cancel is idempotent")
        #expect(try await live.games.fetchActivity(gameID: created.id).map(\.kind) == [.created, .meetPointUpdated, .cancelled])
    }

    @Test func blockUnblockAndReport() async throws {
        let live = try await signedIn()

        let game = try #require(try await live.games.fetchMapGames().first)
        let host = game.host
        try await live.safety.block(userID: host.id)
        #expect(try await live.safety.fetchBlockedPeople().first?.id == host.id)
        #expect(!(try await live.games.fetchMapGames().contains { $0.host.id == host.id }), "RLS hides a blocked host's games")
        await #expect(throws: DomainError.notFound) { try await live.games.fetchGame(id: game.id) }

        try await live.safety.unblock(userID: host.id)
        #expect(!(try await live.safety.fetchBlockedPeople().contains { $0.id == host.id }))
        #expect(try await live.games.fetchGame(id: game.id).id == game.id)

        try await live.safety.report(.game(game.id), reason: .other, note: "B7 integration test, please ignore")
        await #expect(throws: DomainError.invalidInput) {
            try await live.safety.block(userID: try #require(try await live.profiles.fetchMyProfile()).id)
        }
    }

    /// E26 + B20 end to end: consent, send, retry, read back, the private Realtime channel, and the
    /// rules for people outside the game.
    @Test func groupChatMessaging() async throws {
        let live = try await signedIn()
        try #require(try await live.catalog.fetchAppConfig().chatEnabled, "Turn chat_enabled on in masuno-dev (supabase/README.md)")

        let map = try await live.games.fetchMapGames()
        let target = try #require(map.first { $0.myRole == nil && $0.spotsLeft > 0 })
        await #expect(throws: DomainError.notAllowed) {
            try await live.chat.sendMessage(gameID: target.id, body: "Not in the game", clientID: UUID())
        }
        #expect(try await live.chat.fetchMessages(gameID: target.id, before: nil, limit: 50).isEmpty, "Outsiders can't read a chat")

        _ = try await live.games.joinGame(id: target.id)
        try await live.chat.acceptChatRules()
        #expect(try #require(try await live.profiles.fetchMyProfile()).chatRulesAcceptedAt != nil)

        // Listen first, and give the channel a few seconds to join before posting.
        let heard = Task { () -> ChatUpdate? in
            for await update in live.chat.updates(gameID: target.id) where update == .message { return update }
            return nil
        }
        try await Task.sleep(for: .seconds(5))

        let clientID = UUID()
        let body = "E26 integration test \(clientID.uuidString.prefix(8))"
        let sent = try await live.chat.sendMessage(gameID: target.id, body: "  \(body)  ", clientID: clientID)
        #expect(sent.body == body)
        #expect(sent.clientID == clientID)
        #expect(try await live.chat.sendMessage(gameID: target.id, body: body, clientID: clientID).id == sent.id, "A retry doesn't post twice")

        let giveUp = Task {
            try await Task.sleep(for: .seconds(10))
            heard.cancel()
        }
        #expect(await heard.value == .message, "No ping arrived on the game's private channel")
        giveUp.cancel()

        #expect(try await live.chat.fetchMessages(gameID: target.id, before: nil, limit: 50).contains { $0.id == sent.id })
        #expect(try await live.chat.fetchMessages(gameID: target.id, since: sent.createdAt.addingTimeInterval(-5)).contains { $0.id == sent.id })
        #expect(try await live.chat.fetchUnreadCounts()[target.id] == nil, "Your own messages aren't new")
        try await live.chat.markRead(gameID: target.id)

        await #expect(throws: DomainError.invalidText) {
            try await live.chat.sendMessage(gameID: target.id, body: "pinche juego", clientID: UUID())
        }
        await #expect(throws: DomainError.invalidText) {
            try await live.chat.sendMessage(gameID: target.id, body: "mira https://example.com", clientID: UUID())
        }
        await #expect(throws: DomainError.invalidInput) {
            try await live.safety.report(.message(sent.id), reason: .other, note: nil)
        }

        _ = try await live.games.leaveGame(id: target.id)
        #expect(try await live.chat.fetchMessages(gameID: target.id, before: nil, limit: 50).isEmpty, "Leaving closes the chat")
    }
}
