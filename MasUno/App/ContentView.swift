import SwiftUI

/// Root of the app (SPEC §7.3): launch gate, then the map with game detail, Me and
/// Settings pushed on top and the game form as a sheet.
struct ContentView: View {
    @State private var store = EventStore()
    @State private var appViewModel = AppViewModel()

    var body: some View {
        Group {
            switch appViewModel.session {
            case .updateRequired: UpdateRequiredView()
            case .signedOut: WelcomeView()
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
        #if DEBUG
        .onAppear { appViewModel.openDebugScreen(in: store) }
        #endif
    }

    private var main: some View {
        @Bindable var appViewModel = appViewModel

        return NavigationStack(path: $appViewModel.path) {
            EventMapView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .game(let id): EventDetailView(eventID: id)
                    case .me(let tab): MeView(tab: tab)
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
            case .gameForm(let id): GameFormSheet(editing: id.flatMap { store.event($0) })
            }
        }
    }
}

/// Short toast for failed actions and confirmations ("Someone just took the last spot.").
private struct NoticeBanner: View {
    @Environment(EventStore.self) private var store

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
