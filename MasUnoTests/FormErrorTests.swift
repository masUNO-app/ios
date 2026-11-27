import Foundation
import Testing
@testable import masUNO

/// Where VoiceOver goes and what it says after a submit finds a problem (A11Y-04), and the
/// players stepper's swipe (A11Y-14). The first field is always the first one on screen.
@MainActor
struct FormErrorTests {
    // MARK: Game form

    /// Everything wrong at once: no name, a start that already passed, no place, unfriendly words.
    private func brokenForm() -> GameFormViewModel {
        let form = GameFormViewModel()
        form.day = Calendar.current.startOfDay(for: .now)
        form.time = form.day
        form.meetUpSpot = "pinche bleachers"
        form.notes = "no pendejo"
        form.showsErrors = true
        return form
    }

    @Test func nothingIsReportedBeforeTheFirstTry() {
        let form = GameFormViewModel()
        #expect(form.firstInvalidField == nil)
        #expect(form.errorSummary == nil)
    }

    @Test func theFirstInvalidFieldFollowsTheFormsOrder() {
        let form = brokenForm()
        #expect(form.firstInvalidField == .name)
        form.name = "After-work hoops"
        #expect(form.firstInvalidField == .time)
        form.day = Calendar.current.date(byAdding: .day, value: 1, to: form.day)!
        #expect(form.firstInvalidField == .place)
        form.place = MockFixtures.Places.basketballCourts
        #expect(form.firstInvalidField == .meetUp)
        form.meetUpSpot = "By the bleachers"
        #expect(form.firstInvalidField == .notes)
        form.notes = "Casual 3-on-3."
        #expect(form.firstInvalidField == nil)
        #expect(form.errorSummary == nil)
    }

    @Test func theSummarySaysTheFirstProblemAndHowMany() throws {
        let form = brokenForm()
        let nameError = try #require(form.nameError)
        #expect(form.errorSummary == "5 things to fix. \(nameError)")
        form.name = "After-work hoops"
        form.day = Calendar.current.date(byAdding: .day, value: 1, to: form.day)!
        form.place = MockFixtures.Places.basketballCourts
        form.meetUpSpot = ""
        #expect(form.errorSummary == form.notesError)
    }

    @Test func aServerErrorIsTheSummaryWhenNoFieldHasOne() {
        let form = GameFormViewModel()
        form.formError = DomainError.offline.message
        #expect(form.firstInvalidField == nil)
        #expect(form.errorSummary == DomainError.offline.message)
    }

    @Test func swipingThePlayersStaysInRange() {
        let form = GameFormViewModel()
        form.players = form.playersRange.upperBound
        form.stepPlayers(by: 1)
        #expect(form.players == form.playersRange.upperBound)
        form.stepPlayers(by: -1)
        #expect(form.players == form.playersRange.upperBound - 1)
        form.players = form.playersRange.lowerBound
        form.stepPlayers(by: -1)
        #expect(form.players == form.playersRange.lowerBound)
    }

    @Test func editingCantSwipeBelowTheNumberGoing() throws {
        let going = try #require(MockFixtures.world(now: .now).games.first { $0.id == MockFixtures.GameID.going })
        let form = GameFormViewModel(editing: going)
        form.players = form.minimumPlayers
        form.stepPlayers(by: -1)
        #expect(form.players == max(GameFormViewModel.playerRange.lowerBound, going.goingCount))
    }

    // MARK: Edit profile

    private func profileEditor() -> ProfileEditorViewModel {
        ProfileEditorViewModel(profile: MockFixtures.world(now: .now).me)
    }

    @Test func editProfileGoesFirstNameLastNameThenSports() throws {
        let editor = profileEditor()
        editor.firstName = ""
        editor.lastName = " "
        editor.interests = []
        #expect(editor.firstInvalidField == nil)
        editor.showsErrors = true
        #expect(editor.firstInvalidField == .firstName)
        let missing = try #require(editor.nameError(""))
        #expect(editor.errorSummary == "3 things to fix. \(missing)")
        editor.firstName = "Emilio"
        #expect(editor.firstInvalidField == .lastName)
        editor.lastName = "Garza"
        #expect(editor.firstInvalidField == .interests)
        #expect(editor.errorSummary == editor.interestsError)
        editor.interests = [Activity.builtIn[0]]
        #expect(editor.firstInvalidField == nil)
        #expect(editor.errorSummary == nil)
    }

    // MARK: Onboarding

    private func onboarding(_ state: AuthState = .signedOut(expired: false)) -> (OnboardingViewModel, MockBackend) {
        let auth = MockBackend(state: state)
        return (OnboardingViewModel(auth: auth, catalog: auth, campus: MockFixtures.tec), auth)
    }

    @Test func signUpPointsAtTheFieldThatShowsTheError() async {
        let (model, _) = onboarding()
        model.email = "a0123@tec.mx"
        model.password = "short"
        await model.submitSignUp()
        #expect(model.firstInvalidField(on: .signUp) == .password)
        #expect(model.errorSummary(on: .signUp) == DomainError.weakPassword.message)

        model.email = "someone@gmail.com"
        model.password = "long-enough"
        await model.submitSignUp()
        #expect(model.firstInvalidField(on: .signUp) == .email)
        #expect(model.errorSummary(on: .signUp) == model.signUpError)

        // Email comes before password on the screen.
        model.passwordError = DomainError.weakPassword.message
        #expect(model.firstInvalidField(on: .signUp) == .email)
    }

    @Test func aWrongPasswordPointsAtPassword() async {
        let (model, _) = onboarding()
        model.email = "a0123@tec.mx"
        model.password = "wrong"
        await model.submitSignIn()
        #expect(model.signInError != nil)
        #expect(model.firstInvalidField(on: .signIn) == .password)
        #expect(model.errorSummary(on: .signIn) == model.signInError)
    }

    @Test func aRefusedCodePointsAtTheCodeButACheckErrorHasNoField() {
        let (model, _) = onboarding(.pendingApproval)
        model.pendingError = DomainError.offline.message
        #expect(model.firstInvalidField(on: .pending) == nil)
        #expect(model.errorSummary(on: .pending) == DomainError.offline.message)
        model.inviteError = DomainError.invalidInvite.message
        #expect(model.firstInvalidField(on: .pending) == .inviteCode)
        #expect(model.errorSummary(on: .pending) == DomainError.invalidInvite.message)
    }

    @Test func makeItYoursPointsAtTheNameThatsMissingThenSports() async {
        let (model, _) = onboarding(.needsProfile)
        model.firstName = "Emilio"
        model.lastName = ""
        await model.submitProfile()
        #expect(model.firstInvalidProfileField == .lastName)
        #expect(model.errorSummary(on: .about) == model.aboutError)

        model.firstName = ""
        await model.submitProfile()
        #expect(model.firstInvalidProfileField == .firstName)

        model.firstName = "Emilio"
        model.lastName = "Garza"
        model.interests = []
        await model.submitProfile()
        #expect(model.firstInvalidProfileField == .interests)
        #expect(model.errorSummary(on: .about) == model.profileError)
    }

    @Test func stepsWithoutFieldsPointNowhere() {
        let (model, _) = onboarding()
        model.signInError = DomainError.offline.message
        #expect(model.firstInvalidField(on: .about) == nil)
        #expect(model.firstInvalidField(on: .guidelines) == nil)
        #expect(model.firstInvalidProfileField == nil)
    }
}
