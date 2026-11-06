import SwiftUI

/// Figma: "Me · Going" (341:2165) and "Me · Hosting" (341:2240). Replaces "Registered
/// events" and "Hosted events".
struct MeView: View {
    @Environment(GameStore.self) private var store
    @Environment(AppViewModel.self) private var appViewModel
    @State private var viewModel: MeViewModel

    init(tab: MeViewModel.Tab = .going, editsProfile: Bool = false) {
        let viewModel = MeViewModel(tab: tab)
        viewModel.editsProfile = editsProfile
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.isOffline { OfflineBanner() }
                profileCard

                Picker("Show", selection: $viewModel.tab) {
                    Text("Going").tag(MeViewModel.Tab.going)
                    Text("Hosting").tag(MeViewModel.Tab.hosting)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Coming up")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if viewModel.tab == .hosting {
                        Button("Create", systemImage: "plus") { appViewModel.presentGameForm() }
                            .buttonStyle(.glassProminent)
                            .tint(Theme.accentSoft)
                            .foregroundStyle(Theme.ink)
                    }
                }

                if case .failed = store.myGamesState {
                    RetryCard { await store.refreshMyGames() }
                } else {
                    switch viewModel.tab {
                    case .going: goingList
                    case .hosting: hostingList
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Me")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .tint(Theme.ink)
            }
        }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $viewModel.editsProfile) {
            if let profile = store.profile { EditProfileSheet(profile: profile) }
        }
        .alert(
            Text("Leave \(viewModel.leaving?.title ?? "")?"),
            isPresented: Binding(get: { viewModel.leaving != nil }, set: { if !$0 { viewModel.leaving = nil } }),
            presenting: viewModel.leaving
        ) { event in
            Button("Leave game", role: .destructive) { viewModel.leave(event, in: store) }
            Button("Stay in", role: .cancel) {}
        } message: { _ in
            Text("Your spot opens up for someone else.")
        }
    }

    // MARK: Profile

    @ViewBuilder
    private var profileCard: some View {
        if let profile = store.profile { profileCard(profile) }
    }

    private func profileCard(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Avatar(name: profile.fullName, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.fullName)
                        .font(.title2.bold())
                        .foregroundStyle(Theme.ink)
                    Text(viewModel.classLine(for: profile))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    // "Tec verified" if O4 finds staff share the @tec.mx domain.
                    StatusChip(String(localized: "Verified student"), systemImage: "checkmark.seal.fill")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Your interests")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                FlowLayout(spacing: 8) {
                    ForEach(profile.interests) { InterestChip(sport: $0) }
                }
            }

            Button("Edit profile & interests") { viewModel.editsProfile = true }
                .buttonStyle(.glassProminent)
                .tint(Theme.accentSoft)
                .foregroundStyle(Theme.ink)
                .controlSize(.large)
                .buttonSizing(.flexible)
                .fontWeight(.semibold)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: Lists

    @ViewBuilder
    private var goingList: some View {
        let events = store.goingGames()
        if events.isEmpty, store.myGamesState == .loaded {
            emptyState("No games yet. Find one on the map.", systemImage: "sportscourt", action: "Find a game") {
                appViewModel.path.removeAll()
            }
        }
        ForEach(events) { event in
            NavigationLink(value: Route.game(event.id)) {
                GameCard(event: event) {
                    if !event.isCancelled {
                        Button("Leave") { viewModel.leaving = event }
                            .buttonStyle(.glassProminent)
                            .tint(Theme.accentSoft)
                            .foregroundStyle(Theme.ink)
                    }
                } footer: {
                    if !event.isCancelled { chatButton(event) }
                }
            }
            .buttonStyle(.plain)
        }
        pastSection
    }

    /// Last 14 days, collapsed.
    @ViewBuilder
    private var pastSection: some View {
        @Bindable var viewModel = viewModel
        let events = store.pastGames()
        if !events.isEmpty {
            DisclosureGroup(isExpanded: $viewModel.showsPast) {
                VStack(spacing: 16) {
                    ForEach(events) { event in
                        NavigationLink(value: Route.game(event.id)) {
                            GameCard(event: event, status: String(localized: "Ended · \(event.goingCount) played")) {
                                EmptyView()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)
            } label: {
                Text("Past · \(events.count)")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.ink)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var hostingList: some View {
        let events = store.hostedGames()
        if events.isEmpty, store.myGamesState == .loaded {
            emptyState("Host a game in under a minute.", systemImage: "plus.circle", action: "Add game") {
                appViewModel.presentGameForm()
            }
        }
        ForEach(events) { event in
            NavigationLink(value: Route.game(event.id)) {
                GameCard(event: event, showsHost: false, status: event.statusLine, showsRepost: true) {
                    Button("Edit") { appViewModel.presentGameForm(editing: event.id) }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accentSoft)
                        .foregroundStyle(Theme.ink)
                } footer: {
                    chatButton(event)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func chatButton(_ event: Game) -> some View {
        NavigationLink(value: Route.chat(event.id)) {
            Text("Group chat")
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .buttonSizing(.flexible)
        .fontWeight(.semibold)
    }

    private func emptyState(
        _ message: LocalizedStringKey, systemImage: String, action: LocalizedStringKey,
        perform: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(Theme.muted)
            Text(message)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Button(action, action: perform)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
