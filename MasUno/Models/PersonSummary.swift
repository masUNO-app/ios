import Foundation

/// How another student appears in the app: first name, last initial and class year,
/// nothing else (SPEC §8.8). Identity is always `id`, never the name.
nonisolated struct PersonSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    var firstName: String
    var lastInitial: String
    var gradYear: Int
    /// Opened a TestFlight build while signed in (`is_beta_tester`, N37). Only Who's going and your own
    /// profile carry it; everywhere else it's false.
    var isBetaTester = false

    /// Someone a guest isn't shown: names stay with verified students (SPEC §8.8, `guest_games`).
    static let hidden = PersonSummary(id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)), firstName: "", lastInitial: "", gradYear: 0)

    /// The placeholder above, not a real person.
    var isHidden: Bool { id == Self.hidden.id }

    /// "Emilio G." (SPEC §7.2).
    var displayName: String { "\(firstName) \(lastInitial)." }

    /// "EG", for initials avatars.
    var initials: String { "\(firstName.prefix(1))\(lastInitial.prefix(1))".uppercased() }
}

/// A row in Who's going (`game_attendees`).
nonisolated struct Attendee: Identifiable, Hashable, Sendable {
    var person: PersonSummary
    var role: GameRole
    var joinedAt: Date

    var id: UUID { person.id }
}
