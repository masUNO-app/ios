import SwiftUI

/// Onboarding (E5, SPEC §7.5) in the 1.0 look. Welcome → account or **Browse as a guest** (R7-15)
/// → "Quick check before you join" → Create account (school email + password) → We're checking
/// your account (the team approves by hand, N36) → You're verified → Make it yours → Before you
/// play → map. Coming back: Sign in. Guests who hit join/save/host return here via Create account
/// or Sign in. `AuthService` moves the session along; when it reaches signed in, the root swaps
/// to the map. The location primer is on the map now. `FindSchoolStep` (school SSO) is kept but
/// nothing navigates to it.
struct OnboardingFlow: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(GameStore.self) private var store
    @State private var viewModel: OnboardingViewModel

    init(auth: any AuthService, catalog: any AppConfigRepository, campus: University?) {
        _viewModel = State(initialValue: OnboardingViewModel(auth: auth, catalog: catalog, campus: campus))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack(path: $viewModel.path) {
            welcome
                .navigationDestination(for: OnboardingViewModel.Step.self) { step in
                    Group {
                        switch step {
                        case .signUp: SignUpStep(viewModel: viewModel)
                        case .signIn: SignInStep(viewModel: viewModel)
                        case .pending: PendingStep(viewModel: viewModel)
                        case .findSchool: FindSchoolStep(viewModel: viewModel)
                        case .verified: VerifiedStep(viewModel: viewModel)
                        case .about: ProfileStep(viewModel: viewModel)
                        case .guidelines: GuidelinesStep(viewModel: viewModel)
                        }
                    }
                    .tint(Theme.ink)
                    .navigationBarBackButtonHidden(step.hidesBackButton)
                }
        }
        .dialog(isPresented: $viewModel.isSignInSheetPresented) {
            DialogCard(
                systemImage: "checkmark.shield",
                title: Text("Quick check before you join"),
                message: Text("Create an account with your school email so other players know you're a real student. We approve each one by hand."),
                confirm: DialogAction("Create account") { viewModel.createAccount() },
                cancel: DialogAction("I already have an account") { viewModel.haveAnAccount() }
            )
        }
        .onAppear(perform: consumeResume)
        #if DEBUG
        .onAppear(perform: openDebugStep)
        #endif
    }

    /// Create account / Sign in after a guest tapped an account-only action.
    private func consumeResume() {
        guard let resume = appViewModel.onboardingResume else { return }
        appViewModel.clearOnboardingResume()
        viewModel.applyResume(resume)
    }

    /// Figma "Welcome": a court with room on it, and "We're looking for you."
    private var welcome: some View {
        CourtPage(lineup: .welcome()) {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: "masUNO")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("We're looking for you.")
                    .font(.rounded(.title2))
                    .foregroundStyle(Theme.ink)
                Text(viewModel.welcomeMessage)
                    .font(.rounded(.callout, .bold))
                    .foregroundStyle(Theme.mutedLarge)
                FlowLayout(spacing: 6) {
                    ForEach(Activity.builtIn.sorted { $0.sortOrder < $1.sortOrder }) { SportChip(sport: $0) }
                }
                .padding(.top, 2)
            }
        } footer: {
            VStack(spacing: 10) {
                Button("Get started") { viewModel.getStarted() }
                    .pill(.primary)
                Button("Browse as a guest") {
                    Task { await viewModel.browseAsGuest(app: appViewModel, store: store) }
                }
                .pill(.secondary)
                .disabled(viewModel.isStartingGuest)
                if let guestBrowseError = viewModel.guestBrowseError {
                    Text(verbatim: guestBrowseError)
                        .font(.rounded(.footnote))
                        .foregroundStyle(Theme.error)
                        .multilineTextAlignment(.center)
                }
                Link("Privacy & Terms", destination: appViewModel.config.privacyURL)
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.mutedLarge)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    #if DEBUG
    /// `-screen onboarding-sheet|signup|signin|pending|school|verified|about|guidelines`
    /// opens a step with sample input.
    private func openDebugStep() {
        guard let step = UserDefaults.standard.string(forKey: "screen"), step.hasPrefix("onboarding-") else { return }
        viewModel.firstName = "Emilio"
        viewModel.lastName = "Garza"
        viewModel.interests = [Activity.builtIn[0], Activity.builtIn[2], Activity.builtIn[1]]
        switch String(step.dropFirst("onboarding-".count)) {
        case "sheet": viewModel.getStarted()
        case "signup": viewModel.path = [.signUp]
        case "signin", "review": viewModel.path = [.signIn]
        case "pending": viewModel.path = [.pending]
        case "school": viewModel.path = [.findSchool]
        case "verified": viewModel.path = [.verified]
        case "about", "interests": viewModel.path = [.about]
        case "guidelines": viewModel.path = [.guidelines]
        default: break
        }
    }
    #endif
}

// MARK: - Steps

/// Create account: school email and a password. The server decides which addresses may sign up.
private struct SignUpStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var focus: Int?

    var body: some View {
        OnboardingPage(title: "Create your account", message: viewModel.signUpMessage) {
            FieldBox("School email", error: viewModel.signUpError, isFocused: focus == 0) {
                TextField(viewModel.emailPlaceholder, text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: 0)
            }
            FieldBox("Password", error: viewModel.passwordError, isFocused: focus == 1) {
                SecureField("At least 8 characters", text: $viewModel.password)
                    .textContentType(.newPassword)
                    .focused($focus, equals: 1)
                    .onSubmit { Task { await viewModel.submitSignUp() } }
            }
        } footer: {
            VStack(spacing: 10) {
                WorkingButton("Create account", isWorking: viewModel.isWorking) { Task { await viewModel.submitSignUp() } }
                    .disabled(viewModel.email.isEmpty || viewModel.password.isEmpty)
                Button("I already have an account") { viewModel.path = [.signIn] }
                    .pill(.quiet)
            }
        }
    }
}

/// Sign in, for students and for the review and demo accounts.
private struct SignInStep: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var focus: Int?

    var body: some View {
        OnboardingPage(title: "Sign in", message: "Welcome back. Use the email and password you signed up with.") {
            FieldBox("Email", isFocused: focus == 0) {
                TextField(viewModel.emailPlaceholder, text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: 0)
            }
            FieldBox("Password", error: viewModel.signInError, isFocused: focus == 1) {
                SecureField("Password", text: $viewModel.password)
                    .textContentType(.password)
                    .focused($focus, equals: 1)
                    .onSubmit { Task { await viewModel.submitSignIn() } }
            }
            // No reset email yet: the team resets a password by hand.
            if let mail = appViewModel.config.supportMailURL {
                Link("Forgot your password? Contact us", destination: mail)
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.mutedLarge)
            }
        } footer: {
            VStack(spacing: 10) {
                WorkingButton("Sign in", isWorking: viewModel.isWorking) { Task { await viewModel.submitSignIn() } }
                    .disabled(viewModel.email.isEmpty || viewModel.password.isEmpty)
                Button("Create an account") { viewModel.path = [.signUp] }
                    .pill(.quiet)
            }
        }
    }
}

/// We're checking your account: the team approves each sign-up by hand (N36). Checks again
/// whenever the app comes back to the front.
private struct PendingStep: View {
    @Environment(\.scenePhase) private var scenePhase
    var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingPage(
            systemImage: "hourglass",
            title: "We're checking your account",
            message: "We approve each account by hand, usually within a day. You don't need to do anything. Just come back later."
        ) {
            if let error = viewModel.pendingError {
                Text(verbatim: error).font(.rounded(.caption)).foregroundStyle(Theme.error)
            } else if viewModel.isStillPending {
                Text("Not yet. We'll get to it soon.").font(.rounded(.footnote)).foregroundStyle(Theme.muted)
            }
        } footer: {
            VStack(spacing: 10) {
                WorkingButton("Check again", isWorking: viewModel.isWorking) { Task { await viewModel.checkApproval() } }
                Button("Sign out") { Task { await viewModel.signOutWhilePending() } }
                    .pill(.quiet)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.checkApproval(quietly: true) } }
        }
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
                FieldBox("Search schools") {
                    TextField("Search your school", text: $viewModel.schoolSearch)
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

private struct SchoolRow: View {
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
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 66)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.accentSoft.opacity(0.6) : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Figma "You're verified!": you, on the court, and what happens next.
private struct VerifiedStep: View {
    var viewModel: OnboardingViewModel

    var body: some View {
        CourtPage(lineup: .welcome(includesYou: true)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("You're verified!")
                    .font(.rounded(.largeTitle, .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: viewModel.verifiedWelcome)
                    .font(.rounded(.title3))
                    .foregroundStyle(Theme.mutedLarge)
                Text("Next, tell us what you play so the right games show up first.")
                    .font(.rounded(.subheadline, .bold))
                    .foregroundStyle(Theme.mutedLarge)

                VStack(spacing: 0) {
                    row(title: Text("Verified student"), subtitle: viewModel.verifiedSchoolLine) {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 36, height: 36)
                            .background(Theme.accentSoft, in: .rect(cornerRadius: Theme.Radius.tile))
                    }
                    if let name = viewModel.verifiedName {
                        row(title: Text(verbatim: name), subtitle: String(localized: "Others only see your first name and last initial")) {
                            Text(verbatim: PersonToken.initials(of: name))
                                .font(.rounded(size: 13))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 36, height: 36)
                                .background(Theme.you, in: .rect(cornerRadius: Theme.Radius.tile))
                        }
                    }
                }
                .padding(.vertical, 6)
                .cardSurface()
                .padding(.top, 4)
            }
        } footer: {
            VStack(spacing: 8) {
                Button("Set up my profile") { viewModel.path.append(.about) }
                    .pill(.primary)
                Text("Takes about 20 seconds.")
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.mutedLarge)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func row(title: Text, subtitle: String, @ViewBuilder tile: () -> some View) -> some View {
        HStack(spacing: 14) {
            tile()
            VStack(alignment: .leading, spacing: 1) {
                title.font(.rounded(.body)).foregroundStyle(Theme.ink)
                Text(verbatim: subtitle).font(.rounded(.footnote)).foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
    }
}

/// Figma "Make it yours": your token, name, class year and what you play, on one screen.
private struct ProfileStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingPage(title: "Make it yours", message: nil) {
            MeToken(name: "\(viewModel.firstName) \(viewModel.lastName)", size: 80, ring: 4)
                .shadow(color: Theme.ink.opacity(0.08), radius: 6, y: 2)

            Text(verbatim: viewModel.previewLine)
                .font(.rounded(.subheadline))
                .foregroundStyle(Theme.muted)

            ProfileFields(
                firstName: $viewModel.firstName, lastName: $viewModel.lastName, classYear: $viewModel.classYear,
                classYears: viewModel.classYears
            )
            if let error = viewModel.aboutError {
                Text(verbatim: error).font(.rounded(.caption)).foregroundStyle(Theme.error)
            }

            Text("What do you play?")
                .font(.rounded(.callout, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 4)
            FlowLayout(spacing: 8) {
                ForEach(Activity.builtIn.filter(\.interestSelectable)) { sport in
                    SportToggle(sport: sport, isOn: viewModel.interests.contains(sport)) { viewModel.toggle(sport) }
                }
            }
            if let error = viewModel.profileError {
                Text(verbatim: error).font(.rounded(.caption)).foregroundStyle(Theme.error)
            } else {
                Text("Pick as many as you like. We'll show these first.")
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.muted)
            }
        } footer: {
            WorkingButton("Let's play", isWorking: viewModel.isWorking) { Task { await viewModel.submitProfile() } }
        }
    }
}

/// The community guidelines, agreed to once before the map (SPEC §7.5).
private struct GuidelinesStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingPage(
            systemImage: "checkmark.shield",
            title: "Before you play",
            message: "masUNO works because people show up and play fair."
        ) {
            CommunityRules()
                .padding(18)
                .cardSurface()
            SafetyNote(text: "You can report or block anyone from a game's Who's going list.")
            if let error = viewModel.guidelinesError {
                Text(verbatim: error).font(.rounded(.caption)).foregroundStyle(Theme.error)
            }
        } footer: {
            WorkingButton("I agree", isWorking: viewModel.isWorking) { Task { await viewModel.agreeToGuidelines() } }
        }
    }
}

// MARK: - Layout

/// A big rounded title, an optional icon above it and message under it, content, and a pinned
/// bottom action.
private struct OnboardingPage<Content: View, Footer: View>: View {
    var systemImage: String?
    var title: LocalizedStringKey
    var message: LocalizedStringKey?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    init(
        systemImage: String? = nil, title: LocalizedStringKey, message: LocalizedStringKey?,
        @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
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
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.rounded(.largeTitle, .bold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let message {
                        Text(message)
                            .font(.rounded(.body))
                            .foregroundStyle(Theme.muted)
                    }
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 4)
            .padding(.bottom, 16)
            .readableColumn()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .readableColumn()
                .background(Theme.background)
        }
    }
}

/// Welcome and You're verified: the top of a game's details, with the court as a picture (no
/// taps, hidden from VoiceOver), the content as its sheet, and a pinned bottom action.
private struct CourtPage<Content: View, Footer: View>: View {
    var lineup: Lineup
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        CourtScaffold(activity: Activity.builtIn[0], lineup: lineup, capacity: 6) { content }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .readableColumn()
                    .background(Theme.background)
            }
    }
}

/// The green pill, with a spinner while a request is out.
struct WorkingButton: View {
    var title: LocalizedStringKey
    var isWorking = false
    var action: () -> Void

    init(_ title: LocalizedStringKey, isWorking: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isWorking = isWorking
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if isWorking { ProgressView().tint(Theme.onAccent) } else { Text(title) }
        }
        // The steps are tinted ink for the back button; this stays green.
        .pill(.primary)
        .disabled(isWorking)
    }
}
