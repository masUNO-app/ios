import SwiftUI

/// Onboarding (E5, SPEC §7.5), built from the spec copy; 1.0 restyles it from Arianna's D2 frames.
/// Welcome → school email → code → about you → interests → community guidelines → map.
/// `AuthService` moves the session along; when it reaches signed in, the root swaps to the map.
struct OnboardingFlow: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var viewModel: OnboardingViewModel

    init(auth: any AuthService, campus: University?) {
        _viewModel = State(initialValue: OnboardingViewModel(auth: auth, campus: campus))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack(path: $viewModel.path) {
            welcome
                .navigationDestination(for: OnboardingViewModel.Step.self) { step in
                    Group {
                        switch step {
                        case .email: EmailStep(viewModel: viewModel)
                        case .code: CodeStep(viewModel: viewModel)
                        case .about: AboutStep(viewModel: viewModel)
                        case .interests: InterestsStep(viewModel: viewModel)
                        case .guidelines: GuidelinesStep(viewModel: viewModel)
                        }
                    }
                    .tint(Theme.ink)
                }
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
                PrimaryAction(viewModel.continueTitle) { viewModel.path.append(.email) }
                Link("Privacy & Terms", destination: appViewModel.config.privacyURL)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    #if DEBUG
    /// `-screen onboarding-email|code|about|interests|guidelines` opens a step with sample input.
    private func openDebugStep() {
        guard let step = UserDefaults.standard.string(forKey: "screen"), step.hasPrefix("onboarding-") else { return }
        viewModel.email = "a01234567@tec.mx"
        viewModel.firstName = "Emilio"
        viewModel.lastName = "Garza"
        viewModel.interests = [Activity.builtIn[0], Activity.builtIn[2]]
        let all: [OnboardingViewModel.Step] = [.email, .code, .about, .interests, .guidelines]
        let names = ["email", "code", "about", "interests", "guidelines"]
        if let index = names.firstIndex(of: String(step.dropFirst("onboarding-".count))) {
            viewModel.path = Array(all[...index])
        }
    }
    #endif
}

// MARK: - Steps

private struct EmailStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var focused: Bool

    var body: some View {
        OnboardingPage(title: viewModel.emailTitle, message: "We'll send you a 6-digit code. No passwords.") {
            FieldBox(viewModel.emailLabel, error: viewModel.usesPassword ? nil : viewModel.emailError) {
                TextField(viewModel.emailPlaceholder, text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.continue)
                    .onSubmit { Task { await viewModel.submitEmail() } }
            }
            // Review accounts only (SPEC §8.4).
            if viewModel.usesPassword {
                FieldBox("Password", error: viewModel.emailError) {
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                        .onSubmit { Task { await viewModel.submitPassword() } }
                }
            }
        } footer: {
            if viewModel.usesPassword {
                PrimaryAction("Sign in", isWorking: viewModel.isWorking) { Task { await viewModel.submitPassword() } }
                    .disabled(viewModel.password.isEmpty)
            } else {
                PrimaryAction("Send code", isWorking: viewModel.isWorking) { Task { await viewModel.submitEmail() } }
                    .disabled(viewModel.email.isEmpty)
            }
        }
        .onAppear { focused = true }
    }
}

private struct CodeStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var focused: Bool

    var body: some View {
        OnboardingPage(
            title: "Check your email",
            message: "We sent a 6-digit code to \(viewModel.maskedEmail). It comes from masunoapp@gmail.com — check Junk if you don't see it."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                codeBoxes
                if let error = viewModel.codeError {
                    Text(error).font(.caption).foregroundStyle(Theme.error)
                }
                Button(viewModel.resendIn > 0 ? "Resend code in \(viewModel.resendIn) s" : "Resend code") {
                    Task { await viewModel.resendCode() }
                }
                .font(.subheadline.weight(.semibold))
                .tint(viewModel.resendIn > 0 ? Theme.muted : Theme.accent)
                .disabled(viewModel.resendIn > 0)
                .padding(.top, 4)
            }
        } footer: {
            PrimaryAction("Continue", isWorking: viewModel.isWorking) { Task { await viewModel.verifyCode() } }
                .disabled(viewModel.code.count < 6)
        }
        .onAppear { focused = true }
        .onChange(of: viewModel.code) { if viewModel.code.count == 6 { Task { await viewModel.verifyCode() } } }
    }

    /// Six boxes over one hidden field, so one-time-code autofill and paste work.
    private var codeBoxes: some View {
        ZStack {
            TextField("", text: $viewModel.code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .opacity(0.02)
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    let digits = Array(viewModel.code)
                    let isCurrent = focused && index == digits.count
                    Text(index < digits.count ? String(digits[index]) : "")
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.field))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.field)
                                .strokeBorder(
                                    viewModel.codeError != nil ? Theme.error : (isCurrent ? Theme.accent : Theme.hairline),
                                    lineWidth: isCurrent || viewModel.codeError != nil ? 1.5 : 1
                                )
                        }
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(.rect)
        .onTapGesture { focused = true }
        .accessibilityElement()
        .accessibilityLabel(Text("Code, \(viewModel.code.count) of 6 digits"))
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
