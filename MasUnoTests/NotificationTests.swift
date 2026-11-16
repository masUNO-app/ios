import Foundation
import Testing
@testable import masUNO

@MainActor
struct NotificationTests {
    @Test func gameLinkOpensTheGame() {
        let app = signedInApp()
        let id = UUID()
        app.handle(URL(string: "masuno://game/\(id.uuidString)")!)
        #expect(app.path == [.game(id)])
    }

    @Test func chatLinkOpensTheGameThenTheChat() {
        let app = signedInApp()
        let id = UUID()
        app.handle(URL(string: "masuno://game/\(id.uuidString)/chat")!)
        #expect(app.path == [.game(id), .chat(id)])
    }

    @Test func mapLinkClearsTheStackAndAsksForMySports() {
        let app = signedInApp()
        app.path = [.settings]
        app.handle(URL(string: "masuno://map")!)
        #expect(app.path.isEmpty)
        #expect(app.focusMapOnMySports)
    }

    @Test func aLinkBeforeSignInWaits() {
        let mock = MockBackend(state: .signedOut(expired: false))
        let app = AppViewModel(auth: mock, catalog: mock)
        let id = UUID()
        app.handle(URL(string: "masuno://game/\(id.uuidString)")!)
        #expect(app.path.isEmpty)
        #expect(app.pendingLink == URL(string: "masuno://game/\(id.uuidString)"))
    }

    @Test func payloadDecodesASpotAndAChat() throws {
        let spot: [String: Any] = [
            "kind": "spot_open",
            "game_id": "6F1C0000-0000-4000-8000-000000000001",
            "outbox_id": 4812,
            "place": ["name": "Courts", "lat": 25.65, "lng": -100.29],
        ]
        let decoded = try #require(NotificationPayload(userInfo: spot))
        #expect(decoded.kind == "spot_open")
        #expect(decoded.outboxID == 4812)
        #expect(decoded.routeURL()?.host() == "game")
        #expect(decoded.place?.lat == 25.65)

        let chat: [String: Any] = [
            "kind": "chat_message",
            "game_id": "6F1C0000-0000-4000-8000-000000000001",
            "game": ["title": "Sunday pickup soccer", "sport": "soccer"],
            "sender": ["id": "A21B0000-0000-4000-8000-000000000002", "name": "Maya C.", "initials": "MC"],
            "others": [["id": "C9D00000-0000-4000-8000-000000000003", "name": "Sam L."]],
            "body": "I'll bring the ball",
            "count": 1,
        ]
        let message = try #require(NotificationPayload(userInfo: chat))
        #expect(message.routeURL()?.absoluteString.hasSuffix("/chat") == true)
        #expect(message.sender?.initials == "MC")
        #expect(message.others.count == 1)
    }

    @Test func signupOpensNothingAndWinbackOpensTheMap() throws {
        let signup = try #require(NotificationPayload(userInfo: ["kind": "signup_approved"]))
        #expect(signup.routeURL() == nil)
        let winback = try #require(NotificationPayload(userInfo: ["kind": "winback"]))
        #expect(winback.routeURL()?.host() == "map")
    }

    @Test func theSamePersonGetsTheSameColorSlot() {
        let id = UUID()
        #expect(AvatarPalette.index(for: id) == AvatarPalette.index(for: id))
        #expect(AvatarPalette.people.count == 7)
        #expect(AvatarPalette.emoji(for: "soccer") == "⚽️")
    }

    private func signedInApp() -> AppViewModel {
        AppViewModel(auth: MockBackend(), catalog: MockBackend())
    }
}
