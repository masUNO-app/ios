import Foundation
import Observation

/// Edit profile & interests (E21). Same fields as onboarding screens 4–5 (SPEC §7.5):
/// first and last name (≤ 30, filtered), class year and at least one sport.
/// No photos, bios, skill levels or follower counts.
@Observable
final class ProfileEditorViewModel {
    // Only write back when over the limit (an unconditional write recurses in @Observable).
    var firstName: String { didSet { if firstName.count > ProfileInput.nameLimit { firstName = Self.limited(firstName) } } }
    var lastName: String { didSet { if lastName.count > ProfileInput.nameLimit { lastName = Self.limited(lastName) } } }
    var classYear: Int
    var interests: Set<Activity>
    var showsErrors = false
    private(set) var isSaving = false
    private(set) var saveError: String?

    init(profile: Profile) {
        firstName = profile.firstName
        lastName = profile.lastName
        classYear = profile.gradYear
        interests = Set(profile.interests)
    }

    /// This year through six years out.
    var classYears: [Int] {
        let year = Calendar.current.component(.year, from: .now)
        return Array(year...(year + 6))
    }

    /// "Emilio G.": how others see you.
    var previewName: String {
        let name = ProfileInput.previewName(first: firstName, last: lastName)
        return name.isEmpty ? String(localized: "your first name and last initial") : name
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

    func toggle(_ sport: Activity) {
        if interests.contains(sport) { interests.remove(sport) } else { interests.insert(sport) }
    }

    /// Returns true when saved (`complete_profile`).
    func save(in store: GameStore) async -> Bool {
        showsErrors = true
        saveError = nil
        guard nameError(firstName) == nil, nameError(lastName) == nil, interestsError == nil else { return false }
        isSaving = true
        defer { isSaving = false }
        let input = ProfileInput(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            gradYear: classYear,
            interests: interests.sorted { $0.sortOrder < $1.sortOrder }
        )
        do {
            try await store.updateProfile(input)
            return true
        } catch {
            saveError = (error as? DomainError ?? .offline).message
            return false
        }
    }

    private static func limited(_ value: String) -> String {
        String(value.prefix(ProfileInput.nameLimit))
    }
}
