import Observation
import SwiftUI

/// Onboarding (E5, SPEC §7.5), driven by `AuthService`: sign up with a school email and a
/// password, enter the code from the email (N39), wait on the waitlist until the team or an invite
/// lets you in (N36, N37), then `complete_profile` and `accept_guidelines`. A forgotten password is
/// reset with an emailed code from Sign in.
/// The school SSO step (`findSchool`, `continueWithSchool`) is kept but nothing opens it.
@Observable
final class OnboardingViewModel {
    enum Step: Hashable {
        case signUp, signIn, pending, verified, guidelines
        /// "Check your email": the 6-digit sign-up code (N39).
        case verifyEmail
        /// Forgot your password: the emailed code and a new password.
        case resetPassword
        /// "Make it yours": name, class year and sports on one screen.
        case about
        /// School SSO. Unreachable while sign-in is email and password (N36).
        case findSchool
        /// "Which campus?" for Browse as a guest when several are open.
        case guestCampus

        /// Past sign-in there's nothing to go back to, and past the profile it's already saved.
        var hidesBackButton: Bool {
            switch self {
            // The code step offers "Use a different email" instead, so a restored session can't land
            // on Welcome while still signed in.
            case .verifyEmail, .pending, .verified, .about, .guidelines: true
            case .signUp, .signIn, .resetPassword, .findSchool, .guestCampus: false
            }
        }
    }

    /// The account fields a step can send VoiceOver to after a failed submit.
    enum Field: Hashable {
        case email, password, inviteCode, code, newPassword
    }

    var path: [Step] = []
    var isSignInSheetPresented = false

    private(set) var schools: [University] = []
    private(set) var isLoadingSchools = false
    private(set) var schoolsFailedToLoad = false
    var schoolSearch = ""
    var selectedSchool: University?
    /// The campus picked on the guest step.
    var guestCampusChoice: University?

    /// At least this many characters, checked before the server's own rule.
    static let minimumPasswordLength = 8
    /// Digits in an emailed code (`otp_length`, supabase/config.toml).
    static let codeLength = 6
    /// Supabase sends at most one code a minute to an address (`max_frequency`).
    static let resendInterval: TimeInterval = 60

    // Sign up and Sign in share these.
    var email = ""
    var password = ""
    /// A member's invite code (N37), typed on Create account or on the waitlist. Optional: without
    /// one, the account waits for the team. One typed on Create account is held until the email
    /// code is in, because redeeming needs the session the code brings.
    var inviteCode = ""

    // The code steps (N39).
    /// The address the sign-up code went to.
    private(set) var codeEmail: String?
    var code = ""
    var codeError: String?
    /// "We sent a new code", after Send a new code.
    private(set) var codeNotice: String?
    /// When the last sign-up code went out, for the minute before another can.
    private(set) var codeSentAt: Date?
    /// A restored session that still needs its code: none has been sent yet (`sendFirstCodeIfNeeded`).
    @ObservationIgnored private var needsFirstCode = false
    /// The address the reset code went to.
    private(set) var resetEmail: String?
    var resetCode = ""
    var newPassword = ""
    var resetError: String?
    var newPasswordError: String?
    private(set) var resetNotice: String?
    private(set) var resetSentAt: Date?

    // Only write back when the value changes: in an @Observable class an unconditional
    // write in didSet calls didSet again, forever.
    var firstName = "" { didSet { if firstName.count > 30 { firstName = String(firstName.prefix(30)) } } }
    var lastName = "" { didSet { if lastName.count > 30 { lastName = String(lastName.prefix(30)) } } }
    var classYear = Calendar.current.component(.year, from: .now) + 3
    var interests: Set<Activity> = []

    var signInError: String?
    /// Forgot your password with no email typed.
    var signInEmailError: String?
    var signUpError: String?
    var passwordError: String?
    /// "Check again" came back still waiting.
    private(set) var isStillPending = false
    var pendingError: String?
    /// The invite code was refused, at sign-up or on the waitlist. The account exists either way.
    var inviteError: String?
    /// Your place on the waitlist, 1 being next. Nil until it loads, or once you're in.
    private(set) var waitlistPosition: Int?
    var aboutError: String?
    var profileError: String?
    var guidelinesError: String?
    private(set) var isWorking = false
    /// Welcome → Browse as a guest couldn't pick an open campus.
    var guestBrowseError: String?
    private(set) var isStartingGuest = false

    /// Set by the root. A finished sign-in keeps the session, even if an earlier sign-out could not drop the token.
    @ObservationIgnored var onSignedIn: (() -> Void)?

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
        case .needsEmailVerification(let email):
            codeEmail = email
            needsFirstCode = true
            path = [.verifyEmail]
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
        if let campus { return "Plans around \(campus.shortName) that are just one or two people short. Grab the open spot and tag along today." }
        return "Plans on campus that are just one or two people short. Grab the open spot and tag along today."
    }

    /// The open campuses a guest can browse, narrowed by the search.
    var filteredOpenCampuses: [University] {
        let open = Set(schools.filter(\.signupEnabled).map(\.id))
        return filteredSchools.filter { open.contains($0.id) }
    }

    /// Search only earns its place on a long list.
    var guestCampusesNeedSearch: Bool { schools.filter(\.signupEnabled).count > 5 }

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
        return first.isEmpty ? String.app("Welcome to masUNO.") : String.app("Welcome to masUNO, \(first).")
    }

    /// "Tec de Monterrey · school account", under "Verified student".
    var verifiedSchoolLine: String {
        guard let school = selectedSchool ?? campus else { return String.app("School account") }
        return String.app("\(school.name) · school account")
    }

    /// The name from the school's sign-in, if it gave one.
    var verifiedName: String? {
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    var signUpMessage: LocalizedStringKey {
        if let campus { return "masUNO is invite-only for now. Use your \(campus.shortName) email (@\(campus.emailDomain)). With an invite code you're in right away; without one you join the waitlist." }
        return "masUNO is invite-only for now. Use your school email. With an invite code you're in right away; without one you join the waitlist."
    }

    /// The rate limit on codes is per hour, so it says so; the chat's "too fast" wording doesn't fit here.
    private func inviteMessage(for error: DomainError) -> String {
        error == .rateLimited ? String.app("Too many tries. Wait an hour and try again.") : message(for: error)
    }

    var emailPlaceholder: String {
        campus.map { "you@\($0.emailDomain)" } ?? String.app("School email")
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces).lowercased() }

    /// Names the campus in the "not allowed" message when there's only one to name.
    private func message(for error: DomainError) -> String {
        if error == .emailNotAllowed, let campus {
            return String.app("masUNO is just for \(campus.shortName) students right now. Use your \(campus.shortName) school account.")
        }
        return error.message
    }

    var classYears: [Int] { ProfileInput.classYears() }

    /// "Others see Emilio G. and your class year."
    var previewLine: String {
        let name = ProfileInput.previewName(first: firstName, last: lastName)
        if name.isEmpty { return String.app("Others see your first name, last initial and class year.") }
        return String.app("Others see \(name) and your class year.")
    }

    // MARK: Errors after a submit

    /// Where VoiceOver goes after a failed submit on `step`: the first field with a problem, in
    /// the order the step shows them. Each error shows on the field named here.
    func firstInvalidField(on step: Step) -> Field? {
        switch step {
        case .signUp: signUpError != nil ? .email : passwordError != nil ? .password : nil
        case .signIn: signInEmailError != nil ? .email : signInError != nil ? .password : nil
        case .pending: inviteError != nil ? .inviteCode : nil
        case .verifyEmail: codeError != nil ? .code : nil
        case .resetPassword: resetError != nil ? .code : newPasswordError != nil ? .newPassword : nil
        default: nil
        }
    }

    /// The same on Make it yours, whose name error shows under both name fields.
    var firstInvalidProfileField: ProfileInput.Field? {
        if aboutError != nil {
            return ProfileInput.nameProblem(firstName) == nil && ProfileInput.nameProblem(lastName) != nil ? .lastName : .firstName
        }
        return profileError != nil ? .interests : nil
    }

    /// What VoiceOver says after a failed submit on `step`, field or not.
    func errorSummary(on step: Step) -> String? {
        switch step {
        case .signUp: signUpError ?? passwordError
        case .signIn: signInEmailError ?? signInError
        case .pending: inviteError ?? pendingError
        case .verifyEmail: codeError
        case .resetPassword: resetError ?? newPasswordError
        case .about: aboutError ?? profileError
        default: nil
        }
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
        case .guestCampus: path = [.guestCampus]
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
            if open.count > 1 {
                path.append(.guestCampus)
            } else if let campus = open.first {
                await app.browseAsGuest(campus: campus, store: store)
            } else {
                guestBrowseError = String.app("Browsing isn't open on any campus yet. Create an account to join the wait.")
            }
        } catch {
            guestBrowseError = (error as? DomainError ?? .offline).message
        }
    }

    /// **Browse games** on the campus step.
    func startGuestBrowsing(app: AppViewModel, store: GameStore) async {
        guard let guestCampusChoice, !isStartingGuest else { return }
        isStartingGuest = true
        defer { isStartingGuest = false }
        await app.browseAsGuest(campus: guestCampusChoice, store: store)
    }

    /// Creates the account and opens Check your email, where the code moves it on (`submitCode`).
    /// The invite code waits there too.
    func submitSignUp() async {
        guard !trimmedEmail.isEmpty, !password.isEmpty, !isWorking else { return }
        signUpError = nil
        passwordError = nil
        inviteError = nil
        guard password.count >= Self.minimumPasswordLength else {
            passwordError = DomainError.weakPassword.message
            return
        }
        await work {
            let before = auth.state
            try await auth.signUp(email: trimmedEmail, password: password)
            password = ""
            // Signed in straight away: the project has "Confirm email" off, so there's no code.
            guard auth.state == before else { return await enterNewAccount() }
            showCodeStep(for: trimmedEmail, sentAt: .now)
        } onError: { signUpError = $0 }
    }

    /// **Continue** on Check your email: the account is verified, then on to the waitlist, You're in
    /// (allowlisted, sign-up open, or with an invite code), as the server says.
    func submitCode() async {
        guard let codeEmail, !isWorking else { return }
        codeError = nil
        codeNotice = nil
        guard let typed = Self.completeCode(code) else {
            codeError = DomainError.invalidCode.message
            return
        }
        await work {
            try await auth.verifyEmail(codeEmail, code: typed)
            code = ""
            await enterNewAccount()
        } onError: { codeError = $0 }
    }

    /// **Send a new code**, once a minute.
    func resendCode() async {
        guard let codeEmail, !isWorking else { return }
        codeError = nil
        codeNotice = nil
        await work {
            try await auth.resendVerification(to: codeEmail)
            codeSentAt = .now
            codeNotice = String.app("We sent a new code to \(codeEmail).")
        } onError: { codeError = $0 }
    }

    /// A restored session that still needs its code has had none sent yet, so the step sends one.
    /// Quiet: if it fails, Send a new code is right there.
    func sendFirstCodeIfNeeded() async {
        guard needsFirstCode, let codeEmail, !codeEmail.isEmpty else { return }
        needsFirstCode = false
        do {
            try await auth.resendVerification(to: codeEmail)
            codeSentAt = .now
        } catch {}
    }

    /// **Use a different email** on Check your email: back to Create account with the address to fix.
    /// A restored session is signed out first, so nobody is left signed in on Welcome.
    func useDifferentEmail() async {
        codeError = nil
        await work {
            if case .needsEmailVerification = auth.state { try await auth.signOut() }
            if let codeEmail { email = codeEmail }
            resetCodeStep()
            password = ""
            path = [.signUp]
        } onError: { codeError = $0 }
    }

    /// Seconds until Send a new code works again; 0 when it does.
    func secondsUntilResend(at date: Date, sentAt: Date?) -> Int {
        guard let sentAt else { return 0 }
        return max(0, Int((sentAt.addingTimeInterval(Self.resendInterval).timeIntervalSince(date)).rounded(.up)))
    }

    /// The digits of a full code, ignoring spaces and dashes; nil until all of them are there.
    static func completeCode(_ text: String) -> String? {
        let digits = text.filter(\.isASCII).filter(\.isNumber)
        return digits.count == codeLength && digits.count == text.filter { !$0.isWhitespace && $0 != "-" }.count ? digits : nil
    }

    /// **Use code** on the waitlist. On success it's You're in, as when the team approves.
    func redeemInviteWhileWaiting() async {
        guard auth.state == .pendingApproval, hasInviteCode, !isWorking else { return }
        inviteError = nil
        await work {
            do {
                try await auth.redeemInvite(inviteCode)
                inviteCode = ""
                enterAfterApproval()
            } catch {
                inviteError = inviteMessage(for: error as? DomainError ?? .offline)
            }
        } onError: { inviteError = $0 }
    }

    /// The place in line on the waitlist. Quiet: without it the step just doesn't show a number.
    func loadWaitlistPosition() async {
        guard auth.state == .pendingApproval else {
            waitlistPosition = nil
            return
        }
        do {
            waitlistPosition = try await auth.waitlistPosition()
        } catch {}
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
            noteIfSignedIn()
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

    /// An account that never entered its sign-up code gets a new one and the code step, rather
    /// than an error.
    func submitSignIn() async {
        guard !trimmedEmail.isEmpty, !password.isEmpty, !isWorking else { return }
        signInError = nil
        signInEmailError = nil
        await work {
            do {
                try await auth.signIn(email: trimmedEmail, password: password)
            } catch DomainError.emailNotVerified {
                password = ""
                return try await sendCodeAndShowStep(for: trimmedEmail)
            }
            noteIfSignedIn()
            password = ""
            advance()
        } onError: { signInError = $0 }
    }

    /// **Forgot your password?** on Sign in: emails a code to the address typed there.
    func forgotPassword() async {
        guard !isWorking else { return }
        signInError = nil
        signInEmailError = nil
        guard !trimmedEmail.isEmpty else {
            signInEmailError = String.app("Type your email first, and we'll send it a code.")
            return
        }
        await work {
            try await auth.requestPasswordReset(for: trimmedEmail)
            resetEmail = trimmedEmail
            resetSentAt = .now
            resetCode = ""
            newPassword = ""
            resetError = nil
            newPasswordError = nil
            resetNotice = nil
            path.append(.resetPassword)
        } onError: { signInError = $0 }
    }

    /// **Send a new code** on the reset step, once a minute.
    func resendResetCode() async {
        guard let resetEmail, !isWorking else { return }
        resetError = nil
        resetNotice = nil
        await work {
            try await auth.requestPasswordReset(for: resetEmail)
            resetSentAt = .now
            resetNotice = String.app("We sent a new code to \(resetEmail).")
        } onError: { resetError = $0 }
    }

    /// **Save password**: the code and a new password, then on as after signing in.
    func submitReset() async {
        guard let resetEmail, !isWorking else { return }
        resetError = nil
        newPasswordError = nil
        resetNotice = nil
        guard let typed = Self.completeCode(resetCode) else {
            resetError = DomainError.invalidCode.message
            return
        }
        guard newPassword.count >= Self.minimumPasswordLength else {
            newPasswordError = DomainError.weakPassword.message
            return
        }
        await work {
            try await auth.resetPassword(email: resetEmail, code: typed, newPassword: newPassword)
            resetCode = ""
            newPassword = ""
            password = ""
            noteIfSignedIn()
            // A reset can also be how an account first verifies, so it may be new.
            await enterNewAccount()
        } onError: { resetError = $0 }
    }

    /// Checks the name before anything goes to the server. Returns whether it's fine.
    private func validateName() -> Bool {
        for name in [firstName, lastName] {
            switch ProfileInput.nameProblem(name) {
            case .missing:
                aboutError = String.app("Add your first and last name.")
                return false
            case .unfriendly:
                aboutError = TextFilter.message
                return false
            case nil:
                continue
            }
        }
        aboutError = nil
        return true
    }

    func toggle(_ sport: Activity) {
        interests.toggle(sport)
    }

    /// **Let's play** on Make it yours: name, class year and at least one sport.
    func submitProfile() async {
        profileError = nil
        guard validateName() else { return }
        guard !interests.isEmpty else {
            profileError = String.app("Pick at least one.")
            return
        }
        let input = ProfileInput(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            gradYear: classYear,
            interests: interests.sorted { $0.sortOrder < $1.sortOrder },
            locale: LanguageSettings.shared.language
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
            noteIfSignedIn()
        } onError: { guidelinesError = $0 }
    }

    // MARK: Helpers

    /// Signed in for real. A leftover sign-out retry must not send them back out.
    private func noteIfSignedIn() {
        if case .signedIn = auth.state { onSignedIn?() }
    }

    /// The step after sign-in or the profile. Signed in needs nothing: the root swaps to the map.
    private func advance() {
        switch auth.state {
        case .needsEmailVerification(let email):
            codeEmail = email
            needsFirstCode = true
            path = [.verifyEmail]
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

    /// Approved while waiting, by the team or an invite: You're in, then the profile.
    private func enterAfterApproval() {
        guard auth.state == .needsProfile else { return advance() }
        waitlistPosition = nil
        fillInName()
        path = [.verified]
    }

    private var hasInviteCode: Bool { !Invite.normalized(inviteCode).isEmpty }

    /// Where a new account goes once it's signed in. A held invite code is redeemed first, so the
    /// waitlist doesn't flash past on the way to You're in. A refused code leaves the account on the
    /// waitlist with `inviteError`, where it can try again.
    private func enterNewAccount() async {
        if auth.state == .pendingApproval, hasInviteCode {
            do {
                try await auth.redeemInvite(inviteCode)
                inviteCode = ""
                return enterAfterApproval()
            } catch {
                inviteError = inviteMessage(for: error as? DomainError ?? .offline)
            }
        }
        if auth.state == .needsProfile { return enterAfterApproval() }
        advance()
    }

    private func showCodeStep(for email: String, sentAt: Date?) {
        resetCodeStep()
        codeEmail = email
        codeSentAt = sentAt
        path.append(.verifyEmail)
    }

    /// From Sign in. A code that went out less than a minute ago is still good, so that's no failure.
    private func sendCodeAndShowStep(for email: String) async throws {
        do {
            try await auth.resendVerification(to: email)
            showCodeStep(for: email, sentAt: .now)
        } catch DomainError.tooManyAttempts {
            showCodeStep(for: email, sentAt: .now)
        }
    }

    private func resetCodeStep() {
        code = ""
        codeError = nil
        codeNotice = nil
        codeSentAt = nil
        needsFirstCode = false
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
