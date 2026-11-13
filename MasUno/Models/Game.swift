import CoreLocation
import Foundation

nonisolated enum GameRole: String, Hashable, Sendable {
    case host, player
}

/// The six Event detail states (SPEC §7.6.4).
nonisolated enum GameStatus: Hashable, Sendable {
    case open, going, full, hosting, ended, cancelled
}

/// A row in `game_cards`, seen by the signed-in user. Every game write returns one.
nonisolated struct Game: Identifiable, Hashable, Sendable {
    /// How long a repost keeps the pin on top with "Spot open" (SPEC §7.6.11).
    static let bumpWindow: TimeInterval = 2 * 3600
    /// Pins say "Soon" this close to the start (SPEC §7.6.1).
    static let soonWindow: TimeInterval = 3600

    let id: UUID
    var host: PersonSummary
    var activity: Activity
    var title: String
    var startsAt: Date
    var durationMinutes: Int
    var endsAt: Date
    /// Total players, including the host.
    var capacity: Int
    /// Includes the host and anyone you blocked, so it can exceed Who's going.
    var goingCount: Int
    var notes: String?
    var place: Place
    var meetPoint: String?
    var materialChangeAt: Date?
    var cancelledAt: Date?
    var autoRepost: Bool
    var repostedAt: Date?
    var createdAt: Date
    /// Nil when you're not in this game.
    var myRole: GameRole?
    var myJoinedAt: Date?
    /// Someone you blocked is going, so `join_game` will answer `blocked`.
    var hasBlockedAttendee: Bool

    var spotsLeft: Int { max(capacity - goingCount, 0) }
    var isFull: Bool { spotsLeft == 0 }
    var isCancelled: Bool { cancelledAt != nil }
    var isHostedByMe: Bool { myRole == .host }
    var isGoing: Bool { myRole != nil }
    var coordinate: CLLocationCoordinate2D { place.coordinate }
    /// A guest's preview of a game (`guest_games`): no host, attendees, note or meet-up spot.
    var hidesPeople: Bool { host.isHidden }

    func hasEnded(now: Date = .now) -> Bool { endsAt <= now }

    func status(now: Date = .now) -> GameStatus {
        if isCancelled { return .cancelled }
        if hasEnded(now: now) { return .ended }
        if myRole == .host { return .hosting }
        if myRole == .player { return .going }
        return isFull ? .full : .open
    }

    func isSoon(now: Date = .now) -> Bool {
        let wait = startsAt.timeIntervalSince(now)
        return wait >= 0 && wait <= Self.soonWindow
    }

    /// Reposted in the last two hours: draws on top with "Spot open", listed first in search.
    func isBumped(now: Date = .now) -> Bool {
        guard let repostedAt else { return false }
        return now.timeIntervalSince(repostedAt) < Self.bumpWindow
    }
}

/// What `create_game` and `update_game` take. Send nil, not "", for an empty note or meet-up spot.
nonisolated struct GameDraft: Hashable, Sendable {
    static let titleLimit = 40
    static let notesLimit = 280
    static let meetPointLimit = 80
    static let durations = [30, 60, 90, 120, 180]
    static let capacityRange = 2...22
    static let maxUpcomingHosted = 3
    static let postingWindow: TimeInterval = 7 * 24 * 3600

    var activity: Activity
    var title: String
    var startsAt: Date
    var durationMinutes: Int
    var capacity: Int
    var notes: String?
    var place: Place
    var meetPoint: String?
    var autoRepost = true
}

extension GameDraft {
    /// Starts an edit from the current game.
    nonisolated init(_ game: Game) {
        self.init(
            activity: game.activity, title: game.title, startsAt: game.startsAt,
            durationMinutes: game.durationMinutes, capacity: game.capacity, notes: game.notes,
            place: game.place, meetPoint: game.meetPoint, autoRepost: game.autoRepost
        )
    }
}

/// A system row in the group chat (`game_activity`, SPEC §7.6.9).
nonisolated struct GameActivityEntry: Identifiable, Hashable, Sendable {
    nonisolated enum Kind: String, Hashable, Sendable {
        case created, joined, left
        case meetPointUpdated = "meet_point_updated"
        case timeOrPlaceChanged = "time_or_place_changed"
        case cancelled
    }

    let id: UUID
    var gameID: UUID
    var kind: Kind
    /// Nil once that person's account is deleted, or if you blocked them.
    var actor: PersonSummary?
    var at: Date
}
