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
            case .suspended: SuspendedView()
            case .signedIn: main
            }
        }
        .overlay(alignment: .top) { NoticeBanner() }
        .environment(store)
        .environment(appViewModel)
        .tint(Theme.accent)
        // Light mode only (SPEC §7.1).
        .preferredColorScheme(.light)
        .onOpenURL { appViewModel.handle($0) }
        .task { await launch() }
        // Onboarding finished. `launch()` handles an already signed-in session.
        .onChange(of: appViewModel.session) { old, new in
            if old == .onboarding, new == .signedIn { Task { await store.load() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, appViewModel.session == .signedIn { Task { await store.refresh() } }
        }
    }

    private func launch() async {
        store.onSessionProblem = { [auth = appViewModel.auth] in Task { await auth.restoreSession() } }
        await appViewModel.start()
        store.isChatEnabled = appViewModel.config.chatEnabled
        #if DEBUG
        appViewModel.applyDebugSession(mock: services.mock)
        #endif
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
                    #if DEBUG
                    case .gallery: ComponentGallery()
                    #endif
                    }
                }
        }
        .sheet(item: $appViewModel.sheet) { sheet in
            switch sheet {
            case .gameForm(let id): GameFormSheet(editing: id.flatMap { store.game($0) })
            }
        }
    }
}

/// Short toast for failed actions and confirmations ("Someone just took the last spot.").
private struct NoticeBanner: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        if let notice = store.notice {
            Label(notice, systemImage: "info.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, Theme.gutter)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { store.notice = nil }
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { store.notice = nil }
                }
        }
    }
}

#Preview {
    ContentView()
}
