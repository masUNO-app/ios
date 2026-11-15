import Foundation

// The boundary between the app and Supabase (SPEC §8.5, `docs/API.md`). Views and view
// models only see these protocols, and only this folder imports `supabase-swift` (B7).
// Every method throws `DomainError`. A change here is one PR reviewed by both coders.

/// A ping on a campus's games channel (`campus:<id>:games`).
nonisolated enum GameChanges: Equatable, Sendable {
    /// These games changed, or a spot in them did.
    case games(Set<UUID>)
    /// Too many to list, such as a bulk change on the server: re-read everything on screen.
    case unlisted
}

/// Games: `game_cards`, `game_attendees`, `game_activity` and the game RPCs.
protocol GameRepository: AnyObject {
    /// Open games for the map: not cancelled, ended or full, starting within 7 days,
    /// newest bump first.
    func fetchMapGames() async throws -> [Game]
    /// Everything you host or joined that hasn't been over for more than 14 days.
    /// `GameStore` splits it into Going, Hosting and Past.
    func fetchMyGames() async throws -> [Game]
    /// Throws `.notFound` if the game doesn't exist or is hidden by a block.
    func fetchGame(id: UUID) async throws -> Game
    /// The games behind the phone's Saved list. Missing IDs are left out, not errors.
    func fetchGames(ids: [UUID]) async throws -> [Game]
    /// Who's going, host first, without anyone you blocked.
    func fetchAttendees(gameID: UUID) async throws -> [Attendee]
    /// Group chat system rows, oldest first.
    func fetchActivity(gameID: UUID) async throws -> [GameActivityEntry]

    func createGame(_ draft: GameDraft) async throws -> Game
    func updateGame(id: UUID, _ draft: GameDraft) async throws -> Game
    func cancelGame(id: UUID) async throws -> Game
    func joinGame(id: UUID) async throws -> Game
    func leaveGame(id: UUID) async throws -> Game
    /// Fires when a game on `campus`, or a spot in one, changes, for as long as the caller keeps
    /// listening. It says which games, not how, so callers re-read them. It ends if the connection
    /// can't be made or drops.
    func changes(campus: UUID) -> AsyncStream<GameChanges>
}

/// Your own profile (`my_profile`, `complete_profile`).
protocol ProfileRepository: AnyObject {
    /// Nil until onboarding has saved a profile.
    func fetchMyProfile() async throws -> Profile?
    /// Edit profile & interests.
    func updateProfile(_ input: ProfileInput) async throws -> Profile
}

/// Reports (people, games and chat messages) and blocks. Instant local hiding after a block is `GameStore`'s job (B6).
protocol SafetyRepository: AnyObject {
    func report(_ target: ReportTarget, reason: ReportReason, note: String?) async throws
    func block(userID: UUID) async throws
    func unblock(userID: UUID) async throws
    /// Settings › Blocked people, newest first.
    func fetchBlockedPeople() async throws -> [PersonSummary]
}

/// Read-only reference data. Both work signed out: the version gate runs before sign-in.
protocol AppConfigRepository: AnyObject {
    func fetchAppConfig() async throws -> AppConfig
    func fetchActivities() async throws -> [Activity]
    /// Find your school (`university_lookup`): every campus, open or closed, so existing accounts
    /// can sign back in at a closed one. Hidden demo campuses aren't listed.
    func fetchUniversities() async throws -> [University]
}

/// Group chat messaging (`game_messages`, `chat_unread` and the chat RPCs; SPEC Appendix A). System
/// rows stay in `GameRepository.fetchActivity`.
protocol ChatRepository: AnyObject {
    /// The newest `limit` messages, oldest first. Pass the oldest one you have as `before` for the
    /// page before it; that page can repeat it. Messages from people you blocked are left out.
    func fetchMessages(gameID: UUID, before: Date?, limit: Int) async throws -> [ChatMessage]
    /// Everything sent at or after `since`, oldest first.
    func fetchMessages(gameID: UUID, since: Date) async throws -> [ChatMessage]
    /// `clientID` identifies this send: sending it again returns the first message instead of
    /// posting twice. Throws `.chatRulesRequired` until `acceptChatRules` has run.
    func sendMessage(gameID: UUID, body: String, clientID: UUID) async throws -> ChatMessage
    /// "Before you chat", once per account.
    func acceptChatRules() async throws
    func markRead(gameID: UUID) async throws
    /// Messages you haven't seen, by game. Games with none are left out.
    func fetchUnreadCounts() async throws -> [UUID: Int]
    /// Fires when a game's chat has something new, for as long as the caller keeps listening. It
    /// ends if the connection can't be made, so callers also check on a timer.
    func updates(gameID: UUID) -> AsyncStream<ChatUpdate>
}
