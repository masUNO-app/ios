import Foundation

/// How another student appears in the app: first name, last initial and class year,
/// nothing else (SPEC §8.8). Identity is always `id`, never the name.
nonisolated struct PersonSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    var firstName: String
    var lastInitial: String
    var gradYear: Int

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
