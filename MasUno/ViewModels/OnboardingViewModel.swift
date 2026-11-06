import Observation
import SwiftUI

/// Onboarding (E5, SPEC §7.5), driven by `AuthService`: `sign_in_method(email)`,
/// send/verify the code, `complete_profile`, `accept_guidelines`.
@Observable
final class OnboardingViewModel {
    enum Step: Hashable {
        case email, code, about, interests, guidelines
    }

    var path: [Step] = []

    var email = ""
    var password = ""
    /// Review accounts sign in with a password instead of a code (SPEC §8.4).
    private(set) var usesPassword = false
    // Only write back when the value changes: in an @Observable class an unconditional
    // write in didSet calls didSet again, forever.
    var code = "" { didSet { let clean = String(code.filter(\.isNumber).prefix(6)); if clean != code { code = clean } } }
    var firstName = "" { didSet { if firstName.count > 30 { firstName = String(firstName.prefix(30)) } } }
    var lastName = "" { didSet { if lastName.count > 30 { lastName = String(lastName.prefix(30)) } } }
    var classYear = Calendar.current.component(.year, from: .now) + 3
    var interests: Set<Activity> = []

    var emailError: String?
    var codeError: String?
    var aboutError: String?
    var profileError: String?
    var guidelinesError: String?
    private(set) var isWorking = false
    /// Seconds until "Resend code" is available.
    private(set) var resendIn = 0

    @ObservationIgnored private let auth: any AuthService
    /// The only open campus, if there's just one: the copy then names it.
    let campus: University?

    /// Picks up where the session is: an expired session prefills the email, and someone
    /// who quit halfway through continues with the step they left.
    init(auth: any AuthService, campus: University? = nil) {
        self.auth = auth
        self.campus = campus
        switch auth.state {
        case .signedOut(let email?):
            self.email = email
            path = [.email]
        case .needsProfile:
            path = [.about]
        case .needsGuidelines:
            path = [.guidelines]
        default:
            break
        }
    }

    // MARK: Presentation

    /// "a0…@tec.mx"
    var maskedEmail: String {
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return email }
        return "\(parts[0].prefix(2))…@\(parts[1])"
    }

    var welcomeMessage: LocalizedStringKey {
        if let campus { return "Pickup games around \(campus.shortName), one or two players short — and looking for you." }
        return "Pickup games around campus, one or two players short — and looking for you."
    }

    var continueTitle: LocalizedStringKey {
        if let campus { return "Continue with your \(campus.shortName) email" }
        return "Continue with your school email"
    }

    var emailTitle: LocalizedStringKey {
        if let campus { return "What's your \(campus.shortName) email?" }
        return "What's your school email?"
    }

    var emailLabel: LocalizedStringKey {
        if let campus { return "\(campus.shortName) email" }
        return "School email"
    }

    var emailPlaceholder: String {
        "you@\(campus?.emailDomain ?? "school.edu")"
    }

    /// Names the campus in the "not allowed" message when there's only one to name.
    private func message(for error: DomainError) -> String {
        if error == .emailNotAllowed, let campus {
            return String(localized: "masUNO is just for \(campus.shortName) students right now. Use your @\(campus.emailDomain) email.")
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

    /// Asks `sign_in_method`, which knows the open campuses and the review accounts.
    func submitEmail() async {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return }
        email = trimmed
        emailError = nil
        await work {
            let method = try await auth.signInMethod(for: trimmed)
            if method == .password {
                usesPassword = true
                return
            }
            try await auth.sendCode(to: trimmed)
            startResendTimer()
            path.append(.code)
        } onError: { emailError = $0 }
    }

    func submitPassword() async {
        emailError = nil
        await work {
            try await auth.signIn(email: email, password: password)
            advance()
        } onError: { emailError = $0 }
    }

    func verifyCode() async {
        guard code.count == 6, !isWorking else { return }
        codeError = nil
        await work {
            try await auth.verifyCode(code, email: email)
            advance()
        } onError: {
            codeError = $0
            code = ""
        }
    }

    func resendCode() async {
        guard resendIn == 0 else { return }
        codeError = nil
        await work {
            try await auth.sendCode(to: email)
            startResendTimer()
        } onError: { codeError = $0 }
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
        case .needsProfile: path.append(.about)
        case .needsGuidelines: path.append(.guidelines)
        default: break
        }
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

    private func startResendTimer() {
        resendIn = 30
        Task {
            while resendIn > 0 {
                try? await Task.sleep(for: .seconds(1))
                resendIn -= 1
            }
        }
    }
}
