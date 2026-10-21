import SwiftUI

/// Root of the app: the map, with plans/chat pushed on top and Add event as a sheet.
struct ContentView: View {
    @State private var store = EventStore()
    @State private var appViewModel = AppViewModel()

    var body: some View {
        @Bindable var appViewModel = appViewModel

        NavigationStack(path: $appViewModel.path) {
            EventMapView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .registered: RegisteredEventsView()
                    case .hosted: HostedEventsView()
                    case .chat(let id): GroupChatView(eventID: id)
                    }
                }
        }
        .sheet(isPresented: $appViewModel.isAddingEvent, onDismiss: { appViewModel.editingEventID = nil }) {
            AddEventSheet(editing: appViewModel.editingEvent(in: store))
        }
        .overlay(alignment: .top) { NoticeBanner() }
        .environment(store)
        .environment(appViewModel)
        .tint(Theme.orange)
        // The Figma is light-only for now.
        .preferredColorScheme(.light)
        #if DEBUG
        .onAppear(perform: appViewModel.openDebugScreen)
        #endif
    }
}

/// Stand-in for push notifications (e.g. "a spot opened in a game you bookmarked").
private struct NoticeBanner: View {
    @Environment(EventStore.self) private var store

    var body: some View {
        if let notice = store.notice {
            Label(notice, systemImage: "bell.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 20)
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
