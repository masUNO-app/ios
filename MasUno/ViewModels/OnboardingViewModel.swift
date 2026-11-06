import Foundation
import Observation

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

    static let domain = "@tec.mx"

    @ObservationIgnored private let auth: any AuthService

    /// Picks up where the session is: an expired session prefills the email, and someone
    /// who quit halfway through continues with the step they left.
    init(auth: any AuthService) {
        self.auth = auth
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
        let local = email.split(separator: "@").first.map(String.init) ?? ""
        return "\(local.prefix(2))…\(Self.domain)"
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

    /// Asks `sign_in_method` first: review accounts are Gmail aliases, so the `@tec.mx`
    /// check only applies to people signing in with a code.
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
            guard trimmed.hasSuffix(Self.domain), trimmed.count > Self.domain.count else { throw DomainError.emailNotAllowed }
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
            onError((error as? DomainError ?? .offline).message)
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
