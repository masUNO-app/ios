import SwiftUI

/// Figma: "Me · Going" (341:2165) and "Me · Hosting" (341:2240): the sky-blue profile card,
/// Plays chips, and your games as sport-colored cards with their people and "+1" tokens.
struct MeView: View {
    @Environment(GameStore.self) private var store
    @Environment(AppViewModel.self) private var appViewModel
    @State private var viewModel: MeViewModel
    @Environment(\.dynamicTypeSize) private var typeSize

    init(tab: MeViewModel.Tab = .going, editsProfile: Bool = false) {
        let viewModel = MeViewModel(tab: tab)
        viewModel.editsProfile = editsProfile
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        // Each list once per render, against one clock, so they can't disagree about a game ending mid-render.
        let now = Date.now
        let going = store.goingGames(now: now)
        let past = store.pastGames(now: now)
        let hosted = store.hostedGames(now: now)
        let listed = going + past + hosted

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
                // About one card wide: full width on every phone, not stretched across two columns.
                .frame(maxWidth: 400)
                .padding(.top, 8)

                list(going: going, past: past, hosted: hosted)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
            .wideColumn()
            .animation(.snappy, value: going.map(\.id))
        }
        .background(Theme.background)
        .navigationTitle(String.app("Me"))
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
        .sheet(isPresented: $viewModel.showsInvites) { InvitesSheet() }
        .sheet(item: $viewModel.reportTarget) { ReportSheet(target: $0) }
        .leaveGameDialog($viewModel.leaving)
        #if DEBUG
        .onAppear {
            switch UserDefaults.standard.string(forKey: "screen") {
            // The Leave confirmation over the first game you're in.
            case "me-leave": viewModel.leaving = store.goingGames().first
            case "me-past": viewModel.showsEarlier = true
            // The Invites sheet over Me.
            case "invites": viewModel.showsInvites = true
            default: break
            }
        }
        #endif
    }

    // MARK: Tabs

    @ViewBuilder
    private func list(going: [Game], past: [Game], hosted: [Game]) -> some View {
        HStack {
            sectionTitle("Coming up")
            Spacer()
            if viewModel.tab == .hosting {
                Button("Make a plan", systemImage: "plus") { appViewModel.presentGameForm() }
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
            case .going: goingList(going, past: past)
            case .hosting: hostingList(hosted)
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

    /// Side by side when both halves get a card's width (open landscape), stacked otherwise.
    /// The ideal widths are what `ViewThatFits` measures: without them the chips' one-row
    /// width decides, and the wide card would come and go with your sports.
    private func profileCard(_ profile: Profile) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                profileHeader(profile)
                    .frame(minWidth: Theme.cardMinWidth, idealWidth: Theme.cardMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(Theme.you)
                profilePlays(profile)
                    .frame(minWidth: Theme.cardMinWidth, idealWidth: Theme.cardMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            // Both halves as tall as the taller one, so the blue reaches the bottom.
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                profileHeader(profile)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.you)
                profilePlays(profile)
            }
        }
        .background(Theme.card)
        .clipShape(.rect(cornerRadius: Theme.Radius.dialog))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.dialog).strokeBorder(Theme.separator))
    }

    private func profileHeader(_ profile: Profile) -> some View {
        // The token goes above the name at accessibility sizes, so the text gets the card's width.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(spacing: 14))

        return layout {
            MeToken(name: profile.fullName, size: 72, ring: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: profile.fullName)
                    .font(.rounded(.title2, .bold))
                    .foregroundStyle(Theme.ink)
                Text(verbatim: viewModel.classLine(for: profile))
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.ink)
                // O4: "Tec verified" if staff turn out to share the student domain.
                FlowLayout(spacing: 6) {
                    ProfileBadge("Verified student", systemImage: "checkmark.seal.fill")
                    if profile.isBetaTester { ProfileBadge("Beta tester", systemImage: "testtube.2") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        // On the You color, in dark mode too.
        .inkOnColor()
    }

    private func profilePlays(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Into")
                .font(.rounded(.footnote))
                .foregroundStyle(Theme.muted)
                .accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 6) {
                ForEach(profile.interests) { SportChip(sport: $0) }
            }
            Button("Edit profile and interests") { viewModel.editsProfile = true }
                .pill(.secondary)
                .padding(.top, 4)
            Button(viewModel.inviteTitle(for: store.invites)) { viewModel.showsInvites = true }
                .pill(.quiet)
        }
        .padding(18)
    }

    // MARK: Lists

    @ViewBuilder
    private func goingList(_ events: [Game], past: [Game]) -> some View {
        if events.isEmpty, store.myGamesState == .loaded {
            EmptyCard(title: "No plans yet", message: "Find one nearby, or start your own. Most plans just need one more.") {
                Button("Find a plan") { appViewModel.showMap() }
                    .pill(.primary)
                Button("Make a plan") { appViewModel.presentGameForm() }
                    .pill(.secondary)
            }
        }
        // Only when there are cards: an empty grid would still take the stack's spacing.
        if !events.isEmpty {
            CardGrid {
                ForEach(events) { event in
                    if event.isCancelled { cancelledCard(event) } else { goingCard(event) }
                }
            }
        }
        earlierSection(past)
    }

    private func goingCard(_ event: Game) -> some View {
        GameCard(
            event: event, lineup: store.lineup(for: event), status: event.goingLine, time: EventFormat.cardTime(event),
            onOpen: { open(event) },
            shortcuts: [
                GameCardShortcut(name: String.app("Leave")) { viewModel.leaving = event },
                GameCardShortcut(name: String.app("Open group chat")) { appViewModel.path.append(.chat(event.id)) },
            ]
        ) {
            Button("Leave") { viewModel.leaving = event }
                .pill(.secondary, expands: false)
                .accessibilityLabel(String.app("Leave \(event.title)"))
                .accessibilityInputLabels([Text("Leave")])
            chatButton(event)
        }
    }

    /// Stays in Going, greyed out, until you remove it.
    private func cancelledCard(_ event: Game) -> some View {
        GameCard(
            event: event, lineup: store.lineup(for: event), status: event.cancelledLine,
            time: EventFormat.cancelledTime(event), isMuted: true, onOpen: { open(event) }
        ) {
            Button("Remove") { store.dismissCancelled(event.id) }
                .pill(.secondary, expands: false)
                .accessibilityLabel(String.app("Remove \(event.title)"))
                .accessibilityInputLabels([Text("Remove")])
            Button("Find another plan") { appViewModel.showMap() }
                .pill(.primary)
        }
    }

    /// Games from the last 14 days, so you can still report someone, or get the group back
    /// together. Collapsed, so they don't push what's coming up out of sight.
    @ViewBuilder
    private func earlierSection(_ events: [Game]) -> some View {
        @Bindable var viewModel = viewModel
        if !events.isEmpty {
            DisclosureGroup(isExpanded: $viewModel.showsEarlier) {
                CardGrid {
                    ForEach(events) { event in
                        GameCard(
                            event: event, lineup: store.lineup(for: event), status: event.playedLine,
                            time: EventFormat.cardTime(event), isMuted: true, onOpen: { open(event) }
                        ) {
                            Button("Report") { viewModel.reportTarget = .game(event.id) }
                                .pill(.secondary, expands: false)
                                .accessibilityLabel(String.app("Report, \(event.title)"))
                                .accessibilityInputLabels([Text("Report")])
                            Button("Run it back") { appViewModel.presentPlayAgain(event.id) }
                                .pill(.primary)
                                .accessibilityLabel(String.app("Run it back, \(event.title)"))
                                .accessibilityInputLabels([Text("Run it back")])
                        }
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
    private func hostingList(_ events: [Game]) -> some View {
        if events.isEmpty, store.myGamesState == .loaded {
            EmptyCard(title: "Nothing on the map yet", message: "Start a plan in under a minute. Most plans just need one more.") {
                Button("Make a plan") { appViewModel.presentGameForm() }
                    .pill(.primary)
            }
        }
        if !events.isEmpty {
            CardGrid {
                ForEach(events) { event in
                    GameCard(
                        event: event, lineup: store.lineup(for: event), status: hostingStatus(event), time: EventFormat.cardTime(event),
                        onOpen: { open(event) },
                        shortcuts: [GameCardShortcut(name: String.app("Open group chat")) { appViewModel.path.append(.chat(event.id)) }]
                    ) {
                        Button("Edit") { appViewModel.presentGameForm(editing: event.id) }
                            .pill(.secondary, expands: false)
                            .accessibilityLabel(String.app("Edit \(event.title)"))
                            .accessibilityInputLabels([Text("Edit")])
                        chatButton(event)
                    }
                }
            }
        }
    }

    /// "3 joined · room for 6 more", then the auto-repost line when there's news (SPEC §7.6.11).
    private func hostingStatus(_ event: Game) -> String {
        guard event.autoRepost, let repostedAt = event.repostedAt else { return event.hostingLine }
        let when = Date.now.timeIntervalSince(repostedAt) < 60
            ? String.app("Reposted just now")
            : String.app("Reposted \(repostedAt.formatted(.relative(presentation: .named).locale(LanguageSettings.shared.locale)))")
        return "\(event.hostingLine)\n\(when)"
    }

    /// The game's detail, from a tap on its card.
    private func open(_ event: Game) {
        appViewModel.path.append(.game(event.id))
    }

    private func chatButton(_ event: Game) -> some View {
        let unread = store.unreadCount(event.id)
        return NavigationLink(value: Route.chat(event.id)) {
            Text(verbatim: viewModel.chatTitle(unread: unread))
        }
        .pill(.primary)
        .accessibilityLabel(viewModel.chatAccessibilityLabel(for: event.title, unread: unread))
        .accessibilityInputLabels([Text("Group chat")])
    }
}
