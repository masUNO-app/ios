import SwiftUI

/// Root of the app (SPEC §7.3): launch gate, then the map with game detail, Me and
/// Settings pushed on top and the game form as a sheet.
struct ContentView: View {
    @State private var store: GameStore
    @State private var appViewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    private let services: AppServices
    private let notifications: NotificationCenterBridge

    init(notifications: NotificationCenterBridge = NotificationCenterBridge()) {
        let services = AppLaunch.services
        self.notifications = notifications
        self.services = services
        _store = State(initialValue: GameStore(
            games: services.games, profiles: services.profiles, safety: services.safety, chat: services.chat,
            catalog: services.catalog, notifications: services.notifications
        ))
        _appViewModel = State(initialValue: AppViewModel(auth: services.auth, catalog: services.catalog, push: services.push))
    }

    var body: some View {
        Group {
            switch appViewModel.session {
            case .launching: Theme.background.ignoresSafeArea()
            case .updateRequired: UpdateRequiredView()
            case .onboarding: OnboardingFlow(auth: appViewModel.auth, catalog: services.catalog, campus: appViewModel.launchCampus)
            case .guest, .signedIn: main
            case .suspended: SuspendedView()
            }
        }
        // Over the bottom bar on the map, as in the Figma; at the top elsewhere, clear of the
        // action bars pinned to the bottom of other screens.
        .overlay(alignment: showsNoticeAtBottom ? .bottom : .top) {
            NoticeBanner()
                .padding(.bottom, showsNoticeAtBottom ? 84 : 0)
        }
        .animation(.snappy, value: store.notice)
        .environment(store)
        .environment(appViewModel)
        .environment(services.push)
        .environment(\.currentUserID, store.profile?.id)
        .tint(Theme.accent)
        // SF Pro Rounded throughout (SPEC §7.7.2, R7-10).
        .fontDesign(.rounded)
        // Light mode only (SPEC §7.1).
        .preferredColorScheme(.light)
        .onOpenURL { appViewModel.handle($0) }
        .onChange(of: appViewModel.path, initial: true) { _, _ in retainNavigationGames() }
        .onChange(of: appViewModel.sheet) { _, _ in retainNavigationGames() }
        .task { await launch() }
        // Onboarding finished. `launch()` handles an already signed-in session.
        .onChange(of: appViewModel.session) { old, new in
            if new == .signedIn, old == .onboarding || old == .guest {
                appViewModel.clearGuestBrowsingFlag()
                Task { await loadSignedIn() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await appViewModel.finishPendingSignOutIfNeeded()
                    guard appViewModel.session == .signedIn || appViewModel.session == .guest else { return }
                    await store.refresh()
                    if appViewModel.session == .signedIn {
                        await appViewModel.push?.refreshRegistration(force: false)
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: {
                store.asksForNotificationPrimer && appViewModel.push?.shouldOfferPrimer(accountID: store.profile?.id) == true
            },
            set: { presented in
                guard !presented else { return }
                // A drag-away is the same as Not now. Turn on sets the accepted flag first.
                appViewModel.push?.recordPrimerClose(
                    accepted: store.notificationPrimerAccepted, accountID: store.profile?.id
                )
                store.notificationPrimerAccepted = false
                store.asksForNotificationPrimer = false
            }
        )) {
            NotificationPrimerSheet()
                .environment(store)
                .environment(services.push)
        }
        .dialog(item: Bindable(appViewModel).accountPrompt) { prompt in
            DialogCard(
                systemImage: "checkmark.shield",
                title: Text(verbatim: prompt.title),
                message: Text(verbatim: prompt.message),
                confirm: DialogAction("Create account") {
                    appViewModel.endGuestBrowsing(resume: .signUp, store: store)
                },
                cancel: DialogAction("I already have an account") {
                    appViewModel.endGuestBrowsing(resume: .signIn, store: store)
                },
                tertiary: prompt == .me && appViewModel.canSwitchGuestCampus
                    ? DialogAction("Browse another campus") {
                        appViewModel.endGuestBrowsing(resume: .guestCampus, store: store)
                    }
                    : nil
            )
        }
    }

    private var showsNoticeAtBottom: Bool {
        (appViewModel.session == .signedIn || appViewModel.session == .guest)
            && appViewModel.path.isEmpty && appViewModel.sheet == nil
    }

    private func retainNavigationGames() {
        var ids = Set(appViewModel.path.compactMap { route -> UUID? in
            switch route {
            case .game(let id), .chat(let id): return id
            default: return nil
            }
        })
        switch appViewModel.sheet {
        case .gameForm(let id): if let id { ids.insert(id) }
        case .playAgain(let id): ids.insert(id)
        case nil: break
        }
        store.retainGames(ids)
    }

    private func launch() async {
        store.onSessionProblem = { [auth = appViewModel.auth] in Task { await auth.restoreSession() } }
        appViewModel.push?.onOpen = { url in
            if let url { appViewModel.handle(url) }
        }
        appViewModel.push?.onRefreshGame = { id in Task { await store.loadGame(id) } }
        await appViewModel.start()
        store.isChatEnabled = appViewModel.config.chatEnabled
        #if DEBUG
        appViewModel.applyDebugSession(mock: services.mock)
        if UserDefaults.standard.string(forKey: "screen")?.hasPrefix("guest") == true {
            await appViewModel.openDebugScreen(store: store, mock: services.mock)
            return
        }
        #endif
        // Install routing for both guest and account sessions; only accounts register a token.
        if let push = appViewModel.push { await notifications.connect(push) }
        // A guest from last time goes straight back to the map.
        if appViewModel.session == .guest { return await appViewModel.resumeGuestBrowsing(store: store) }
        guard appViewModel.session == .signedIn else { return }
        await loadSignedIn()
        #if DEBUG
        await appViewModel.openDebugScreen(store: store, mock: services.mock)
        #endif
    }

    /// Loads a signed-in account, then tells the server if this is a TestFlight install (beta badge).
    private func loadSignedIn() async {
        await store.load()
        appViewModel.push?.noteAccount(store.profile?.id)
        // Routing is useful immediately; device registration must not delay a tapped game.
        appViewModel.deliverPushRoute(appViewModel.push?.consumePendingRoute())
        await appViewModel.push?.refreshRegistration(force: true)
        await store.markBetaTesterIfNeeded(isTestFlight: await BuildChannel.isTestFlight)
    }

    private var main: some View {
        @Bindable var appViewModel = appViewModel

        return NavigationStack(path: $appViewModel.path) {
            EventMapView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .game(let id): EventDetailView(eventID: id)
                    case .chat(let id): GroupChatView(eventID: id)
                    case .me(let tab, let editsProfile): MeView(tab: tab, editsProfile: editsProfile)
                    case .settings: SettingsView()
                    case .blockedPeople: BlockedPeopleView()
                    case .guidelines: CommunityGuidelinesView()
                    #if DEBUG
                    case .gallery: ComponentGallery()
                    #endif
                    }
                }
        }
        .readsBarLayout()
        .sheet(item: $appViewModel.sheet) { sheet in
            switch sheet {
            case .gameForm(let id): GameFormSheet(editing: id.flatMap { store.game($0) })
            case .playAgain(let id): GameFormSheet(template: store.game(id))
            }
        }
    }
}

/// Short toast for failed actions and confirmations ("Saved. Find it under bookmarks.").
private struct NoticeBanner: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        if let notice = store.notice {
            Text(verbatim: notice)
                .font(.rounded(.subheadline, .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, Theme.gutter)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .onTapGesture { store.notice = nil }
                .accessibilityAddTraits(.isStaticText)
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(4))
                    store.notice = nil
                }
        }
    }
}

#Preview {
    ContentView()
}
