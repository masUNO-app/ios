import Foundation

/// Where the launch gate sends you (SPEC §7.3).
nonisolated enum AuthState: Hashable, Sendable {
    /// Before the saved session has been checked.
    case loading
    /// `expired`: the saved session stopped working, so onboarding reopens at Find your school.
    /// Signing out or deleting the account starts at Welcome (SPEC §7.5).
    case signedOut(expired: Bool)
    /// Signed up with a school email and a password, and the team hasn't approved it yet (N36).
    case pendingApproval
    /// Set up profile: about you, then interests.
    case needsProfile
    /// Set up profile: community guidelines.
    case needsGuidelines
    case suspended
    case signedIn(userID: UUID)
}

/// Sign-in and account lifecycle (SPEC §7.5, §8.4, B5). Students sign up with their school email
/// and a password, and the team approves each account by hand (N36). School SSO (`signIn(at:)`)
/// is kept but nothing calls it: Tec IT hasn't approved the Entra app. Implementations are `@Observable`,
/// so a view reading `state` updates when it changes. Failures are `DomainError`s.
protocol AuthService: AnyObject {
    var state: AuthState { get }
    /// The name the school's sign-in gave us, to fill in Set up profile.
    var suggestedName: SuggestedName? { get }

    /// Checks the saved session at launch and leaves `.loading`.
    func restoreSession() async

    /// Not used while sign-in is email and password (N36); kept for when a school approves SSO.
    /// Opens the school's own sign-in page. Closing the page isn't a failure: it returns with
    /// `state` unchanged. The school picks the provider and hint, but doesn't decide who gets in:
    /// the auth hook checks the account on the server and can throw `.emailNotAllowed`.
    func signIn(at school: University) async throws
    /// Creates an account for a school address and leaves it `.pendingApproval`; an allowlisted
    /// address skips the wait. The auth hook refuses any other address with `.emailNotAllowed`.
    func signUp(email: String, password: String) async throws
    /// Students, and the allowlisted review, demo-day and QA accounts.
    func signIn(email: String, password: String) async throws
    /// Asks the server where the account stands now: `.pendingApproval` moves on once approved.
    func refreshStatus() async throws

    /// `complete_profile`, then moves `.needsProfile` → `.needsGuidelines`.
    func completeProfile(_ input: ProfileInput) async throws
    /// `accept_guidelines`, then moves `.needsGuidelines` → `.signedIn`.
    func acceptGuidelines() async throws

    func signOut() async throws
    /// The `delete-account` Edge Function, then `.signedOut`.
    func deleteAccount() async throws
}
