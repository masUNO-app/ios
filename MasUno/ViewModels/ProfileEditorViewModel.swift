import Foundation
import Observation

/// Edit profile & interests (E21). Same fields as onboarding screens 4–5 (SPEC §7.5):
/// first and last name (≤ 30, filtered), class year and at least one sport.
/// No photos, bios, skill levels or follower counts.
@Observable
final class ProfileEditorViewModel {
    var firstName: String { didSet { firstName = Self.limited(firstName) } }
    var lastName: String { didSet { lastName = Self.limited(lastName) } }
    var classYear: Int
    var interests: Set<Sport>
    var showsErrors = false

    private let original: Profile
    static let nameLimit = 30

    init(profile: Profile) {
        original = profile
        firstName = profile.firstName
        lastName = profile.lastName
        classYear = profile.classYear
        interests = Set(profile.interests)
    }

    /// This year through six years out.
    var classYears: [Int] {
        let year = Calendar.current.component(.year, from: .now)
        return Array(year...(year + 6))
    }

    /// "Emilio G. · Class of 2029" — how others see you.
    var preview: String {
        let name = Person.display("\(firstName.trimmingCharacters(in: .whitespaces)) \(lastName.trimmingCharacters(in: .whitespaces))")
        return String(localized: "\(name) · Class of \(String(classYear))")
    }

    // MARK: Validation

    func nameError(_ value: String) -> String? {
        guard showsErrors else { return nil }
        if value.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "Add your name.") }
        return TextFilter.isFriendly(value) ? nil : TextFilter.message
    }

    var interestsError: String? {
        showsErrors && interests.isEmpty ? String(localized: "Pick at least one sport.") : nil
    }

    // MARK: Intents

    func toggle(_ sport: Sport) {
        if interests.contains(sport) { interests.remove(sport) } else { interests.insert(sport) }
    }

    /// Returns true when saved. TODO(B7): `complete_profile`; interests also drive the
    /// "New [sport] game near you" notification (2.0, B13).
    func save(in store: EventStore) -> Bool {
        showsErrors = true
        guard nameError(firstName) == nil, nameError(lastName) == nil, interestsError == nil else { return false }
        var profile = original
        profile.firstName = firstName.trimmingCharacters(in: .whitespaces)
        profile.lastName = lastName.trimmingCharacters(in: .whitespaces)
        profile.classYear = classYear
        profile.interests = Sport.postable.filter(interests.contains)
        store.profile = profile
        return true
    }

    private static func limited(_ value: String) -> String {
        value.count > nameLimit ? String(value.prefix(nameLimit)) : value
    }
}
