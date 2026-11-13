import Observation
import SwiftUI

/// Onboarding (E5, SPEC §7.5), driven by `AuthService`: sign up with a school email and a
/// password, wait for the team's approval (N36), then `complete_profile` and `accept_guidelines`.
/// The school SSO step (`findSchool`, `continueWithSchool`) is kept but nothing opens it.
@Observable
final class OnboardingViewModel {
    enum Step: Hashable {
        case signUp, signIn, pending, verified, guidelines
        /// "Make it yours": name, class year and sports on one screen.
        case about
        /// School SSO. Unreachable while sign-in is email and password (N36).
        case findSchool

        /// Past sign-in there's nothing to go back to, and past the profile it's already saved.
        var hidesBackButton: Bool {
            switch self {
            case .pending, .verified, .about, .guidelines: true
            case .signUp, .signIn, .findSchool: false
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

    /// At least this many characters, checked before the server's own rule.
    static let minimumPasswordLength = 8

    // Sign up and Sign in share these.
    var email = ""
    var password = ""

    // Only write back when the value changes: in an @Observable class an unconditional
    // write in didSet calls didSet again, forever.
    var firstName = "" { didSet { if firstName.count > 30 { firstName = String(firstName.prefix(30)) } } }
    var lastName = "" { didSet { if lastName.count > 30 { lastName = String(lastName.prefix(30)) } } }
    var classYear = Calendar.current.component(.year, from: .now) + 3
    var interests: Set<Activity> = []

    var signInError: String?
    var signUpError: String?
    var passwordError: String?
    /// "Check again" came back still waiting.
    private(set) var isStillPending = false
    var pendingError: String?
    var aboutError: String?
    var profileError: String?
    var guidelinesError: String?
    private(set) var isWorking = false
    /// Welcome → Browse as a guest couldn't pick an open campus.
    var guestBrowseError: String?
    private(set) var isStartingGuest = false

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
            path = [.signIn]
        case .pendingApproval:
            path = [.pending]
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
        if let campus { return "Pickup games around \(campus.shortName) that are one or two players short. Grab the open spot and play today." }
        return "Pickup games on campus that are one or two players short. Grab the open spot and play today."
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

    /// "Welcome to masUNO, Emilio." when the school told us a name; otherwise just the welcome.
    var verifiedWelcome: String {
        let first = firstName.trimmingCharacters(in: .whitespaces)
        return first.isEmpty ? String(localized: "Welcome to masUNO.") : String(localized: "Welcome to masUNO, \(first).")
    }

    /// "Tec de Monterrey · school account", under "Verified student".
    var verifiedSchoolLine: String {
        guard let school = selectedSchool ?? campus else { return String(localized: "School account") }
        return String(localized: "\(school.name) · school account")
    }

    /// The name from the school's sign-in, if it gave one.
    var verifiedName: String? {
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    var signUpMessage: LocalizedStringKey {
        if let campus { return "Use your \(campus.shortName) email (@\(campus.emailDomain)). We approve each account by hand, usually within a day." }
        return "Use your school email. We approve each account by hand, usually within a day."
    }

    var emailPlaceholder: String {
        campus.map { "you@\($0.emailDomain)" } ?? String(localized: "School email")
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces).lowercased() }

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

    /// "Others see Emilio G. and your class year."
    var previewLine: String {
        let name = ProfileInput.previewName(first: firstName, last: lastName)
        if name.isEmpty { return String(localized: "Others see your first name, last initial and class year.") }
        return String(localized: "Others see \(name) and your class year.")
    }

    // MARK: Intents

    /// **Get started** on Welcome: "Quick check before you join". Location is asked on the map (C11).
    func getStarted() {
        isSignInSheetPresented = true
    }

    func createAccount() {
        isSignInSheetPresented = false
        path.append(.signUp)
    }

    func haveAnAccount() {
        isSignInSheetPresented = false
        path.append(.signIn)
    }

    /// After guest browse: jump straight to Create account or Sign in.
    /// - Parameter resume: Which step to open.
    func applyResume(_ resume: AppViewModel.OnboardingResume) {
        switch resume {
        case .signUp: path = [.signUp]
        case .signIn: path = [.signIn]
        }
    }

    /// Picks an open campus and asks the app to show the guest map (SPEC R7-15).
    /// - Parameter app: Root presentation; starts guest browse.
    /// - Parameter store: Loads nameless games for that campus.
    func browseAsGuest(app: AppViewModel, store: GameStore) async {
        guard !isStartingGuest else { return }
        guestBrowseError = nil
        isStartingGuest = true
        defer { isStartingGuest = false }

        if let campus {
            await app.browseAsGuest(campus: campus, store: store)
            return
        }

        do {
            let open = try await catalog.fetchUniversities().filter(\.signupEnabled)
            guard let campus = open.first, open.count == 1 else {
                guestBrowseError = open.isEmpty
                    ? String(localized: "Browsing isn't open on any campus yet. Create an account to join the wait.")
                    : String(localized: "Create an account or sign in to pick your campus.")
                return
            }
            await app.browseAsGuest(campus: campus, store: store)
        } catch {
            guestBrowseError = (error as? DomainError ?? .offline).message
        }
    }

    /// Creates the account and lands on "We're checking your account"; an allowlisted address
    /// skips the wait.
    func submitSignUp() async {
        guard !trimmedEmail.isEmpty, !password.isEmpty, !isWorking else { return }
        signUpError = nil
        passwordError = nil
        guard password.count >= Self.minimumPasswordLength else {
            passwordError = DomainError.weakPassword.message
            return
        }
        await work {
            try await auth.signUp(email: trimmedEmail, password: password)
            password = ""
            advance()
        } onError: { signUpError = $0 }
    }

    /// "Check again" on the waiting step, and every time the app comes back to it.
    func checkApproval(quietly: Bool = false) async {
        guard auth.state == .pendingApproval, !isWorking else { return }
        pendingError = nil
        await work {
            try await auth.refreshStatus()
            isStillPending = auth.state == .pendingApproval && !quietly
            if auth.state == .needsProfile {
                fillInName()
                path = [.verified]
            } else {
                advance()
            }
        } onError: { if !quietly { pendingError = $0 } }
    }

    /// Leaves the waiting step for Welcome. The request stays, so signing back in picks it up.
    func signOutWhilePending() async {
        pendingError = nil
        await work {
            try await auth.signOut()
            password = ""
            path = []
        } onError: { pendingError = $0 }
    }

    // MARK: School SSO (unused, N36)

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

    // MARK: Sign in and profile

    func submitSignIn() async {
        guard !trimmedEmail.isEmpty, !password.isEmpty, !isWorking else { return }
        signInError = nil
        await work {
            try await auth.signIn(email: trimmedEmail, password: password)
            password = ""
            advance()
        } onError: { signInError = $0 }
    }

    /// Checks the name before anything goes to the server. Returns whether it's fine.
    private func validateName() -> Bool {
        for name in [firstName, lastName] {
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                aboutError = String(localized: "Add your first and last name.")
                return false
            }
            if !TextFilter.isFriendly(name) {
                aboutError = TextFilter.message
                return false
            }
        }
        aboutError = nil
        return true
    }

    func toggle(_ sport: Activity) {
        if interests.contains(sport) { interests.remove(sport) } else { interests.insert(sport) }
    }

    /// **Let's play** on Make it yours: name, class year and at least one sport.
    func submitProfile() async {
        profileError = nil
        guard validateName() else { return }
        guard !interests.isEmpty else {
            profileError = String(localized: "Pick at least one sport.")
            return
        }
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
        case .pendingApproval:
            path = [.pending]
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
