import SwiftUI

/// Figma: "Me · Going" (341:2165) and "Me · Hosting" (341:2240): the sky-blue profile card,
/// Plays chips, and your games as sport-colored cards with their people and "+1" tokens.
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
        let listed = store.goingGames() + store.pastGames() + store.hostedGames()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.isOffline { OfflineBanner() }
                profileCard

                // Segments only: Me is pushed over the map, so a swipe right is always Back.
                Picker("Show", selection: $viewModel.tab) {
                    Text("Going").tag(MeViewModel.Tab.going)
                    Text("Hosting").tag(MeViewModel.Tab.hosting)
                }
                .pickerStyle(.segmented)
                .padding(.top, 8)

                list
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
            .readableColumn()
            .animation(.snappy, value: store.goingGames().map(\.id))
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
        .task(id: listed.map(\.id)) { await store.loadMissingAttendees(for: listed.map(\.id)) }
        .sheet(isPresented: $viewModel.editsProfile) {
            if let profile = store.profile { EditProfileSheet(profile: profile) }
        }
        .sheet(item: $viewModel.reportTarget) { ReportSheet(target: $0) }
        .leaveGameDialog($viewModel.leaving)
        #if DEBUG
        .onAppear {
            switch UserDefaults.standard.string(forKey: "screen") {
            // The Leave confirmation over the first game you're in.
            case "me-leave": viewModel.leaving = store.goingGames().first
            case "me-past": viewModel.showsEarlier = true
            default: break
            }
        }
        #endif
    }

    // MARK: Tabs

    @ViewBuilder
    private var list: some View {
        HStack {
            sectionTitle("Coming up")
            Spacer()
            if viewModel.tab == .hosting {
                Button("Add game", systemImage: "plus") { appViewModel.presentGameForm() }
                    .labelStyle(.titleAndIcon)
                    .pill(.secondary, expands: false, size: .small)
            }
        }
        // The same height with or without Add game, so switching tabs doesn't nudge the list.
        .frame(minHeight: 30)

        if case .failed = store.myGamesState {
            RetryCard { await store.refreshMyGames() }
        } else {
            switch viewModel.tab {
            case .going: goingList
            case .hosting: hostingList
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.rounded(.footnote, .bold))
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Profile

    @ViewBuilder
    private var profileCard: some View {
        if let profile = store.profile { profileCard(profile) }
    }

    private func profileCard(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                MeToken(name: profile.fullName, size: 72, ring: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: profile.fullName)
                        .font(.rounded(.title2, .bold))
                        .foregroundStyle(Theme.ink)
                    Text(verbatim: viewModel.classLine(for: profile))
                        .font(.rounded(.footnote))
                        .foregroundStyle(Theme.ink)
                    // O4: "Tec verified" if staff turn out to share the student domain.
                    VerifiedBadge()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.you)

            VStack(alignment: .leading, spacing: 10) {
                Text("Plays")
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.muted)
                FlowLayout(spacing: 6) {
                    ForEach(profile.interests) { SportChip(sport: $0) }
                }
                Button("Edit profile and sports") { viewModel.editsProfile = true }
                    .pill(.secondary)
                    .padding(.top, 4)
            }
            .padding(18)
        }
        .background(Theme.card)
        .clipShape(.rect(cornerRadius: Theme.Radius.dialog))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.dialog).strokeBorder(Theme.separator))
    }

    // MARK: Lists

    @ViewBuilder
    private var goingList: some View {
        let events = store.goingGames()
        if events.isEmpty, store.myGamesState == .loaded {
            EmptyCard(title: "No games yet", message: "Find one nearby, or start your own. Most games just need one more.") {
                Button("Find a game") { appViewModel.showMap() }
                    .pill(.primary)
                Button("Add a game") { appViewModel.presentGameForm() }
                    .pill(.secondary)
            }
        }
        ForEach(events) { event in
            NavigationLink(value: Route.game(event.id)) {
                if event.isCancelled { cancelledCard(event) } else { goingCard(event) }
            }
            .buttonStyle(.plain)
        }
        earlierSection
    }

    private func goingCard(_ event: Game) -> some View {
        GameCard(event: event, lineup: store.lineup(for: event), status: event.goingLine, time: EventFormat.cardTime(event)) {
            Button("Leave") { viewModel.leaving = event }
                .pill(.secondary, expands: false)
            chatButton(event)
        }
    }

    /// Stays in Going, greyed out, until you remove it.
    private func cancelledCard(_ event: Game) -> some View {
        GameCard(
            event: event, lineup: store.lineup(for: event), status: event.cancelledLine,
            time: EventFormat.cancelledTime(event), isMuted: true
        ) {
            Button("Remove") { store.dismissCancelled(event.id) }
                .pill(.secondary, expands: false)
            Button("Find another game") { appViewModel.showMap() }
                .pill(.primary)
        }
    }

    /// Games from the last 14 days, so you can still report someone, or get the group back
    /// together. Collapsed, so they don't push what's coming up out of sight.
    @ViewBuilder
    private var earlierSection: some View {
        @Bindable var viewModel = viewModel
        let events = store.pastGames()
        if !events.isEmpty {
            DisclosureGroup(isExpanded: $viewModel.showsEarlier) {
                VStack(spacing: 16) {
                    ForEach(events) { event in
                        NavigationLink(value: Route.game(event.id)) {
                            GameCard(
                                event: event, lineup: store.lineup(for: event), status: event.playedLine,
                                time: EventFormat.cardTime(event), isMuted: true
                            ) {
                                Button("Report") { viewModel.reportTarget = .game(event.id) }
                                    .pill(.secondary, expands: false)
                                Button("Play again") { appViewModel.presentPlayAgain(event.id) }
                                    .pill(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)
            } label: {
                sectionTitle("Earlier · \(events.count)")
            }
            .tint(Theme.ink)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var hostingList: some View {
        let events = store.hostedGames()
        if events.isEmpty, store.myGamesState == .loaded {
            EmptyCard(title: "Nothing on the map yet", message: "Host a game in under a minute. Most games just need one more.") {
                Button("Add a game") { appViewModel.presentGameForm() }
                    .pill(.primary)
            }
        }
        ForEach(events) { event in
            NavigationLink(value: Route.game(event.id)) {
                GameCard(event: event, lineup: store.lineup(for: event), status: hostingStatus(event), time: EventFormat.cardTime(event)) {
                    Button("Edit") { appViewModel.presentGameForm(editing: event.id) }
                        .pill(.secondary, expands: false)
                    chatButton(event)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// "3 joined · room for 6 more", then the auto-repost line when there's news (SPEC §7.6.11).
    private func hostingStatus(_ event: Game) -> String {
        guard event.autoRepost, let repostedAt = event.repostedAt else { return event.hostingLine }
        let when = Date.now.timeIntervalSince(repostedAt) < 60
            ? String(localized: "Reposted just now")
            : String(localized: "Reposted \(repostedAt.formatted(.relative(presentation: .named)))")
        return "\(event.hostingLine)\n\(when)"
    }

    private func chatButton(_ event: Game) -> some View {
        NavigationLink(value: Route.chat(event.id)) {
            Text(verbatim: viewModel.chatTitle(unread: store.unreadCount(event.id)))
        }
        .pill(.primary)
    }
}
