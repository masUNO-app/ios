import Foundation
import Observation

/// Onboarding (E5, SPEC §7.5) on mock auth.
/// TEMP: no real sign-in yet. TODO(B5): drive this from `AuthService` —
/// `sign_in_method(email)`, send/verify the code, `complete_profile`, `accept_guidelines`.
@Observable
final class OnboardingViewModel {
    enum Step: Hashable {
        case email, code, about, interests, guidelines
    }

    var path: [Step] = []

    var email = ""
    // Only write back when the value changes: in an @Observable class an unconditional
    // write in didSet calls didSet again, forever.
    var code = "" { didSet { let clean = String(code.filter(\.isNumber).prefix(6)); if clean != code { code = clean } } }
    var firstName = "" { didSet { if firstName.count > 30 { firstName = String(firstName.prefix(30)) } } }
    var lastName = "" { didSet { if lastName.count > 30 { lastName = String(lastName.prefix(30)) } } }
    var classYear = Calendar.current.component(.year, from: .now) + 3
    var interests: Set<Sport> = []
    var agreed = false

    var emailError: String?
    var codeError: String?
    var aboutError: String?
    private(set) var isWorking = false
    /// Seconds until "Resend code" is available.
    private(set) var resendIn = 0

    static let domain = "@tec.mx"

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
        let name = first.isEmpty ? String(localized: "Your name") : Person.display("\(first) \(last)")
        return String(localized: "\(name) · Class of \(String(classYear))")
    }

    // MARK: Intents

    func submitEmail() async {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.hasSuffix(Self.domain), trimmed.count > Self.domain.count else {
            emailError = String(localized: "masUNO is just for Tec students right now. Use your @tec.mx email.")
            return
        }
        email = trimmed
        emailError = nil
        await work { /* TODO(B5): AuthService.sendCode(to:) */ }
        startResendTimer()
        path.append(.code)
    }

    /// TEMP: any 6 digits work, except 000000 (shows the wrong-code message).
    func verifyCode() async {
        guard code.count == 6 else { return }
        await work { /* TODO(B5): AuthService.verify(code:) */ }
        guard code != "000000" else {
            codeError = String(localized: "That code didn't work. Check the email and try again.")
            code = ""
            return
        }
        codeError = nil
        path.append(.about)
    }

    func resendCode() async {
        guard resendIn == 0 else { return }
        await work { /* TODO(B5): AuthService.sendCode(to:) */ }
        startResendTimer()
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

    func toggle(_ sport: Sport) {
        if interests.contains(sport) { interests.remove(sport) } else { interests.insert(sport) }
    }

    /// The finished profile. TODO(B5): `complete_profile` + `accept_guidelines`.
    func profile() -> Profile {
        Profile(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            classYear: classYear,
            school: "Tec de Monterrey",
            isVerified: true,
            interests: Sport.postable.filter(interests.contains)
        )
    }

    // MARK: Helpers

    /// Stand-in for a network round trip.
    private func work(_ body: () -> Void) async {
        isWorking = true
        body()
        try? await Task.sleep(for: .milliseconds(600))
        isWorking = false
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
