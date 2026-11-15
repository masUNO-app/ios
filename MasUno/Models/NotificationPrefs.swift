import Foundation

/// One row of `notification_prefs`. Cancellations, changes and "You're in" are not here: those always send.
nonisolated struct NotificationPrefs: Codable, Equatable, Sendable {
    var interestMatch: Bool
    var spotOpen: Bool
    var reminders: Bool
    var hosting: Bool
    var chat: Bool
    /// Off until the person opts in. This is the only promotional kind.
    var winback: Bool

    static let standard = NotificationPrefs(
        interestMatch: true, spotOpen: true, reminders: true, hosting: true, chat: true, winback: false
    )

    enum CodingKeys: String, CodingKey {
        case interestMatch = "interest_match"
        case spotOpen = "spot_open"
        case reminders, hosting, chat, winback
    }
}
