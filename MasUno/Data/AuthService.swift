import Foundation

/// Where the launch gate sends you (SPEC §7.3).
nonisolated enum AuthState: Hashable, Sendable {
    /// Before the saved session has been checked.
    case loading
    /// `email` prefills the email step after a session expires.
    case signedOut(email: String?)
    /// Onboarding steps 4–5.
    case needsProfile
    /// Onboarding step 6.
    case needsGuidelines
    case suspended
    case signedIn(userID: UUID)
}

/// Raw values are what `sign_in_method` returns.
nonisolated enum SignInMethod: String, Hashable, Sendable {
    case otp, password
}

/// Sign-in and account lifecycle (SPEC §7.5, B5). Implementations are `@Observable`,
/// so a view reading `state` updates when it changes. Failures are `DomainError`s.
protocol AuthService: AnyObject {
    var state: AuthState { get }

    /// Checks the saved session at launch and leaves `.loading`.
    func restoreSession() async

    /// Call this before checking for `@tec.mx`: review accounts are Gmail aliases and get `.password`.
    func signInMethod(for email: String) async throws -> SignInMethod
    func sendCode(to email: String) async throws
    func verifyCode(_ code: String, email: String) async throws
    func signIn(email: String, password: String) async throws

    /// `complete_profile`, then moves `.needsProfile` → `.needsGuidelines`.
    func completeProfile(_ input: ProfileInput) async throws
    /// `accept_guidelines`, then moves `.needsGuidelines` → `.signedIn`.
    func acceptGuidelines() async throws

    func signOut() async throws
    /// The `delete-account` Edge Function, then `.signedOut`.
    func deleteAccount() async throws
}
