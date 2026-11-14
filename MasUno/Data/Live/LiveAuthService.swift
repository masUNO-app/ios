import AuthenticationServices
import Foundation
import Observation
import Supabase

/// The live `AuthService` (B5, SPEC §8.4). Students sign up with their school email and a
/// password, and wait for the team to approve the account (N36). The auth hook on the server
/// decides which addresses may sign up. School SSO (`signIn(at:)`) is kept but unused.
@Observable
final class LiveAuthService: AuthService {
    private(set) var state = AuthState.loading

    @ObservationIgnored private let client: SupabaseClient
    /// Sign out and delete account end the session on purpose, so it isn't "expired".
    @ObservationIgnored private var isLeaving = false
    @ObservationIgnored private var listener: Task<Void, Never>?

    /// Matches Supabase Auth → URL Configuration → Redirect URLs (B2).
    private static let callbackURL = URL(string: "masuno://auth-callback")!
    /// The minimum, so masUNO gets a name and an email and nothing else (SPEC §10.2).
    private static let scopes = "openid email profile"

    init(client: SupabaseClient) {
        self.client = client
        listener = Task { [weak self] in
            for await (event, _) in client.auth.authStateChanges where event == .signedOut {
                self?.sessionEnded()
            }
        }
    }

    deinit { listener?.cancel() }

    var suggestedName: SuggestedName? {
        guard let metadata = client.auth.currentSession?.user.userMetadata else { return nil }
        return SuggestedName(metadata: metadata.compactMapValues(\.stringValue))
    }

    func restoreSession() async {
        guard let saved = client.auth.currentSession else {
            sessionEnded()
            return
        }
        do {
            let session = try await client.auth.session
            try await refreshState(userID: session.user.id)
        } catch is AuthError {
            sessionEnded()
        } catch {
            // No connection isn't a lost session: keep it, and the map shows the last games.
            if state == .loading { state = .signedIn(userID: saved.user.id) }
        }
    }

    func signIn(at school: University) async throws {
        guard let sso = school.ssoProvider, let provider = Provider(rawValue: sso.rawValue) else {
            throw DomainError.signInFailed
        }
        do {
            let session = try await client.auth.signInWithOAuth(
                provider: provider,
                redirectTo: Self.callbackURL,
                scopes: Self.scopes,
                queryParams: [(name: sso.hintParameter, value: school.emailDomain)],
                // Skips the "masUNO wants to use … to sign in" alert; students re-enter their
                // school password if they ever sign in again (SPEC §8.4).
                configure: { $0.prefersEphemeralWebBrowserSession = true }
            )
            try await refreshState(userID: session.user.id)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            throw translate(error)
        }
    }

    func signUp(email: String, password: String) async throws {
        do {
            let response = try await client.auth.signUp(email: email, password: password)
            // No session means the project has "Confirm email" on, which this flow doesn't use
            // (supabase/README, hosted checklist).
            guard let session = response.session else { throw DomainError.signInFailed }
            try await refreshState(userID: session.user.id)
        } catch {
            throw translate(error)
        }
    }

    func signIn(email: String, password: String) async throws {
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            try await refreshState(userID: session.user.id)
        } catch {
            throw translate(error)
        }
    }

    func refreshStatus() async throws {
        do {
            try await refreshState()
        } catch {
            throw translate(error)
        }
    }

    /// `redeem_invite` answers with a status rather than raising (`docs/API.md`, Invites), then the
    /// usual status check moves the account on.
    func redeemInvite(_ code: String) async throws {
        do {
            let status: String = try await client.rpc("redeem_invite", params: RedeemInviteParams(code: code)).execute().value
            try RedeemInviteResult.check(status)
            try await refreshState()
        } catch {
            throw translate(error)
        }
    }

    func waitlistPosition() async throws -> Int? {
        do {
            let position: Int? = try await client.rpc("waitlist_position").execute().value
            return position
        } catch {
            throw translate(error)
        }
    }

    func completeProfile(_ input: ProfileInput) async throws {
        do {
            try await client.rpc("complete_profile", params: CompleteProfileParams(input)).execute()
            try await refreshState()
        } catch {
            throw translate(error)
        }
    }

    func acceptGuidelines() async throws {
        do {
            try await client.rpc("accept_guidelines").execute()
            try await refreshState()
        } catch {
            throw translate(error)
        }
    }

    func signOut() async throws {
        isLeaving = true
        defer { isLeaving = false }
        do {
            try await client.auth.signOut()
            state = .signedOut(expired: false)
        } catch {
            throw translate(error)
        }
    }

    func deleteAccount() async throws {
        isLeaving = true
        defer { isLeaving = false }
        do {
            try await client.functions.invoke("delete-account", options: FunctionInvokeOptions(method: .post))
            // The server already deleted the user, so only this phone's session is left.
            try? await client.auth.signOut(scope: .local)
            state = .signedOut(expired: false)
        } catch {
            throw translate(error)
        }
    }

    // MARK: Helpers

    private func refreshState(userID: UUID? = nil) async throws {
        guard let id = userID ?? client.auth.currentSession?.user.id else { throw DomainError.notAuthenticated }
        let rows: [ProfileStatusRow] = try await client
            .from("my_profile")
            .select("guidelines_accepted_at,banned_at")
            .execute()
            .value
        // Only an account without a profile can still be waiting for approval.
        var isPending = false
        if rows.isEmpty {
            let status: String = try await client.rpc("signup_status").execute().value
            isPending = status == "pending"
        }
        state = AuthState(profile: rows.first, isPending: isPending, userID: id)
    }

    /// The session is gone. If there was an account in use and nobody asked for this, it expired.
    private func sessionEnded() {
        guard !isLeaving else { return }
        switch state {
        case .loading: state = .signedOut(expired: false)
        case .signedOut: break
        case .pendingApproval, .needsProfile, .needsGuidelines, .suspended, .signedIn: state = .signedOut(expired: true)
        }
    }

    private func translate(_ error: any Error) -> DomainError {
        switch error {
        case let error as DomainError:
            return error
        case is URLError:
            return .offline
        case let error as PostgrestError:
            return DomainError(serverCode: error.message)
        case let error as AuthError:
            return translate(authError: error)
        default:
            return .signInFailed
        }
    }

    private func translate(authError error: AuthError) -> DomainError {
        switch error {
        case .pkceGrantCodeExchange(let message, let failure, let code):
            return SignInFailure(error: failure, code: code, message: message).domainError
        case .api(let message, let code, _, _):
            if code == .invalidCredentials { return .invalidCredentials }
            if code == .userAlreadyExists || code == .emailExists { return .emailTaken }
            if code == .weakPassword { return .weakPassword }
            if code == .overRequestRateLimit { return .tooManyAttempts }
            return SignInFailure(code: code.rawValue, message: message).domainError
        case .sessionMissing:
            return .notAuthenticated
        case .weakPassword:
            return .weakPassword
        default:
            return .signInFailed
        }
    }
}
