import Foundation

/// What a report is about (`report` RPC: exactly one of `p_user_id`, `p_game_id`).
nonisolated enum ReportTarget: Hashable, Sendable {
    case person(UUID)
    case game(UUID)
}

/// Raw values are what the `report` RPC stores in `reports.reason`.
nonisolated enum ReportReason: String, CaseIterable, Identifiable, Hashable, Sendable {
    case harassment, inappropriate, spam, unsafe, other

    var id: Self { self }
}
