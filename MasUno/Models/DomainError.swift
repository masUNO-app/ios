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

    // Raised by Supabase Auth or the auth hook; mapped in `AuthService` (B5).
    case emailNotAllowed, schoolApprovalNeeded, signInFailed, tooManyAttempts, invalidCredentials
    case emailTaken, weakPassword

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
        case "email_not_allowed": .emailNotAllowed
        default: .unknown(serverCode)
        }
    }

    /// Short copy for a failed action (SPEC §7.6.8).
    @MainActor var message: String {
        switch self {
        case .full: String(localized: "Someone just took the last spot.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .cancelled: String(localized: "This game was cancelled.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .ended: String(localized: "This game has ended", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .blocked: String(localized: "Someone you blocked is going.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .notFound: String(localized: "This game isn't available anymore.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .notAllowed: String(localized: "You can't do that on this game.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .limitReached: String(localized: "You can host up to 3 upcoming games. Cancel one to post another.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .capacityBelowGoing: String(localized: "Players can't be lower than the number going.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .invalidTime: String(localized: "Pick a start time in the next 7 days.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .invalidText: TextFilter.message
        case .invalidInput: String(localized: "Check the details and try again.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .notAuthenticated: String(localized: "Please sign in again.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .suspended: String(localized: "Your account is suspended", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .pendingApproval: String(localized: "Your account is still waiting for approval.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .chatRulesRequired: String(localized: "Agree to the chat rules to send messages.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .chatDisabled: String(localized: "Messages are off right now. Try again later.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .rateLimited: String(localized: "You're sending messages too fast. Wait a minute.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .invalidInvite: String(localized: "That invite code doesn't work. Check it and try again.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .emailNotAllowed: String(localized: "masUNO isn't open at your school yet.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .schoolApprovalNeeded: String(localized: "Your school hasn't approved masUNO yet.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .signInFailed: String(localized: "We couldn't sign you in. Try again.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .tooManyAttempts: String(localized: "Too many tries. Wait a minute and try again.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .invalidCredentials: String(localized: "That email and password don't match.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .emailTaken: String(localized: "There's already an account with that email. Sign in instead.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .weakPassword: String(localized: "Pick a stronger password: at least 8 characters.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .offline: String(localized: "You're offline. Try again when you're connected.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        case .unknown: String(localized: "Something went wrong. Try again.", bundle: LanguageSettings.shared.bundle, locale: LanguageSettings.shared.locale)
        }
    }
}
