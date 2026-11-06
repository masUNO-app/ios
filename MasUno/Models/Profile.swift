import Foundation

/// The signed-in student (`my_profile`). Only you see `lastName` and `interests` (SPEC §8.8).
nonisolated struct Profile: Identifiable, Hashable, Sendable {
    let id: UUID
    var firstName: String
    var lastName: String
    var gradYear: Int
    var university: University
    var interests: [Activity]

    var fullName: String { "\(firstName) \(lastName)" }

    /// How others see you.
    var summary: PersonSummary {
        PersonSummary(id: id, firstName: firstName, lastInitial: String(lastName.prefix(1)).uppercased(), gradYear: gradYear)
    }
}

/// What `complete_profile` takes: onboarding step 4–5 and Edit profile & interests.
nonisolated struct ProfileInput: Hashable, Sendable {
    static let nameLimit = 30

    var firstName: String
    var lastName: String
    var gradYear: Int
    /// At least one.
    var interests: [Activity]
    var locale = "en"
}
