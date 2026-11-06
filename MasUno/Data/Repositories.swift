import Foundation

// The boundary between the app and Supabase (SPEC §8.5, `docs/API.md`). Views and view
// models only see these protocols, and only this folder imports `supabase-swift` (B7).
// Every method throws `DomainError`. A change here is one PR reviewed by both coders.

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
}

/// Your own profile (`my_profile`, `complete_profile`).
protocol ProfileRepository: AnyObject {
    /// Nil until onboarding has saved a profile.
    func fetchMyProfile() async throws -> Profile?
    /// Edit profile & interests.
    func updateProfile(_ input: ProfileInput) async throws -> Profile
}

/// Reports and blocks. Instant local hiding after a block is `GameStore`'s job (B6).
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
}
