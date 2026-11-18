import Foundation

/// The signed-in student (`my_profile`). Only you see `lastName` and `interests` (SPEC §8.8).
nonisolated struct Profile: Identifiable, Hashable, Sendable {
    let id: UUID
    var firstName: String
    var lastName: String
    var gradYear: Int
    var university: University
    var interests: [Activity]
    /// When you agreed to "Before you chat". Nil until then; the server asks for it before your first message.
    var chatRulesAcceptedAt: Date?
    /// The beta tester badge (N37): set once, the first time you open a TestFlight build signed in.
    var isBetaTester = false

    var fullName: String { "\(firstName) \(lastName)" }

    /// How others see you.
    var summary: PersonSummary {
        PersonSummary(
            id: id, firstName: firstName, lastInitial: String(lastName.prefix(1)).uppercased(), gradYear: gradYear,
            isBetaTester: isBetaTester
        )
    }
}

/// What `complete_profile` takes: Set up profile and Edit profile & interests.
nonisolated struct ProfileInput: Hashable, Sendable {
    static let nameLimit = 30

    var firstName: String
    var lastName: String
    var gradYear: Int
    /// At least one.
    var interests: [Activity]
    var locale = "en"
}

/// The checks Set up profile and Edit profile share.
extension ProfileInput {
    enum NameProblem: Equatable {
        case missing
        /// Caught by `TextFilter`.
        case unfriendly
    }

    /// The parts of Make it yours and Edit profile that can have a problem, in screen order.
    enum Field: Hashable, CaseIterable {
        case firstName, lastName, interests
    }

    /// Class years to pick from: this year through six years out.
    static func classYears(now: Date = .now) -> [Int] {
        let year = Calendar.current.component(.year, from: now)
        return Array(year...(year + 6))
    }

    /// What's wrong with a first or last name, if anything. Each screen words the message.
    static func nameProblem(_ name: String) -> NameProblem? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return .missing }
        return TextFilter.isFriendly(name) ? nil : .unfriendly
    }
}

/// The name the school's sign-in gave us, as a starting point: students can edit it.
nonisolated struct SuggestedName: Hashable, Sendable {
    var first: String
    var last: String

    init(first: String, last: String) {
        self.first = first
        self.last = last
    }

    /// `metadata` is the string values of the Supabase user's `user_metadata`. Prefers separate
    /// first and last names, then splits a full name at the first space. B21 confirms the keys.
    init?(metadata: [String: String]) {
        let value = { (key: String) in metadata[key]?.trimmingCharacters(in: .whitespaces) ?? "" }
        if !value("given_name").isEmpty, !value("family_name").isEmpty {
            self.init(first: value("given_name"), last: value("family_name"))
            return
        }
        let full = value("full_name").isEmpty ? value("name") : value("full_name")
        let parts = full.split(separator: " ", maxSplits: 1).map(String.init)
        guard let first = parts.first else { return nil }
        self.init(first: first, last: parts.count > 1 ? parts[1] : "")
    }
}
