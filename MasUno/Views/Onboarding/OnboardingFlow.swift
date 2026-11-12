import SwiftUI

/// Onboarding (E5, SPEC §7.5), built from the spec copy; 1.0 restyles it from Arianna's D2 frames.
/// Welcome → Location primer → Sign in to join (sheet) → Create account (school email + password)
/// → We're checking your account (the team approves by hand, N36) → You're in → about you →
/// interests → community guidelines → map. Coming back: Sign in.
/// `AuthService` moves the session along; when it reaches signed in, the root swaps to the map.
/// `FindSchoolStep` (school SSO) is kept but nothing navigates to it.
struct OnboardingFlow: View {
    @Environment(AppViewModel.self) private var appViewModel
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
                        case .locationPrimer: LocationPrimerStep(viewModel: viewModel)
                        case .signUp: SignUpStep(viewModel: viewModel)
                        case .signIn: SignInStep(viewModel: viewModel)
                        case .pending: PendingStep(viewModel: viewModel)
                        case .findSchool: FindSchoolStep(viewModel: viewModel)
                        case .verified: VerifiedStep(viewModel: viewModel)
                        case .about: AboutStep(viewModel: viewModel)
                        case .interests: InterestsStep(viewModel: viewModel)
                        case .guidelines: GuidelinesStep(viewModel: viewModel)
                        }
                    }
                    .tint(Theme.ink)
                    .navigationBarBackButtonHidden(step.hidesBackButton)
                }
        }
        .sheet(isPresented: $viewModel.isSignInSheetPresented) {
            SignInSheet(viewModel: viewModel)
        }
        #if DEBUG
        .onAppear(perform: openDebugStep)
        #endif
    }

    private var welcome: some View {
        OnboardingPage(
            systemImage: "sportscourt",
            title: "Find your next game",
            message: viewModel.welcomeMessage
        ) {
            EmptyView()
        } footer: {
            VStack(spacing: 12) {
                PrimaryAction("Continue") { viewModel.path.append(.locationPrimer) }
                Link("Privacy & Terms", destination: appViewModel.config.privacyURL)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    #if DEBUG
    /// `-screen onboarding-primer|sheet|signup|signin|pending|school|verified|about|interests|guidelines`
    /// opens a step with sample input.
    private func openDebugStep() {
        guard let step = UserDefaults.standard.string(forKey: "screen"), step.hasPrefix("onboarding-") else { return }
        viewModel.firstName = "Emilio"
        viewModel.lastName = "Garza"
        viewModel.interests = [Activity.builtIn[0], Activity.builtIn[2]]
        switch String(step.dropFirst("onboarding-".count)) {
        case "primer": viewModel.path = [.locationPrimer]
        case "sheet":
            viewModel.path = [.locationPrimer]
            viewModel.continueFromPrimer()
        case "signup": viewModel.path = [.locationPrimer, .signUp]
        case "signin", "review": viewModel.path = [.locationPrimer, .signIn]
        case "pending": viewModel.path = [.pending]
        case "school": viewModel.path = [.locationPrimer, .findSchool]
        case "verified": viewModel.path = [.verified]
        case "about": viewModel.path = [.about]
        case "interests": viewModel.path = [.about, .interests]
        case "guidelines": viewModel.path = [.guidelines]
        default: break
        }
    }
    #endif
}

// MARK: - Steps

private struct LocationPrimerStep: View {
    var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingPage(
            systemImage: "location",
            title: "See games near you",
            message: "The map uses your location to show nearby games. It never leaves your phone."
        ) {
            EmptyView()
        } footer: {
            PrimaryAction("Continue") { viewModel.continueFromPrimer() }
        }
    }
}

/// Sign in to join.
private struct SignInSheet: View {
    var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.title2.weight(.medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 56, height: 56)
                .background(Theme.accentSoft, in: .circle)
            Text("Quick check before you join")
                .font(.title2.bold())
                .foregroundStyle(Theme.ink)
            Text("Create an account with your school email so other players know you're a real student. We approve each one by hand.")
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            PrimaryAction("Create account") { viewModel.createAccount() }
            Button("I already have an account") { viewModel.haveAnAccount() }
                .buttonStyle(.glassProminent)
                .tint(Theme.accentSoft)
                .foregroundStyle(Theme.ink)
                .controlSize(.large)
                .buttonSizing(.flexible)
                .fontWeight(.semibold)
        }
        .padding(Theme.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
        .presentationDetents([.height(390)])
        .presentationDragIndicator(.visible)
    }
}

/// Create account: school email and a password. The server decides which addresses may sign up.
private struct SignUpStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingPage(title: "Create your account", message: viewModel.signUpMessage) {
            FieldBox("School email", error: viewModel.signUpError) {
                TextField(viewModel.emailPlaceholder, text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            FieldBox("Password", error: viewModel.passwordError) {
                SecureField("At least 8 characters", text: $viewModel.password)
                    .textContentType(.newPassword)
                    .onSubmit { Task { await viewModel.submitSignUp() } }
            }
        } footer: {
            VStack(spacing: 12) {
                PrimaryAction("Create account", isWorking: viewModel.isWorking) { Task { await viewModel.submitSignUp() } }
                    .disabled(viewModel.email.isEmpty || viewModel.password.isEmpty)
                Button("I already have an account") { viewModel.path = [.locationPrimer, .signIn] }
                    .font(.footnote)
                    .tint(Theme.muted)
            }
        }
    }
}

/// Sign in, for students and for the review and demo accounts.
private struct SignInStep: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingPage(title: "Sign in", message: "Welcome back. Use the email and password you signed up with.") {
            FieldBox("Email") {
                TextField(viewModel.emailPlaceholder, text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            FieldBox("Password", error: viewModel.signInError) {
                SecureField("Password", text: $viewModel.password)
                    .textContentType(.password)
                    .onSubmit { Task { await viewModel.submitSignIn() } }
            }
            // No reset email yet: the team resets a password by hand.
            if let mail = appViewModel.config.supportMailURL {
                Link("Forgot your password? Contact us", destination: mail)
                    .font(.footnote)
                    .tint(Theme.muted)
            }
        } footer: {
            VStack(spacing: 12) {
                PrimaryAction("Sign in", isWorking: viewModel.isWorking) { Task { await viewModel.submitSignIn() } }
                    .disabled(viewModel.email.isEmpty || viewModel.password.isEmpty)
                Button("Create an account") { viewModel.path = [.locationPrimer, .signUp] }
                    .font(.footnote)
                    .tint(Theme.muted)
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
            message: "We approve each account by hand, usually within a day. You don't need to do anything — just come back later."
        ) {
            if let error = viewModel.pendingError {
                Text(error).font(.caption).foregroundStyle(Theme.error)
            } else if viewModel.isStillPending {
                Text("Not yet. We'll get to it soon.").font(.footnote).foregroundStyle(Theme.muted)
            }
        } footer: {
            VStack(spacing: 12) {
                PrimaryAction("Check again", isWorking: viewModel.isWorking) { Task { await viewModel.checkApproval() } }
                Button("Sign out") { Task { await viewModel.signOutWhilePending() } }
                    .font(.footnote)
                    .tint(Theme.muted)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.checkApproval(quietly: true) } }
        }
    }
}

/// School SSO. Not shown while sign-in is email and password (N36).
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
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            if let error = viewModel.signInError {
                Text(error).font(.caption).foregroundStyle(Theme.error)
            }
        } footer: {
            VStack(spacing: 12) {
                PrimaryAction("Continue with school account", isWorking: viewModel.isWorking) {
                    Task { await viewModel.continueWithSchool() }
                }
                .disabled(viewModel.selectedSchool == nil)
                Button("Use email and password") { viewModel.path.append(.signIn) }
                    .font(.footnote)
                    .tint(Theme.muted)
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
                Text(school.shortName.uppercased())
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.accentSoft, in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(school.name).font(.body).foregroundStyle(Theme.ink)
                    Text(school.emailDomain).font(.footnote).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.accentSoft.opacity(0.5) : .clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct VerifiedStep: View {
    var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingPage(
            systemImage: "checkmark.shield",
            title: "You're in",
            message: viewModel.verifiedMessage
        ) {
            EmptyView()
        } footer: {
            PrimaryAction("Continue") { viewModel.path.append(.about) }
        }
    }
}

private struct AboutStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingPage(title: "About you", message: "Your first name and last initial show on games you join.") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    FieldBox("First name") {
                        TextField("Emilio", text: $viewModel.firstName).textContentType(.givenName)
                    }
                    FieldBox("Last name") {
                        TextField("Garza", text: $viewModel.lastName).textContentType(.familyName)
                    }
                }
                Menu {
                    Picker("Class year", selection: $viewModel.classYear) {
                        ForEach(viewModel.classYears, id: \.self) { Text(String($0)).tag($0) }
                    }
                } label: {
                    FieldBox("Class year", showsChevron: true) { Text(String(viewModel.classYear)) }
                }
                if let error = viewModel.aboutError {
                    Text(error).font(.caption).foregroundStyle(Theme.error)
                }
                HStack(spacing: 12) {
                    Avatar(name: "\(viewModel.firstName) \(viewModel.lastName)", size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.preview).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        Text("This is how others see you.").font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        } footer: {
            PrimaryAction("Continue") { viewModel.submitAbout() }
        }
    }
}

private struct InterestsStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingPage(title: "What do you play?", message: "Pick at least one. Only you see your interests.") {
            FlowLayout(spacing: 8) {
                ForEach(Activity.builtIn.filter(\.interestSelectable)) { sport in
                    InterestToggle(sport: sport, isOn: viewModel.interests.contains(sport)) { viewModel.toggle(sport) }
                }
            }
            if let error = viewModel.profileError {
                Text(error).font(.caption).foregroundStyle(Theme.error)
            }
        } footer: {
            PrimaryAction("Continue", isWorking: viewModel.isWorking) { Task { await viewModel.submitProfile() } }
                .disabled(viewModel.interests.isEmpty)
        }
    }
}

private struct GuidelinesStep: View {
    @Bindable var viewModel: OnboardingViewModel

    private let rules: [LocalizedStringKey] = [
        "Be respectful. No harassment, hate or slurs.",
        "Keep it about the game: plans, timing, where to meet.",
        "Don't share anyone's personal info or photos without asking.",
        "Meet in public places and look out for each other.",
    ]

    var body: some View {
        OnboardingPage(title: "Community guidelines", message: "masUNO works because people show up and play fair.") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(rules.indices, id: \.self) { index in
                    Label {
                        Text(rules[index]).foregroundStyle(Theme.ink)
                    } icon: {
                        Image(systemName: "checkmark").foregroundStyle(Theme.accent).fontWeight(.semibold)
                    }
                }
                Text("You can report or block anyone from the Who's going list.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 4)
            }
            .padding(16)
            .cardSurface()
            if let error = viewModel.guidelinesError {
                Text(error).font(.caption).foregroundStyle(Theme.error)
            }
        } footer: {
            PrimaryAction("I agree", isWorking: viewModel.isWorking) { Task { await viewModel.agreeToGuidelines() } }
        }
    }
}

// MARK: - Layout

/// Title + message at the top, content, and a pinned bottom action.
private struct OnboardingPage<Content: View, Footer: View>: View {
    var systemImage: String?
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    init(
        systemImage: String? = nil, title: LocalizedStringKey, message: LocalizedStringKey,
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
            VStack(alignment: systemImage == nil ? .leading : .center, spacing: 20) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 96, height: 96)
                        .background(Theme.accentSoft, in: .circle)
                        .padding(.top, 120)
                }
                VStack(alignment: systemImage == nil ? .leading : .center, spacing: 8) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.ink)
                    Text(message)
                        .font(.body)
                        .foregroundStyle(Theme.muted)
                }
                .multilineTextAlignment(systemImage == nil ? .leading : .center)
                content
            }
            .frame(maxWidth: .infinity, alignment: systemImage == nil ? .leading : .center)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            footer
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Theme.background)
        }
    }
}

private struct PrimaryAction: View {
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
        .buttonStyle(.glassProminent)
        // The steps are tinted ink for the back button; actions stay green.
        .tint(Theme.accent)
        .controlSize(.large)
        .buttonSizing(.flexible)
        .fontWeight(.semibold)
        .disabled(isWorking)
    }
}
