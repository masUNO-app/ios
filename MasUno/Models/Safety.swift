import Foundation

/// What a report is about: a person or a game (`report` RPC: exactly one of `p_user_id`,
/// `p_game_id`), or a chat message (`report_message`).
nonisolated enum ReportTarget: Hashable, Sendable {
    case person(UUID)
    case game(UUID)
    case message(UUID)
}

/// Raw values are what the `report` RPC stores in `reports.reason`.
nonisolated enum ReportReason: String, CaseIterable, Identifiable, Hashable, Sendable {
    case harassment, inappropriate, spam, unsafe, other

    var id: Self { self }

    /// The order the report sheet lists them in: the most serious first.
    static let listed: [ReportReason] = [.unsafe, .harassment, .inappropriate, .spam, .other]

    /// The wording depends on what's being reported: a person gets the Figma "Report Ricardo"
    /// list; a game or a message keeps the general one.
    func title(for target: ReportTarget) -> String {
        if case .person = target {
            switch self {
            case .unsafe: return String(localized: "Made me feel unsafe")
            case .harassment: return String(localized: "Harassment or hateful language")
            case .inappropriate: return String(localized: "Pushed me to share personal info")
            case .spam: return String(localized: "Fake profile or not a student")
            case .other: return String(localized: "Something else")
            }
        }
        switch self {
        case .unsafe: return String(localized: "Made me feel unsafe")
        case .harassment: return String(localized: "Harassment or hateful language")
        case .inappropriate: return String(localized: "Inappropriate content")
        case .spam: return String(localized: "Spam or fake")
        case .other: return String(localized: "Something else")
        }
    }

    /// The person wording for these two says more than the stored reason does, so the report's
    /// note starts with it and moderators see what was picked.
    func noteLead(for target: ReportTarget) -> String? {
        guard case .person = target, self == .inappropriate || self == .spam else { return nil }
        return title(for: target)
    }
}
