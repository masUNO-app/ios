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

    var classYears: [Int] { ProfileInput.classYears() }

    /// "Emilio G.": how others see you.
    var previewName: String {
        let name = ProfileInput.previewName(first: firstName, last: lastName)
        return name.isEmpty ? String.app("your first name and last initial") : name
    }

    // MARK: Validation

    func nameError(_ value: String) -> String? {
        guard showsErrors else { return nil }
        switch ProfileInput.nameProblem(value) {
        case .missing: return String.app("Add your name.")
        case .unfriendly: return TextFilter.message
        case nil: return nil
        }
    }

    var interestsError: String? {
        showsErrors && interests.isEmpty ? String.app("Pick at least one.") : nil
    }

    func error(for field: ProfileInput.Field) -> String? {
        switch field {
        case .firstName: nameError(firstName)
        case .lastName: nameError(lastName)
        case .interests: interestsError
        }
    }

    /// Where VoiceOver goes after a failed Save: the first part with a problem.
    var firstInvalidField: ProfileInput.Field? {
        ProfileInput.Field.allCases.first { error(for: $0) != nil }
    }

    /// What VoiceOver says after a failed Save: the first problem and how many there are, or the
    /// server's message.
    var errorSummary: String? {
        let errors = ProfileInput.Field.allCases.compactMap(error(for:))
        guard let first = errors.first else { return saveError }
        return errors.count == 1 ? first : String.app("\(errors.count) things to fix. \(first)")
    }

    // MARK: Intents

    func toggle(_ sport: Activity) {
        interests.toggle(sport)
    }

    /// Returns true when saved (`complete_profile`).
    func save(in store: GameStore) async -> Bool {
        guard !isSaving else { return false }
        showsErrors = true
        saveError = nil
        guard nameError(firstName) == nil, nameError(lastName) == nil, interestsError == nil else { return false }
        isSaving = true
        defer { isSaving = false }
        let input = ProfileInput(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            gradYear: classYear,
            interests: interests.sorted { $0.sortOrder < $1.sortOrder },
            locale: LanguageSettings.shared.language
        )
        do {
            try await store.updateProfile(input)
            return true
        } catch {
            guard !OperationCancellation.isCancellation(error) else { return false }
            saveError = (error as? DomainError ?? .offline).message
            return false
        }
    }

    private static func limited(_ value: String) -> String {
        String(value.prefix(ProfileInput.nameLimit))
    }
}
