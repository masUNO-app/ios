import Observation
import SwiftUI

/// Onboarding (E5, SPEC §7.5), driven by `AuthService`: school sign-in or a review account,
/// then `complete_profile` and `accept_guidelines`.
@Observable
final class OnboardingViewModel {
    enum Step: Hashable {
        case locationPrimer, findSchool, reviewAccount, verified, about, interests, guidelines

        /// Past sign-in there's nothing to go back to, and past the profile it's already saved.
        var hidesBackButton: Bool {
            switch self {
            case .verified, .about, .guidelines: true
            case .locationPrimer, .findSchool, .reviewAccount, .interests: false
            }
        }
    }

    var path: [Step] = []
    var isSignInSheetPresented = false

    private(set) var schools: [University] = []
    private(set) var isLoadingSchools = false
    private(set) var schoolsFailedToLoad = false
    var schoolSearch = ""
    var selectedSchool: University?

    // Review accounts only (SPEC §8.4).
    var email = ""
    var password = ""

    // Only write back when the value changes: in an @Observable class an unconditional
    // write in didSet calls didSet again, forever.
    var firstName = "" { didSet { if firstName.count > 30 { firstName = String(firstName.prefix(30)) } } }
    var lastName = "" { didSet { if lastName.count > 30 { lastName = String(lastName.prefix(30)) } } }
    var classYear = Calendar.current.component(.year, from: .now) + 3
    var interests: Set<Activity> = []

    var signInError: String?
    var reviewError: String?
    var aboutError: String?
    var profileError: String?
    var guidelinesError: String?
    private(set) var isWorking = false

    @ObservationIgnored private let auth: any AuthService
    @ObservationIgnored private let catalog: any AppConfigRepository
    /// The only open campus, if there's just one: the copy then names it.
    let campus: University?

    /// Picks up where the session is: an expired session goes back to Find your school, and
    /// someone who quit halfway through continues with the step they left.
    init(auth: any AuthService, catalog: any AppConfigRepository, campus: University? = nil) {
        self.auth = auth
        self.catalog = catalog
        self.campus = campus
        switch auth.state {
        case .signedOut(expired: true):
            path = [.findSchool]
        case .needsProfile:
            fillInName()
            path = [.about]
        case .needsGuidelines:
            path = [.guidelines]
        default:
            break
        }
    }

    // MARK: Presentation

    var welcomeMessage: LocalizedStringKey {
        if let campus { return "Pickup games around \(campus.shortName), one or two players short — and looking for you." }
        return "Pickup games around campus, one or two players short — and looking for you."
    }

    /// Matches the name, short name or domain, ignoring case and accents.
    var filteredSchools: [University] {
        let query = schoolSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return schools }
        return schools.filter { school in
            [school.name, school.shortName, school.emailDomain].contains {
                $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    var verifiedMessage: LocalizedStringKey {
        if let school = selectedSchool ?? campus { return "You're signed in with your \(school.name) account." }
        return "You're signed in with your school account."
    }

    /// Names the campus in the "not allowed" message when there's only one to name.
    private func message(for error: DomainError) -> String {
        if error == .emailNotAllowed, let campus {
            return String(localized: "masUNO is just for \(campus.shortName) students right now. Use your \(campus.shortName) school account.")
        }
        return error.message
    }

    var classYears: [Int] {
        let year = Calendar.current.component(.year, from: .now)
        return Array(year...(year + 6))
    }

    /// "Emilio G. · Class of 2029"
    var preview: String {
        let first = firstName.trimmingCharacters(in: .whitespaces)
        let last = lastName.trimmingCharacters(in: .whitespaces)
        let name = first.isEmpty ? String(localized: "Your name") : ProfileInput.previewName(first: first, last: last)
        return String(localized: "\(name) · Class of \(String(classYear))")
    }

    // MARK: Intents

    /// The primer explains location; the iOS prompt itself waits for the map (C11).
    func continueFromPrimer() {
        isSignInSheetPresented = true
    }

    func findMySchool() {
        isSignInSheetPresented = false
        path.append(.findSchool)
    }

    /// With a single school there's nothing to choose, so it's already selected.
    func loadSchools() async {
        guard schools.isEmpty, !isLoadingSchools else { return }
        isLoadingSchools = true
        schoolsFailedToLoad = false
        defer { isLoadingSchools = false }
        do {
            schools = try await catalog.fetchUniversities()
            if selectedSchool == nil, schools.count == 1 { selectedSchool = schools[0] }
        } catch {
            schoolsFailedToLoad = true
        }
    }

    /// Opens the school's own page. If the person closes it, `state` doesn't change, so they
    /// simply stay here.
    func continueWithSchool() async {
        guard let selectedSchool, !isWorking else { return }
        signInError = nil
        await work {
            try await auth.signIn(at: selectedSchool)
            switch auth.state {
            case .needsProfile:
                fillInName()
                path.append(.verified)
            case .needsGuidelines:
                path.append(.guidelines)
            default:
                break
            }
        } onError: { signInError = $0 }
    }

    func submitReviewAccount() async {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty, !password.isEmpty else { return }
        reviewError = nil
        await work {
            try await auth.signIn(email: trimmed, password: password)
            advance()
        } onError: { reviewError = $0 }
    }

    func submitAbout() {
        for name in [firstName, lastName] {
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                aboutError = String(localized: "Add your first and last name.")
                return
            }
            if !TextFilter.isFriendly(name) {
                aboutError = TextFilter.message
                return
            }
        }
        aboutError = nil
        path.append(.interests)
    }

    func toggle(_ sport: Activity) {
        if interests.contains(sport) { interests.remove(sport) } else { interests.insert(sport) }
    }

    func submitProfile() async {
        profileError = nil
        let input = ProfileInput(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            gradYear: classYear,
            interests: interests.sorted { $0.sortOrder < $1.sortOrder }
        )
        await work {
            try await auth.completeProfile(input)
            advance()
        } onError: { profileError = $0 }
    }

    func agreeToGuidelines() async {
        guidelinesError = nil
        await work {
            try await auth.acceptGuidelines()
        } onError: { guidelinesError = $0 }
    }

    // MARK: Helpers

    /// The step after sign-in or the profile. Signed in needs nothing: the root swaps to the map.
    private func advance() {
        switch auth.state {
        case .needsProfile:
            fillInName()
            path.append(.about)
        case .needsGuidelines:
            path.append(.guidelines)
        default:
            break
        }
    }

    /// A starting point from the school's sign-in, never over something already typed.
    private func fillInName() {
        guard firstName.isEmpty, lastName.isEmpty, let name = auth.suggestedName else { return }
        firstName = name.first
        lastName = name.last
    }

    private func work(_ body: () async throws -> Void, onError: (String) -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await body()
        } catch {
            onError(message(for: error as? DomainError ?? .offline))
        }
    }
}
