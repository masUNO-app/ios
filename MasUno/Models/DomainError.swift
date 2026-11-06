import Foundation

/// Every failure the screens can show. RPCs raise the short codes in `docs/API.md`;
/// `init(serverCode:)` is the one place they're translated.
nonisolated enum DomainError: Error, Hashable, Sendable {
    // Raised by RPCs.
    case full, cancelled, ended, blocked, notFound, notAllowed
    case limitReached, capacityBelowGoing
    case invalidTime, invalidText, invalidInput
    case notAuthenticated, suspended

    // Raised by Supabase Auth or the auth hook; mapped in `AuthService` (B5).
    case emailNotAllowed, codeInvalid, codeExpired, tooManyAttempts, invalidCredentials

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
        case "email_not_allowed": .emailNotAllowed
        default: .unknown(serverCode)
        }
    }

    /// Short copy for a failed action (SPEC §7.6.8).
    @MainActor var message: String {
        switch self {
        case .full: String(localized: "Someone just took the last spot.")
        case .cancelled: String(localized: "This game was cancelled.")
        case .ended: String(localized: "This game has ended")
        case .blocked: String(localized: "Someone you blocked is going.")
        case .notFound: String(localized: "This game isn't available anymore.")
        case .notAllowed: String(localized: "You can't do that on this game.")
        case .limitReached: String(localized: "You can host up to 3 upcoming games. Cancel one to post another.")
        case .capacityBelowGoing: String(localized: "Players can't be lower than the number going.")
        case .invalidTime: String(localized: "Pick a start time in the next 7 days.")
        case .invalidText: TextFilter.message
        case .invalidInput: String(localized: "Check the details and try again.")
        case .notAuthenticated: String(localized: "Please sign in again.")
        case .suspended: String(localized: "Your account is suspended")
        case .emailNotAllowed: String(localized: "masUNO is just for Tec students right now. Use your @tec.mx email.")
        case .codeInvalid: String(localized: "That code didn't work. Check the email and try again.")
        case .codeExpired: String(localized: "That code expired. Send a new one.")
        case .tooManyAttempts: String(localized: "Too many tries. Wait a minute and try again.")
        case .invalidCredentials: String(localized: "That email and password don't match.")
        case .offline: String(localized: "You're offline. Try again when you're connected.")
        case .unknown: String(localized: "Something went wrong. Try again.")
        }
    }
}
