import SwiftUI

/// Onboarding (E5, SPEC §7.5), Figma "Onboarding, reimagined" (0R): a practice round that
/// teaches by doing, then the account. Welcome → What do you play? → How do you want to start? →
/// the practice (join a pretend plan, or make one; or Skip the tour) → Make it official (school
/// email, password, optional invite code) → Check your email → in line, unless an invite code skips
/// it (N36, N37) → Make it yours → Five house rules → You're all set → map. Coming back: Sign in.
/// Guests who hit join/save/host return here via Create account or Sign in. `AuthService` moves the
/// session along; once it's signed in, the root swaps to the map after You're all set. The location
/// primer is on the map. `FindSchoolStep` (school SSO) is kept but nothing navigates to it.
struct OnboardingFlow: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(GameStore.self) private var store
    @State private var viewModel: OnboardingViewModel

    init(auth: any AuthService, catalog: any AppConfigRepository, campus: University?) {
        _viewModel = State(initialValue: OnboardingViewModel(auth: auth, catalog: catalog, campus: campus))
    }

    private func watchSignIn() {
        viewModel.onSignedIn = { [viewModel] in
            appViewModel.keepPracticePlan(viewModel.planToPost)
            appViewModel.noteSignInFinished()
        }
        viewModel.holdsOnboarding = { appViewModel.holdOnboarding($0) }
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack(path: $viewModel.path) {
            WelcomeScreen(viewModel: viewModel)
                .navigationDestination(for: OnboardingViewModel.Step.self) { step in
                    Group {
                        switch step {
                        case .sports: SportsStep(viewModel: viewModel)
                        case .start: StartStep(viewModel: viewModel)
                        case .practice(let mode): PracticeMapStep(viewModel: viewModel, mode: mode)
                        case .practiceJoined: PracticeJoinedStep(viewModel: viewModel)
                        case .allSet: AllSetStep(viewModel: viewModel)
                        case .signUp: SignUpStep(viewModel: viewModel)
                        case .signIn: SignInStep(viewModel: viewModel)
                        case .verifyEmail: VerifyEmailStep(viewModel: viewModel)
                        case .resetPassword: ResetPasswordStep(viewModel: viewModel)
                        case .pending: PendingStep(viewModel: viewModel)
                        case .findSchool: FindSchoolStep(viewModel: viewModel)
                        case .guestCampus: GuestCampusStep(viewModel: viewModel)
                        case .about: ProfileStep(viewModel: viewModel)
                        case .guidelines: GuidelinesStep(viewModel: viewModel)
                        }
                    }
                    .tint(Theme.ink)
                    .navigationBarBackButtonHidden(step.hidesBackButton)
                }
        }
        // The practice map lays out its pretend bars as the real map's: the iPhone Duo's vertical bar too.
        .readsBarLayout()
        .onAppear { watchSignIn() }
        .onAppear(perform: leaveGuestBrowsing)
        .onAppear(perform: consumeResume)
        #if DEBUG
        .onAppear(perform: openDebugStep)
        #endif
    }

    /// Let in while browsing from the line: the guest map's names-free games go.
    private func leaveGuestBrowsing() {
        guard appViewModel.isBrowsingAsGuest else { return }
        appViewModel.endGuestBrowsing(store: store)
    }

    /// Create account / Sign in after a guest tapped an account-only action.
    private func consumeResume() {
        guard let resume = appViewModel.onboardingResume else { return }
        appViewModel.clearOnboardingResume()
        viewModel.applyResume(resume)
    }

    #if DEBUG
    /// `-screen onboarding-welcome|sports|start|join1|join2|join3|host1|host2|host3|signup|signup-practice|signin|verify|reset|pending|pending-code|school|campus|about|guidelines|allset`
    /// opens a step with sample input. `join1…3` and `host1…3` are the practice round's three
    /// steps; `signup-practice` is Make it official after it. `verify` is Check your email after
    /// Create account; `reset` is the reset step after Forgot your password. `pending` is the
    /// waitlist with its place in line; `pending-code` is the same after a refused invite code.
    /// The mock's code is 123456.
    private func openDebugStep() {
        guard let step = UserDefaults.standard.string(forKey: "screen"), step.hasPrefix("onboarding-") else { return }
        viewModel.firstName = "Emilio"
        viewModel.lastName = "Garza"
        // Welcome starts fresh, so a test can pick on What do you play? itself.
        if step != "onboarding-welcome" {
            for slug in ["basketball", "soccer", "tennis"] {
                if let sport = Activity.builtIn.first(where: { $0.slug == slug }) { viewModel.togglePick(sport) }
            }
        }
        switch String(step.dropFirst("onboarding-".count)) {
        case "sports": viewModel.path = [.sports]
        case "start": viewModel.path = [.sports, .start]
        case "join1", "join2":
            viewModel.debugPracticeStage = step.hasSuffix("2") ? .popup : .findPin
            viewModel.path = [.sports, .start, .practice(.join)]
        case "join3":
            viewModel.takePracticeSpot()
            viewModel.path = [.sports, .start, .practice(.join), .practiceJoined]
        case "host1", "host2", "host3":
            viewModel.practiceMode = .host
            viewModel.debugPracticeStage = step.hasSuffix("1") ? .addButton : step.hasSuffix("2") ? .form : .ready
            viewModel.path = [.sports, .start, .practice(.host)]
        case "signup": viewModel.path = [.signUp]
        case "signup-practice":
            viewModel.takePracticeSpot()
            viewModel.path = [.signUp]
        case "signin", "review": viewModel.path = [.signIn]
        case "verify":
            Task {
                viewModel.path = [.signUp]
                viewModel.email = "a0123@tec.mx"
                viewModel.password = "long-enough"
                await viewModel.submitSignUp()
            }
        case "reset":
            // The mock has to know the address, so it signs up and verifies first, then signs out.
            Task {
                viewModel.email = "a0123@tec.mx"
                viewModel.password = "long-enough"
                await viewModel.submitSignUp()
                viewModel.code = MockFixtures.emailCode
                await viewModel.submitCode()
                await viewModel.signOutWhilePending()
                viewModel.email = "a0123@tec.mx"
                viewModel.path = [.signIn]
                await viewModel.forgotPassword()
            }
        case "pending", "pending-code":
            // Through sign-up and the code, so the mock account is really waiting and its place in line loads.
            let refused = step.hasSuffix("-code")
            Task {
                viewModel.email = "a0123@tec.mx"
                viewModel.password = "long-enough"
                viewModel.inviteCode = refused ? "WRONG-ONE" : ""
                await viewModel.submitSignUp()
                viewModel.code = MockFixtures.emailCode
                await viewModel.submitCode()
            }
        case "school": viewModel.path = [.findSchool]
        case "campus": viewModel.path = [.guestCampus]
        case "about", "interests": viewModel.path = [.about]
        case "guidelines": viewModel.path = [.guidelines]
        case "allset": viewModel.path = [.allSet]
        default: break
        }
    }
    #endif
}

// MARK: - Steps

/// Figma "Reimagined · C1 · Make it official" (513:7320): school email, a password, and a friend's
/// invite code to skip the line. The server decides which addresses may sign up. After the practice
/// round, a note at the top says it's done.
private struct SignUpStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var focus: Int?
    @AccessibilityFocusState private var errorFocus: OnboardingViewModel.Field?

    var body: some View {
        OnboardingPage(title: "Make it official", message: viewModel.makeItOfficialMessage) {
            if let line = viewModel.practiceDoneLine {
                PracticeDoneBanner(line: line)
            }
        } content: {
            FieldBox(
                "School email", text: $viewModel.email, prompt: Text(verbatim: viewModel.emailPlaceholder),
                error: viewModel.signUpError, isFocused: focus == 0
            ) { field in
                field
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: 0)
                    .accessibilityFocused($errorFocus, equals: .email)
            }
            FieldBox(
                "Password", text: $viewModel.password, prompt: Text("At least 8 characters"),
                error: viewModel.passwordError, isFocused: focus == 1, secure: true
            ) { field in
                field
                    .textContentType(.newPassword)
                    .focused($focus, equals: 1)
                    .accessibilityFocused($errorFocus, equals: .password)
                    .onSubmit { submit() }
            }
            FieldBox("Invite code (optional)", text: $viewModel.inviteCode, prompt: Text("ABCD-EFGH"), isFocused: focus == 2) { field in
                field
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focus, equals: 2)
                    .onSubmit { submit() }
            }
            Text("We use your email to sign you in. Other students never see it.")
                .font(.rounded(.footnote))
                .foregroundStyle(Theme.muted)
        } footer: {
            VStack(spacing: 10) {
                WorkingButton("Create account", isWorking: viewModel.isWorking) { submit() }
                    .disabled(viewModel.email.isEmpty || viewModel.password.isEmpty)
                Button("I already have an account") { viewModel.path = [.signIn] }
                    .pill(.quiet)
            }
        }
    }

    /// On a problem, VoiceOver moves to the field and says what's wrong.
    private func submit() {
        Task {
            await viewModel.submitSignUp()
            if let field = viewModel.firstInvalidField(on: .signUp) { errorFocus = field }
            if let summary = viewModel.errorSummary(on: .signUp) { Announce.post(summary, priority: .high) }
        }
    }
}

/// Sign in, for students and for the review and demo accounts.
private struct SignInStep: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var focus: Int?
    @AccessibilityFocusState private var errorFocus: OnboardingViewModel.Field?

    var body: some View {
        OnboardingPage(title: "Sign in", message: "Welcome back. Use the email and password you signed up with.") {
            FieldBox(
                "Email", text: $viewModel.email, prompt: Text(verbatim: viewModel.emailPlaceholder),
                error: viewModel.signInEmailError, isFocused: focus == 0
            ) { field in
                field
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: 0)
                    .accessibilityFocused($errorFocus, equals: .email)
            }
            FieldBox(
                "Password", text: $viewModel.password, prompt: Text("Password"),
                error: viewModel.signInError, isFocused: focus == 1, secure: true
            ) { field in
                field
                    .textContentType(.password)
                    .focused($focus, equals: 1)
                    .accessibilityFocused($errorFocus, equals: .password)
                    .onSubmit { submit() }
            }
            // A code to the email typed above (N39); Contact us stays for anything a code can't fix.
            HStack(spacing: 16) {
                Button { forgot() } label: {
                    Text("Forgot your password?")
                        .buttonShapeUnderline()
                        .tapTarget(.vertical, 15)
                }
                .disabled(viewModel.isWorking)
                if let mail = appViewModel.config.supportMailURL {
                    Link(destination: mail) {
                        Text("Contact us")
                            .buttonShapeUnderline()
                            .tapTarget(.vertical, 15)
                    }
                }
            }
            .font(.rounded(.footnote))
            .foregroundStyle(Theme.mutedLarge)
            // 44 pt tall to tap, in the same place: the 16 pt gaps above and below take it (A11Y-19).
            .padding(.vertical, -15)
        } footer: {
            VStack(spacing: 10) {
                WorkingButton("Sign in", isWorking: viewModel.isWorking) { submit() }
                    .disabled(viewModel.email.isEmpty || viewModel.password.isEmpty)
                Button("Create an account") { viewModel.path = [.signUp] }
                    .pill(.quiet)
            }
        }
    }

    /// On a problem, VoiceOver moves to the field and says what's wrong.
    private func submit() {
        Task {
            await viewModel.submitSignIn()
            if let field = viewModel.firstInvalidField(on: .signIn) { errorFocus = field }
            if let summary = viewModel.errorSummary(on: .signIn) { Announce.post(summary, priority: .high) }
        }
    }

    private func forgot() {
        Task {
            await viewModel.forgotPassword()
            if let field = viewModel.firstInvalidField(on: .signIn) { errorFocus = field }
            if let summary = viewModel.errorSummary(on: .signIn) { Announce.post(summary, priority: .high) }
        }
    }
}

/// "Check your email" (N39): the 6-digit code Supabase sent to the new account's address. iOS can
/// fill it in from Mail. Entering it moves the account on to the waitlist or You're in.
private struct VerifyEmailStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var isCodeFocused: Bool
    @AccessibilityFocusState private var errorFocus: OnboardingViewModel.Field?

    var body: some View {
        OnboardingPage(
            systemImage: "envelope.badge",
            title: "Check your email",
            message: "We sent a 6-digit code to \(viewModel.codeEmail ?? "")."
        ) {
            // The number pad has no return key: Continue is the way on.
            CodeBoxes(code: $viewModel.code, error: viewModel.codeError, isFocused: $isCodeFocused)
                .accessibilityFocused($errorFocus, equals: .code)
            if let notice = viewModel.codeNotice {
                Text(verbatim: notice).font(.rounded(.footnote)).foregroundStyle(Theme.muted)
            } else {
                Text("Can't find it? Check your spam or junk folder.").font(.rounded(.footnote)).foregroundStyle(Theme.muted)
            }
        } footer: {
            VStack(spacing: 10) {
                WorkingButton("Continue", isWorking: viewModel.isWorking) { submit() }
                    .disabled(OnboardingViewModel.completeCode(viewModel.code) == nil)
                ResendButton(sentAt: viewModel.codeSentAt, viewModel: viewModel) {
                    Task {
                        await viewModel.resendCode()
                        if let summary = viewModel.codeNotice ?? viewModel.errorSummary(on: .verifyEmail) {
                            Announce.post(summary, priority: .high)
                        }
                    }
                }
                Button("Use a different email") { Task { await viewModel.useDifferentEmail() } }
                    .pill(.quiet)
                    .disabled(viewModel.isWorking)
            }
        }
        .task {
            await viewModel.sendFirstCodeIfNeeded()
            isCodeFocused = true
        }
    }

    private func submit() {
        Task {
            await viewModel.submitCode()
            if let field = viewModel.firstInvalidField(on: .verifyEmail) { errorFocus = field }
            if let summary = viewModel.errorSummary(on: .verifyEmail) { Announce.post(summary, priority: .high) }
        }
    }
}

/// Forgot your password (N39): the code emailed to the address from Sign in, and a new password.
/// Saving signs you in.
private struct ResetPasswordStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var isCodeFocused: Bool
    @FocusState private var isPasswordFocused: Bool
    @AccessibilityFocusState private var errorFocus: OnboardingViewModel.Field?

    var body: some View {
        OnboardingPage(
            title: "Choose a new password",
            message: "If there's an account for \(viewModel.resetEmail ?? ""), we sent it a 6-digit code. Enter it with your new password."
        ) {
            CodeField(code: $viewModel.resetCode, error: viewModel.resetError, isFocused: $isCodeFocused)
                .accessibilityFocused($errorFocus, equals: .code)
            FieldBox(
                "New password", text: $viewModel.newPassword, prompt: Text("At least 8 characters"),
                error: viewModel.newPasswordError, isFocused: isPasswordFocused, secure: true
            ) { field in
                field
                    .textContentType(.newPassword)
                    .focused($isPasswordFocused)
                    .accessibilityFocused($errorFocus, equals: .newPassword)
                    .onSubmit { submit() }
            }
            if let notice = viewModel.resetNotice {
                Text(verbatim: notice).font(.rounded(.footnote)).foregroundStyle(Theme.muted)
            }
        } footer: {
            VStack(spacing: 10) {
                WorkingButton("Save password", isWorking: viewModel.isWorking) { submit() }
                    .disabled(OnboardingViewModel.completeCode(viewModel.resetCode) == nil || viewModel.newPassword.isEmpty)
                ResendButton(sentAt: viewModel.resetSentAt, viewModel: viewModel) {
                    Task {
                        await viewModel.resendResetCode()
                        if let summary = viewModel.resetNotice ?? viewModel.errorSummary(on: .resetPassword) {
                            Announce.post(summary, priority: .high)
                        }
                    }
                }
            }
        }
        .task { isCodeFocused = true }
    }

    private func submit() {
        Task {
            await viewModel.submitReset()
            if let field = viewModel.firstInvalidField(on: .resetPassword) { errorFocus = field }
            if let summary = viewModel.errorSummary(on: .resetPassword) { Announce.post(summary, priority: .high) }
        }
    }
}

/// The 6-digit field on both code steps. Digits only, and iOS offers the code from Mail.
private struct CodeField: View {
    @Binding var code: String
    var error: String?
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        FieldBox(
            "Code", text: $code, prompt: Text(verbatim: "123456"),
            error: error, isFocused: isFocused.wrappedValue
        ) { field in
            field
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled()
                .font(.rounded(.title2, .bold).monospacedDigit())
                .focused(isFocused)
                .onChange(of: code) { _, new in
                    // Keep it to the digits of one code, whatever was pasted.
                    let digits = String(new.filter(\.isNumber).prefix(OnboardingViewModel.codeLength))
                    if digits != new { code = digits }
                }
        }
    }
}

/// Figma "Reimagined · C2 · Check your email" (513:7396): a box per digit, drawn over one real
/// text field, so iOS still offers the code from Mail and VoiceOver reads a single field.
private struct CodeBoxes: View {
    @Binding var code: String
    var error: String?
    var isFocused: FocusState<Bool>.Binding
    @ScaledMetric(relativeTo: .title2) private var boxHeight: CGFloat = 58

    var body: some View {
        let digits = Array(code)
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                TextField(String(), text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .autocorrectionDisabled()
                    .focused(isFocused)
                    // The boxes show the digits; the field underneath only takes them.
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .frame(maxWidth: .infinity, minHeight: boxHeight)
                    .accessibilityLabel(Text("Code"))
                    .accessibilityHint(Text(verbatim: error ?? ""))
                    .onChange(of: code) { _, new in
                        // Keep it to the digits of one code, whatever was pasted.
                        let digits = String(new.filter(\.isNumber).prefix(OnboardingViewModel.codeLength))
                        if digits != new { code = digits }
                    }
                HStack(spacing: 8) {
                    ForEach(0..<OnboardingViewModel.codeLength, id: \.self) { index in
                        box(index < digits.count ? String(digits[index]) : nil, isCurrent: isFocused.wrappedValue && index == min(digits.count, OnboardingViewModel.codeLength - 1))
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .contentShape(.rect)
            .onTapGesture { isFocused.wrappedValue = true }
            if let error {
                Text(verbatim: error)
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.error)
                    // Read as the field's hint.
                    .accessibilityHidden(true)
            }
        }
    }

    private func box(_ digit: String?, isCurrent: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Theme.card)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(error != nil ? Theme.error : isCurrent ? Theme.accent : Theme.hairline, lineWidth: isCurrent || error != nil ? 2 : 1)
            }
            .overlay {
                if let digit {
                    Text(verbatim: digit)
                        .font(.rounded(.title2, .bold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                } else if isCurrent {
                    Capsule().fill(Theme.accent).frame(width: 2, height: boxHeight * 0.4)
                }
            }
            .frame(maxWidth: .infinity, minHeight: boxHeight)
    }
}

/// "Practice round done" over Make it official.
private struct PracticeDoneBanner: View {
    var line: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 36, height: 36)
                .background(Theme.accent, in: .rect(cornerRadius: Theme.Radius.tile))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Practice round done")
                    .font(.rounded(.callout, .bold))
                    .foregroundStyle(Theme.ink)
                Text(verbatim: line)
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.accentSoft, in: .rect(cornerRadius: Theme.Radius.field))
        .accessibilityElement(children: .combine)
    }
}

/// "Send a new code", counting down the minute Supabase makes you wait between codes.
private struct ResendButton: View {
    var sentAt: Date?
    var viewModel: OnboardingViewModel
    var action: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wait = viewModel.secondsUntilResend(at: context.date, sentAt: sentAt)
            Button(action: action) {
                if wait > 0 {
                    Text("Send a new code in \(wait)s")
                } else {
                    Text("Send a new code")
                }
            }
            .pill(.secondary)
            .disabled(wait > 0 || viewModel.isWorking)
        }
    }
}

/// Figma "Reimagined · C3 · You're in line" (513:7470): your place in line, a friend's invite code
/// to skip it, a heads-up when you're in, and the campus's plans to browse meanwhile. The team lets
/// people in as spots open (N36, N37). Checks again when the app comes back to the front, and every
/// half minute while it's on screen.
private struct PendingStep: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PushNotificationService.self) private var push
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(GameStore.self) private var store
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var isCodeFocused: Bool
    @AccessibilityFocusState private var errorFocus: OnboardingViewModel.Field?

    var body: some View {
        let position = viewModel.waitlistPosition
        let title: LocalizedStringKey = if let position { "You're #\(position) in line" } else { "You're on the waitlist" }
        OnboardingPage(
            systemImage: "ticket",
            title: title,
            // "#12" can be read as "pound 12".
            spokenTitle: position.map { Text("You're number \($0) in line") },
            message: viewModel.waitlistMessage
        ) {
            if let position, let ahead = viewModel.waitlistAheadLine {
                LineCard(ahead: position - 1, line: ahead)
            }

            FieldBox(
                "Invite code", text: $viewModel.inviteCode, prompt: Text("ABCD-EFGH"),
                error: viewModel.inviteError, isFocused: isCodeFocused
            ) { field in
                field
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($isCodeFocused)
                    .accessibilityFocused($errorFocus, equals: .inviteCode)
                    .onSubmit { redeem() }
            }
            Button("Use invite code") { redeem() }
                .pill(.secondary)
                .disabled(Invite.normalized(viewModel.inviteCode).isEmpty || viewModel.isWorking)

            if let error = viewModel.pendingError {
                Text(verbatim: error).font(.rounded(.caption)).foregroundStyle(Theme.error)
            }
        } footer: {
            VStack(spacing: 10) {
                let asksForAlerts = push.authorizationStatus == .notDetermined
                if asksForAlerts {
                    Button("Notify me when I'm in") { Task { await push.requestPermission() } }
                        .pill(.primary)
                }
                if let campus = viewModel.campus {
                    Button("Browse plans around \(campus.shortName)") {
                        Task { await appViewModel.browseAsGuest(campus: campus, store: store) }
                    }
                    .pill(asksForAlerts ? .secondary : .primary)
                }
                Button("Sign out") { Task { await viewModel.signOutWhilePending() } }
                    .pill(.quiet)
            }
        }
        .task { await viewModel.loadWaitlistPosition() }
        // While it's on screen, a quiet check every half minute: being let in moves it on.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await viewModel.checkApproval(quietly: true)
            await viewModel.loadWaitlistPosition()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                await viewModel.checkApproval(quietly: true)
                await viewModel.loadWaitlistPosition()
            }
        }
    }

    /// On a refused code, VoiceOver moves to the field and says why.
    private func redeem() {
        Task {
            await viewModel.redeemInviteWhileWaiting()
            if let field = viewModel.firstInvalidField(on: .pending) { errorFocus = field }
            if let summary = viewModel.errorSummary(on: .pending) { Announce.post(summary, priority: .high) }
        }
    }
}

/// The people ahead of you as faces (nobody's named: they're stand-ins), an arrow, and You.
private struct LineCard: View {
    var ahead: Int
    var line: String
    private static let shown = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                HStack(spacing: -6) {
                    ForEach(0..<min(ahead, Self.shown), id: \.self) { index in
                        PersonToken(initials: "", color: index.isMultiple(of: 2) ? Color(.person1) : Color(.person2), size: 34)
                    }
                    if ahead > Self.shown {
                        CountToken(count: ahead - Self.shown, size: 34)
                    }
                }
                if ahead > 0 {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                }
                YouToken(size: 40)
            }
            .accessibilityHidden(true)
            Text(verbatim: line)
                .font(.rounded(.headline, .bold))
                .foregroundStyle(Theme.ink)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft, in: .rect(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
    }
}

/// Figma "Find your school": school SSO. Not shown while sign-in is email and password (N36).
private struct FindSchoolStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingPage(
            title: "Find your school",
            message: "You'll sign in with the account your school gave you. masUNO never sees your password."
        ) {
            if viewModel.schoolsFailedToLoad {
                RetryCard(message: "Couldn't load schools.") { await viewModel.loadSchools() }
            } else if viewModel.isLoadingSchools {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                FieldBox("Search schools", text: $viewModel.schoolSearch, prompt: Text("Search your school")) { field in
                    field
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                schoolList
                Text("Don't see your school? masUNO is just for these campuses right now.")
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.muted)
            }
            if let error = viewModel.signInError {
                Text(verbatim: error).font(.rounded(.caption)).foregroundStyle(Theme.error)
            }
        } footer: {
            VStack(spacing: 10) {
                WorkingButton("Continue with school account", isWorking: viewModel.isWorking) {
                    Task { await viewModel.continueWithSchool() }
                }
                .disabled(viewModel.selectedSchool == nil)
                Button("Use email and password") { viewModel.path.append(.signIn) }
                    .pill(.quiet)
            }
        }
        .task { await viewModel.loadSchools() }
    }

    private var schoolList: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.filteredSchools) { school in
                SchoolRow(school: school, isSelected: school.id == viewModel.selectedSchool?.id) {
                    viewModel.selectedSchool = school
                }
            }
        }
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .cardSurface()
    }
}

struct SchoolRow: View {
    var school: University
    var isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Text(verbatim: school.shortName.uppercased())
                    .font(.rounded(.caption2, .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(Theme.accentSoft, in: .rect(cornerRadius: Theme.Radius.tile))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: school.name).font(.rounded(.body)).foregroundStyle(Theme.ink)
                    Text(verbatim: school.emailDomain).font(.rounded(.footnote)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                RowAccessory()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 66)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { if isSelected { Theme.accentSoft.contrastOpacity(0.6) } }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Figma "Reimagined · C4 · Make it yours" (513:7567): you on a court, your name, class year and
/// what you're into, starting from the picks on What do you play?
private struct ProfileStep: View {
    @Environment(GameStore.self) private var store
    @Bindable var viewModel: OnboardingViewModel
    /// Props leaderboard (1.0): off unless they turn it on here or later in Settings.
    @State private var joinsLeaderboard = false
    @AccessibilityFocusState private var errorFocus: ProfileInput.Field?

    var body: some View {
        OnboardingPage(title: "Make it yours", message: nil) {
            ProfileCourt(
                sport: viewModel.picks.first ?? Activity.builtIn[0],
                name: "\(viewModel.firstName) \(viewModel.lastName)", firstName: viewModel.firstName
            )

            Text("This is you on every plan. \(viewModel.previewLine)")
                .font(.rounded(.subheadline))
                .foregroundStyle(Theme.muted)

            ProfileFields(
                firstName: $viewModel.firstName, lastName: $viewModel.lastName, classYear: $viewModel.classYear,
                classYears: viewModel.classYears,
                errorFocus: $errorFocus
            )
            if let error = viewModel.aboutError {
                Text(verbatim: error).font(.rounded(.caption)).foregroundStyle(Theme.error)
            }

            Text("What are you into?")
                .font(.rounded(.callout, .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 4)
            FlowLayout(spacing: 8) {
                // The server's catalog, so a sport added there can be picked at sign-up.
                ForEach(store.interestActivities) { sport in
                    SportToggle(sport: sport, isOn: viewModel.interests.contains(sport)) { viewModel.toggle(sport) }
                }
            }
            .task { await store.loadCatalogIfNeeded() }
            if let error = viewModel.profileError {
                Text(verbatim: error).font(.rounded(.caption)).foregroundStyle(Theme.error)
                    .accessibilityFocused($errorFocus, equals: .interests)
            } else if !viewModel.picks.isEmpty {
                Text("You picked these earlier. Tap to change.")
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.muted)
            } else {
                Text("Pick as many as you like. We'll show these first.")
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.muted)
            }

            Toggle(isOn: $joinsLeaderboard) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show me on the campus leaderboard")
                        .font(.rounded(.callout, .bold))
                        .foregroundStyle(Theme.ink)
                    Text("Top teammates, by props from people you play with. You can change this in Settings.")
                        .font(.rounded(.footnote))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)
            .padding(.top, 8)
        } footer: {
            WorkingButton("Continue", isWorking: viewModel.isWorking) { submit() }
        }
    }

    /// On a problem, VoiceOver moves to it and says what's wrong.
    private func submit() {
        Task {
            await viewModel.submitProfile()
            // Saved: the step moved on. The switch is a nice-to-have, so a failure stays quiet.
            if joinsLeaderboard, viewModel.path.last != .about { _ = try? await store.setPropsLeaderboardOptIn(true) }
            if let field = viewModel.firstInvalidProfileField { errorFocus = field }
            if let summary = viewModel.errorSummary(on: .about) { Announce.post(summary, priority: .high) }
        }
    }
}

/// A strip of court in your first sport with you in the middle, Alex and Ricardo, and an open spot.
private struct ProfileCourt: View {
    var sport: Activity
    var name: String
    var firstName: String

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                sport.color
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.white.opacity(0.45), lineWidth: 3)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
                    .padding(.top, -8)
                Circle()
                    .stroke(.white.opacity(0.45), lineWidth: 3)
                    .frame(width: 98, height: 98)
                    .position(x: size.width / 2, y: size.height * 0.57)
                PersonAvatar(person: PracticeRound.alex, size: 36)
                    .position(x: size.width * 0.22, y: size.height * 0.42)
                OpenSpotToken(size: 34, fillOpacity: 0.6)
                    .position(x: size.width * 0.3, y: size.height * 0.79)
                PersonAvatar(person: PracticeRound.ricardo, size: 36)
                    .position(x: size.width * 0.79, y: size.height * 0.52)
                VStack(spacing: 3) {
                    MeToken(name: name, size: 56, ring: 3)
                    Text(verbatim: firstName.isEmpty ? String.app("You") : firstName)
                        .font(.rounded(.footnote, .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }
                .position(x: size.width / 2, y: size.height * 0.5)
            }
        }
        .frame(height: 132)
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .inkOnColor()
        .animation(.snappy, value: name)
        // One picture for VoiceOver, so the initials on it aren't read one by one.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("You on a court, with \(PracticeRound.alex.firstName) and \(PracticeRound.ricardo.firstName)"))
        .accessibilityAddTraits(.isImage)
    }
}

/// Figma "Reimagined · C5 · House rules" (513:7684): the community guidelines, agreed to once
/// before the map (SPEC §7.5).
private struct GuidelinesStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingPage(
            systemImage: "checkmark.shield",
            title: "Five house rules",
            message: "Plans work when people show up and play nice."
        ) {
            CommunityRules()
                .padding(18)
                .cardSurface()
            SafetyNote(text: "You can report or block anyone from a plan's Who's going list.")
            if let error = viewModel.guidelinesError {
                Text(verbatim: error).font(.rounded(.caption)).foregroundStyle(Theme.error)
            }
        } footer: {
            WorkingButton("I agree", isWorking: viewModel.isWorking) { Task { await viewModel.agreeToGuidelines() } }
        }
    }
}

// MARK: - Layout

/// A big rounded title, an optional icon or banner above it and message under it, content, and a
/// pinned bottom action.
struct OnboardingPage<Top: View, Content: View, Footer: View>: View {
    var systemImage: String?
    var title: LocalizedStringKey
    /// What VoiceOver says for the title, when the words on screen read badly ("#12").
    var spokenTitle: Text?
    var message: LocalizedStringKey?
    @ViewBuilder var top: Top
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Where the content and the shown part of the screen end, for `MoreBelowHint`.
    @State private var contentBottom: CGFloat = 0
    @State private var scrollBottom: CGFloat = .infinity
    @State private var footerTop: CGFloat = .infinity
    @State private var scroll = ScrollPosition(edge: .top)

    /// The content runs on under the pinned buttons (or off the screen at accessibility sizes).
    private var hasMore: Bool {
        MoreBelowHint.isNeeded(
            contentBottom: contentBottom,
            shownBottom: typeSize.isAccessibilitySize ? scrollBottom : min(scrollBottom, footerTop)
        )
    }

    init(
        systemImage: String? = nil, title: LocalizedStringKey, spokenTitle: Text? = nil, message: LocalizedStringKey?,
        @ViewBuilder top: () -> Top, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer
    ) {
        self.systemImage = systemImage
        self.title = title
        self.spokenTitle = spokenTitle
        self.message = message
        self.top = top()
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 64, height: 64)
                        .background(Theme.accentSoft, in: .circle)
                        .padding(.top, 24)
                        .accessibilityHidden(true)
                }
                top
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.rounded(.largeTitle, .bold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                        .modifier(SpokenLabel(label: spokenTitle))
                    if let message {
                        Text(message)
                            .font(.rounded(.body))
                            .foregroundStyle(Theme.muted)
                    }
                }
                content
                // At accessibility sizes a pinned footer would cover half the screen, so the
                // buttons come after the text instead (A11Y-06).
                if typeSize.isAccessibilitySize { footer.padding(.top, 8) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .reportsBottom($contentBottom)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 4)
            .padding(.bottom, 16)
            .readableColumn()
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollPosition($scroll)
        .reportsBottom($scrollBottom)
        .background(Theme.background)
        .animation(.easeOut(duration: 0.2), value: hasMore)
        .overlay(alignment: .bottom) {
            if typeSize.isAccessibilitySize, hasMore { MoreBelowHint(scrollToEnd: scrollToEnd) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !typeSize.isAccessibilitySize {
                footer
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .readableColumn()
                    .background(Theme.background)
                    .reportsTop($footerTop)
                    .moreBelowHint(isShown: hasMore, scrollToEnd: scrollToEnd)
            }
        }
    }

    private func scrollToEnd() {
        withAnimation(.snappy) { scroll.scrollTo(edge: .bottom) }
    }
}

extension OnboardingPage where Top == EmptyView {
    init(
        systemImage: String? = nil, title: LocalizedStringKey, spokenTitle: Text? = nil, message: LocalizedStringKey?,
        @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer
    ) {
        self.init(
            systemImage: systemImage, title: title, spokenTitle: spokenTitle, message: message,
            top: { EmptyView() }, content: content, footer: footer
        )
    }
}

/// An accessibility label, only when there is one.
private struct SpokenLabel: ViewModifier {
    var label: Text?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(label)
        } else {
            content
        }
    }
}
