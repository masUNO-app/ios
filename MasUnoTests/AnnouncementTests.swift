import Foundation
import Testing
@testable import masUNO

/// What VoiceOver says for results that don't move focus (A11Y-03), and how long toasts stay (A11Y-21).
@MainActor
struct AnnouncementTests {
    let world = MockFixtures.world(now: .now)

    private func game(_ id: UUID) throws -> Game {
        try #require(world.games.first { $0.id == id })
    }

    // MARK: Map search

    @Test func searchResultsSayTheTitleAndHowMany() throws {
        let map = EventMapViewModel()
        let hoops = try game(MockFixtures.GameID.open)
        #expect(map.resultsAnnouncement(for: [hoops]) == "Basketball near you, 1 game")
        let mixed = [hoops, try game(MockFixtures.GameID.going), try game(MockFixtures.GameID.full)]
        #expect(map.resultsAnnouncement(for: mixed) == "Games near you, 3 games")
        #expect(map.resultsAnnouncement(for: []) == "No games match that search")
    }

    @Test func theGameCountIsPluralInSpanish() {
        let settings = LanguageSettings(defaults: UserDefaults(suiteName: "AnnouncementTests.\(UUID().uuidString)")!, preferredLanguages: ["es-MX"])
        let one = 1, three = 3
        #expect(String(localized: "\(one) games", bundle: settings.bundle, locale: settings.locale) == "1 partido")
        #expect(String(localized: "\(three) games", bundle: settings.bundle, locale: settings.locale) == "3 partidos")
    }

    // MARK: Joining

    @Test func joiningSaysTheNewHeadline() throws {
        let detail = EventDetailViewModel(eventID: MockFixtures.GameID.going)
        let going = try game(MockFixtures.GameID.going)
        #expect(detail.joinAnnouncement(from: .open, to: .going, for: going) == "You're in!")
    }

    @Test func otherChangesAreNotJoins() throws {
        let detail = EventDetailViewModel(eventID: MockFixtures.GameID.open)
        let open = try game(MockFixtures.GameID.open)
        #expect(detail.joinAnnouncement(from: .going, to: .open, for: open) == nil)
        #expect(detail.joinAnnouncement(from: .open, to: .full, for: open) == nil)
        #expect(detail.joinAnnouncement(from: .going, to: .cancelled, for: open) == nil)
    }

    // MARK: Chat sends

    private func pending(_ error: DomainError? = nil, id: UUID = UUID()) -> ChatViewModel.Pending {
        .init(id: id, body: "On my way", sentAt: .now, error: error)
    }

    @Test func aSendThatJustFailedIsSaidOnce() {
        let sending = pending()
        var failed = sending
        failed.error = .rateLimited
        #expect(ChatViewModel.newFailure(from: [sending], to: [failed]) == .rateLimited)
        // Still failed on the next change (another message sent): not news.
        #expect(ChatViewModel.newFailure(from: [failed], to: [failed, pending()]) == nil)
        #expect(ChatViewModel.newFailure(from: [], to: [sending]) == nil)
    }

    @Test func aRetryThatFailsAgainIsSaidAgain() {
        let id = UUID()
        #expect(ChatViewModel.newFailure(from: [pending(id: id)], to: [pending(.offline, id: id)]) == .offline)
    }

    @Test func severalFailingTogetherAreSaidAsTheLatest() {
        let first = pending(), second = pending()
        var firstFailed = first, secondFailed = second
        firstFailed.error = .offline
        secondFailed.error = .rateLimited
        #expect(ChatViewModel.newFailure(from: [first, second], to: [firstFailed, secondFailed]) == .rateLimited)
    }

    @Test func aLostConnectionOnlyAsksForARetry() {
        #expect(ChatViewModel.failureText(.offline) == "Not sent · Tap to retry")
        #expect(ChatViewModel.failureText(.unknown("send_outcome_unknown")) == "Not sent · Tap to retry")
        #expect(ChatViewModel.failureText(.rateLimited) == "Not sent · \(DomainError.rateLimited.message)")
    }

    // MARK: Chat messages

    private let me = PersonSummary(id: UUID(), firstName: "Ethan", lastInitial: "W", gradYear: 0)
    private let nina = PersonSummary(id: UUID(), firstName: "Nina", lastInitial: "P", gradYear: 0)

    private func message(from sender: PersonSummary, at offset: TimeInterval) -> ChatMessage {
        ChatMessage(id: UUID(), gameID: UUID(), sender: sender, body: "On my way", clientID: UUID(),
                    createdAt: Date(timeIntervalSinceReferenceDate: offset))
    }

    @Test func theFirstMessageIntoAnEmptyChatIsSaid() {
        let first = message(from: nina, at: 0)
        #expect(GroupChatView.announces(first, after: nil, shownLatest: false, loadedEmpty: true, myID: me.id))
        #expect(!GroupChatView.announces(message(from: me, at: 0), after: nil, shownLatest: true, loadedEmpty: true, myID: me.id))
    }

    @Test func theFirstPageIsNotSaid() {
        // A chat that loaded with messages, or hasn't loaded yet.
        #expect(!GroupChatView.announces(message(from: nina, at: 0), after: nil, shownLatest: true, loadedEmpty: false, myID: me.id))
    }

    @Test func onlyNewerMessagesFromOthersAreSaid() {
        let old = message(from: nina, at: 0)
        #expect(GroupChatView.announces(message(from: nina, at: 10), after: old, shownLatest: true, loadedEmpty: false, myID: me.id))
        #expect(!GroupChatView.announces(message(from: me, at: 10), after: old, shownLatest: true, loadedEmpty: false, myID: me.id))
        // An older message back at the end after someone is blocked.
        #expect(!GroupChatView.announces(message(from: nina, at: -10), after: old, shownLatest: true, loadedEmpty: false, myID: me.id))
        #expect(!GroupChatView.announces(message(from: nina, at: 10), after: old, shownLatest: false, loadedEmpty: false, myID: me.id))
    }

    // MARK: Toasts

    @Test func toastsStayLongerForVoiceOverAndLargeText() {
        #expect(NoticeBanner.duration(voiceOver: false, typeSize: .large) == .seconds(4))
        #expect(NoticeBanner.duration(voiceOver: false, typeSize: .xxxLarge) == .seconds(4))
        #expect(NoticeBanner.duration(voiceOver: true, typeSize: .large) == .seconds(10))
        #expect(NoticeBanner.duration(voiceOver: false, typeSize: .accessibility1) == .seconds(10))
    }
}
