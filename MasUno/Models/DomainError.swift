import Foundation

/// Every failure the screens can show. RPCs raise the short codes in `docs/API.md`;
/// `init(serverCode:)` is the one place they're translated.
nonisolated enum DomainError: Error, Hashable, Sendable {
    // Raised by RPCs.
    case full, cancelled, ended, blocked, notFound, notAllowed
    case limitReached, capacityBelowGoing
    case invalidTime, invalidText, invalidInput
    case notAuthenticated, suspended, pendingApproval
    // Raised by the chat RPCs.
    case chatRulesRequired, chatDisabled, rateLimited
    // Returned by `redeem_invite` (1.0, N37).
    case invalidInvite
    // Raised by `give_props` (1.0).
    case propsClosed, propsDisabled

    // Raised by Supabase Auth or the auth hook; mapped in `AuthService` (B5).
    case emailNotAllowed, schoolApprovalNeeded, signInFailed, tooManyAttempts, invalidCredentials
    case emailTaken, weakPassword
    /// The 6-digit code from the sign-up or reset email is wrong or expired (N39). Supabase says
    /// `otp_expired` for both.
    case invalidCode
    /// Signing in to an account that hasn't entered its sign-up code. Onboarding sends a new code and
    /// opens the code step instead of showing this.
    case emailNotVerified

    // Client side.
    case offline
    /// A code this build doesn't know, kept for debugging. Older builds will meet new codes.
    case unknown(String)

    init(serverCode: String) {
        self = switch serverCode {
        case "full": .full
        case "cancelled": .cancelled
        case "ended": .ended
        case "blocked": .blocked
        case "not_found": .notFound
        case "not_allowed": .notAllowed
        case "limit_reached": .limitReached
        case "capacity_below_going": .capacityBelowGoing
        case "invalid_time": .invalidTime
        case "invalid_text": .invalidText
        case "invalid_input": .invalidInput
        case "not_authenticated": .notAuthenticated
        case "suspended": .suspended
        case "pending_approval": .pendingApproval
        case "chat_rules_required": .chatRulesRequired
        case "chat_disabled": .chatDisabled
        case "rate_limited": .rateLimited
        case "invalid_invite": .invalidInvite
        case "props_closed": .propsClosed
        case "props_disabled": .propsDisabled
        case "email_not_allowed": .emailNotAllowed
        default: .unknown(serverCode)
        }
    }

    /// Short copy for a failed action (SPEC §7.6.8).
    @MainActor var message: String {
        switch self {
        case .full: String.app("Someone just took the last spot.")
        case .cancelled: String.app("This plan was cancelled.")
        case .ended: String.app("This plan has wrapped")
        case .blocked: String.app("Someone you blocked is going.")
        case .notFound: String.app("This plan isn't available anymore.")
        case .notAllowed: String.app("You can't do that on this plan.")
        case .limitReached: String.app("You can host up to 3 upcoming plans. Cancel one to post another.")
        case .capacityBelowGoing: String.app("Can't go below the number of people going.")
        case .invalidTime: String.app("Pick a start time in the next 7 days.")
        case .invalidText: TextFilter.message
        case .invalidInput: String.app("Check the details and try again.")
        case .notAuthenticated: String.app("Please sign in again.")
        case .suspended: String.app("Your account is suspended")
        case .pendingApproval: String.app("Your account is still waiting for approval.")
        case .chatRulesRequired: String.app("Agree to the chat rules to send messages.")
        case .chatDisabled: String.app("Messages are off right now. Try again later.")
        case .rateLimited: String.app("You're sending messages too fast. Wait a minute.")
        case .invalidInvite: String.app("That invite code doesn't work. Check it and try again.")
        case .propsClosed: String.app("Props for this plan are closed.")
        case .propsDisabled: String.app("Props are off right now. Try again later.")
        case .emailNotAllowed: String.app("masUNO isn't open at your school yet.")
        case .schoolApprovalNeeded: String.app("Your school hasn't approved masUNO yet.")
        case .signInFailed: String.app("We couldn't sign you in. Try again.")
        case .tooManyAttempts: String.app("Too many tries. Wait a minute and try again.")
        case .invalidCredentials: String.app("That email and password don't match.")
        case .emailTaken: String.app("There's already an account with that email. Sign in instead.")
        case .weakPassword: String.app("Pick a stronger password: at least 8 characters.")
        case .invalidCode: String.app("That code doesn't work or has expired. Check it or send a new one.")
        case .emailNotVerified: String.app("Confirm your email with the code we sent you.")
        case .offline: String.app("You're offline. Try again when you're connected.")
        case .unknown: String.app("Something went wrong. Try again.")
        }
    }
}
