import Foundation
import Observation

/// In-memory source of truth. No backend yet — everything resets on launch.
/// Swapped for Emilio's `GameStore` once the live repositories land (B6, B7).
///
/// Model layer of the MVVM stack: holds the games and every domain action
/// that mutates them. Screen/presentation state lives in `ViewModels/`.
@Observable
final class EventStore {
    /// Every game the phone knows about, including ones hidden by blocks.
    private var allEvents: [SportsEvent]
    var profile: LegacyProfile
    /// People you blocked, newest first. Hidden immediately, before the server answers (App Review checks this).
    private(set) var blockedPeople: [String] = []

    /// "Before you chat" rules accepted. TODO(chat backend): store per account.
    var hasAgreedToChatRules = false

    /// Short toast text (failed actions, confirmations).
    var notice: String?

    /// Set after creating a game so the map can jump to it.
    var lastCreatedID: SportsEvent.ID?

    init(events: [SportsEvent] = MockData.events(), profile: LegacyProfile = MockData.profile) {
        self.allEvents = events
        self.profile = profile
    }

    // MARK: Queries

    /// Games you can see: none hosted by someone you blocked (`game_cards`, SPEC §8.3).
    var events: [SportsEvent] {
        allEvents.filter { !blockedPeople.contains($0.host) }
    }

    /// Who's going, minus anyone you blocked (`game_attendees`). Counts still include them.
    func visibleAttendees(of event: SportsEvent) -> [String] {
        event.attendees.filter { !blockedPeople.contains($0) }
    }

    func event(_ id: SportsEvent.ID) -> SportsEvent? {
        events.first { $0.id == id }
    }

    /// Games you joined as a guest.
    var goingEvents: [SportsEvent] {
        events.filter { $0.isYouGoing && !$0.isHostedByYou }.sorted { $0.start < $1.start }
    }

    /// Games you played or hosted that ended in the last 14 days, newest first, so you
    /// can still report someone afterwards (E21).
    var pastEvents: [SportsEvent] {
        let cutoff = Date.now.addingTimeInterval(-14 * 24 * 3600)
        return events
            .filter { $0.isYouGoing && !$0.isCancelled && $0.hasEnded && $0.end > cutoff }
            .sorted { $0.start > $1.start }
    }

    /// Saved games that haven't ended, soonest first.
    var bookmarkedEvents: [SportsEvent] {
        events.filter { $0.isBookmarked && !$0.hasEnded }.sorted { $0.start < $1.start }
    }

    var hostedEvents: [SportsEvent] {
        events.filter { $0.isHostedByYou && !$0.isCancelled }.sorted { $0.start < $1.start }
    }

    // MARK: Actions

    /// First come, first served: joining takes the spot immediately.
    func join(_ id: SportsEvent.ID) {
        if let event = event(id), event.attendees.contains(where: blockedPeople.contains) {
            notice = JoinFailure.blocked.message
            return
        }
        mutate(id) { event in
            guard !event.isFull, !event.isYouGoing, !event.isCancelled else { return }
            event.attendees.append(Person.you)
        }
    }

    /// Why a join the phone already showed was undone (server errors from `join_game`).
    enum JoinFailure {
        case full, blocked

        var message: String {
            switch self {
            case .full: String(localized: "Someone just took the last spot.")
            case .blocked: String(localized: "Someone you blocked is going.")
            }
        }
    }

    /// Undoes an optimistic join and says why.
    func rollBackJoin(_ id: SportsEvent.ID, reason: JoinFailure) {
        mutate(id) { $0.attendees.removeAll { $0 == Person.you } }
        notice = reason.message
    }

    func leave(_ id: SportsEvent.ID) {
        guard let event = event(id), event.isYouGoing, !event.isHostedByYou else { return }
        mutate(id) { $0.attendees.removeAll { $0 == Person.you } }
        if event.isFull { autoRepostIfNeeded(id) }
    }

    /// A full game just freed a spot: if the host turned on auto-repost, bump it.
    /// PLACEHOLDER: local only. TODO(backend): the server does this inside `leave_game`
    /// (and when a host raises capacity), so it also works when someone else leaves, and
    /// tells the host. 2.0 could pair it with the "A spot opened" push to people who saved it.
    func autoRepostIfNeeded(_ id: SportsEvent.ID) {
        guard let event = event(id), event.autoRepost, !event.isFull, !event.hasEnded, !event.isCancelled else { return }
        mutate(id) { $0.repostedAt = .now }
        notice = String(localized: "A spot opened in \(event.title) — it's back at the top of the map.")
    }

    // MARK: Group chat (not connected)

    /// Opening the chat marks it read (powers "Group chat · N new").
    func markChatRead(_ id: SportsEvent.ID) {
        mutate(id) { $0.unreadCount = 0 }
    }

    /// Host sets "where to meet", pinned at the top of the chat. TODO(B6): `update_game`.
    func updateMeetUpSpot(_ id: SportsEvent.ID, to spot: String) {
        mutate(id) { event in
            event.meetUpSpot = spot
            event.messages.append(ChatMessage(kind: .system, text: String(localized: "Meet-up spot updated"), sentAt: .now))
        }
    }

    /// TODO(B15): `toggle_bookmark` RPC.
    func toggleBookmark(_ id: SportsEvent.ID) {
        mutate(id) { $0.isBookmarked.toggle() }
    }

    /// Soft cancel: the game stays visible to people going, marked cancelled.
    func cancel(_ id: SportsEvent.ID) {
        mutate(id) { $0.isCancelled = true }
        notice = String(localized: "Game cancelled. We let everyone going know.")
    }

    // MARK: Safety (backend: B8)

    enum ReportReason: String, CaseIterable, Identifiable {
        case harassment, inappropriate, spam, unsafe, other

        var id: Self { self }

        var title: String {
            switch self {
            case .harassment: String(localized: "Harassment or hate")
            case .inappropriate: String(localized: "Inappropriate content")
            case .spam: String(localized: "Spam or fake")
            case .unsafe: String(localized: "Made me feel unsafe")
            case .other: String(localized: "Something else")
            }
        }
    }

    /// TODO(B8): call the `report` RPC, which alerts the moderation channel.
    func report(_ target: LegacyReportTarget, reason: ReportReason, note: String) {}

    func block(_ person: String) {
        guard person != Person.you, !blockedPeople.contains(person) else { return }
        blockedPeople.insert(person, at: 0)
    }

    func unblock(_ person: String) {
        blockedPeople.removeAll { $0 == person }
    }

    func save(_ draft: SportsEvent) {
        if let index = allEvents.firstIndex(where: { $0.id == draft.id }) {
            allEvents[index] = draft
        } else {
            allEvents.append(draft)
            lastCreatedID = draft.id
        }
    }

    func mutate(_ id: SportsEvent.ID, _ change: (inout SportsEvent) -> Void) {
        guard let index = allEvents.firstIndex(where: { $0.id == id }) else { return }
        change(&allEvents[index])
    }
}

/// What a report is about: a person or a game.
enum LegacyReportTarget: Hashable, Identifiable {
    case person(String)
    case game(SportsEvent.ID)

    var id: Self { self }
}
