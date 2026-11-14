#if !DEBUG
import Foundation
import Observation

/// What Release builds run on without real keys in `Config.xcconfig`. Every call fails as offline, so a
/// Release build can't ever show mock data as real (N27, §10.4).
@Observable
final class UnavailableBackend: AuthService, GameRepository, ProfileRepository, SafetyRepository, ChatRepository, AppConfigRepository {
    private(set) var state = AuthState.signedOut(expired: false)
    let suggestedName: SuggestedName? = nil

    func restoreSession() async {}
    func signIn(at school: University) async throws { throw DomainError.offline }
    func signUp(email: String, password: String) async throws { throw DomainError.offline }
    func signIn(email: String, password: String) async throws { throw DomainError.offline }
    func refreshStatus() async throws { throw DomainError.offline }
    func redeemInvite(_ code: String) async throws { throw DomainError.offline }
    func waitlistPosition() async throws -> Int? { throw DomainError.offline }
    func completeProfile(_ input: ProfileInput) async throws { throw DomainError.offline }
    func acceptGuidelines() async throws { throw DomainError.offline }
    func signOut() async throws { throw DomainError.offline }
    func deleteAccount() async throws { throw DomainError.offline }

    func fetchMapGames() async throws -> [Game] { throw DomainError.offline }
    func fetchGuestGames(campus: UUID) async throws -> [Game] { throw DomainError.offline }
    func fetchMyGames() async throws -> [Game] { throw DomainError.offline }
    func fetchGame(id: UUID) async throws -> Game { throw DomainError.offline }
    func fetchGames(ids: [UUID]) async throws -> [Game] { throw DomainError.offline }
    func fetchAttendees(gameID: UUID) async throws -> [Attendee] { throw DomainError.offline }
    func fetchActivity(gameID: UUID) async throws -> [GameActivityEntry] { throw DomainError.offline }
    func createGame(_ draft: GameDraft) async throws -> Game { throw DomainError.offline }
    func updateGame(id: UUID, _ draft: GameDraft) async throws -> Game { throw DomainError.offline }
    func cancelGame(id: UUID) async throws -> Game { throw DomainError.offline }
    func joinGame(id: UUID) async throws -> Game { throw DomainError.offline }
    func leaveGame(id: UUID) async throws -> Game { throw DomainError.offline }
    func changes(campus: UUID) -> AsyncStream<GameChanges> { AsyncStream { $0.finish() } }

    func fetchMyProfile() async throws -> Profile? { throw DomainError.offline }
    func updateProfile(_ input: ProfileInput) async throws -> Profile { throw DomainError.offline }
    func fetchInvites() async throws -> [Invite] { throw DomainError.offline }
    func markBetaTester() async throws -> Profile { throw DomainError.offline }

    func report(_ target: ReportTarget, reason: ReportReason, note: String?) async throws { throw DomainError.offline }
    func block(userID: UUID) async throws { throw DomainError.offline }
    func unblock(userID: UUID) async throws { throw DomainError.offline }
    func fetchBlockedPeople() async throws -> [PersonSummary] { throw DomainError.offline }

    func fetchMessages(gameID: UUID, before: Date?, limit: Int) async throws -> [ChatMessage] { throw DomainError.offline }
    func fetchMessages(gameID: UUID, since: Date) async throws -> [ChatMessage] { throw DomainError.offline }
    func sendMessage(gameID: UUID, body: String, clientID: UUID) async throws -> ChatMessage { throw DomainError.offline }
    func acceptChatRules() async throws { throw DomainError.offline }
    func markRead(gameID: UUID) async throws { throw DomainError.offline }
    func fetchUnreadCounts() async throws -> [UUID: Int] { throw DomainError.offline }
    func updates(gameID: UUID) -> AsyncStream<ChatUpdate> { AsyncStream { $0.finish() } }

    func fetchAppConfig() async throws -> AppConfig { throw DomainError.offline }
    func fetchActivities() async throws -> [Activity] { throw DomainError.offline }
    func fetchUniversities() async throws -> [University] { throw DomainError.offline }
}
#endif
