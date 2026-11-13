import SwiftUI

/// Root of the app (SPEC §7.3): launch gate, then the map with game detail, Me and
/// Settings pushed on top and the game form as a sheet.
struct ContentView: View {
    @State private var store: GameStore
    @State private var appViewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    private let services: AppServices

    init() {
        let services = AppServices.make()
        self.services = services
        _store = State(initialValue: GameStore(
            games: services.games, profiles: services.profiles, safety: services.safety, chat: services.chat, catalog: services.catalog
        ))
        _appViewModel = State(initialValue: AppViewModel(auth: services.auth, catalog: services.catalog))
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
        .environment(\.currentUserID, store.profile?.id)
        .tint(Theme.accent)
        // SF Pro Rounded throughout (SPEC §7.7.2, R7-10).
        .fontDesign(.rounded)
        // Light mode only (SPEC §7.1).
        .preferredColorScheme(.light)
        .onOpenURL { appViewModel.handle($0) }
        .task { await launch() }
        // Onboarding finished. `launch()` handles an already signed-in session.
        .onChange(of: appViewModel.session) { old, new in
            if new == .signedIn, old == .onboarding || old == .guest {
                appViewModel.clearGuestBrowsingFlag()
                Task { await store.load() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, appViewModel.session == .signedIn || appViewModel.session == .guest {
                Task { await store.refresh() }
            }
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
                }
            )
        }
    }

    private var showsNoticeAtBottom: Bool {
        (appViewModel.session == .signedIn || appViewModel.session == .guest)
            && appViewModel.path.isEmpty && appViewModel.sheet == nil
    }

    private func launch() async {
        store.onSessionProblem = { [auth = appViewModel.auth] in Task { await auth.restoreSession() } }
        await appViewModel.start()
        store.isChatEnabled = appViewModel.config.chatEnabled
        #if DEBUG
        appViewModel.applyDebugSession(mock: services.mock)
        if UserDefaults.standard.string(forKey: "screen")?.hasPrefix("guest") == true {
            await appViewModel.openDebugScreen(store: store, mock: services.mock)
            return
        }
        #endif
        // A guest from last time goes straight back to the map.
        if appViewModel.session == .guest { return await appViewModel.resumeGuestBrowsing(store: store) }
        guard appViewModel.session == .signedIn else { return }
        await store.load()
        #if DEBUG
        await appViewModel.openDebugScreen(store: store, mock: services.mock)
        #endif
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
