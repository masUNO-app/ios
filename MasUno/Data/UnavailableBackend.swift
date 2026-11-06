#if !DEBUG
import Foundation
import Observation

/// What Release builds run on until the live repositories land (B5, B7). Every call fails
/// as offline, so a Release build can't ever show mock data as real (N27, §10.4).
@Observable
final class UnavailableBackend: AuthService, GameRepository, ProfileRepository, SafetyRepository, AppConfigRepository {
    private(set) var state = AuthState.signedOut(email: nil)

    func restoreSession() async {}
    func signInMethod(for email: String) async throws -> SignInMethod { throw DomainError.offline }
    func sendCode(to email: String) async throws { throw DomainError.offline }
    func verifyCode(_ code: String, email: String) async throws { throw DomainError.offline }
    func signIn(email: String, password: String) async throws { throw DomainError.offline }
    func completeProfile(_ input: ProfileInput) async throws { throw DomainError.offline }
    func acceptGuidelines() async throws { throw DomainError.offline }
    func signOut() async throws { throw DomainError.offline }
    func deleteAccount() async throws { throw DomainError.offline }

    func fetchMapGames() async throws -> [Game] { throw DomainError.offline }
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

    func fetchMyProfile() async throws -> Profile? { throw DomainError.offline }
    func updateProfile(_ input: ProfileInput) async throws -> Profile { throw DomainError.offline }

    func report(_ target: ReportTarget, reason: ReportReason, note: String?) async throws { throw DomainError.offline }
    func block(userID: UUID) async throws { throw DomainError.offline }
    func unblock(userID: UUID) async throws { throw DomainError.offline }
    func fetchBlockedPeople() async throws -> [PersonSummary] { throw DomainError.offline }

    func fetchAppConfig() async throws -> AppConfig { throw DomainError.offline }
    func fetchActivities() async throws -> [Activity] { throw DomainError.offline }
    func fetchOpenUniversities() async throws -> [University] { throw DomainError.offline }
}
#endif
