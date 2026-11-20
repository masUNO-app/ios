import MapKit
import SwiftUI

/// Figma: "Game details" (408:3506 and one per sport), "You're in" (408:3632), "Game's full" and
/// "Your plan is live!", plus the ended and cancelled states from SPEC §7.6.4. A full-bleed
/// court with the lineup on it, and a content sheet that overlaps it.
struct EventDetailView: View {
    @Environment(GameStore.self) private var store
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var viewModel: EventDetailViewModel
    /// The sheet has scrolled far enough that its title is under the navigation bar.
    @State private var isTitleUnderBar = false

    init(eventID: UUID) {
        _viewModel = State(initialValue: EventDetailViewModel(eventID: eventID))
    }

    var body: some View {
        Group {
            if let event = store.game(viewModel.eventID) {
                content(event)
            } else if store.isMissing(viewModel.eventID) {
                ContentUnavailableView("This plan isn't available.", systemImage: "calendar.badge.exclamationmark")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            } else if store.isOffline {
                RetryCard(message: "Couldn't load this plan.") { await load() }
                    .padding(.horizontal, Theme.gutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            } else {
                ProgressView()
                    .accessibilityLabel(Text("Loading plan"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
        }
        .task(id: viewModel.eventID) { await load() }
        .onAppear {
            AppGroupStore.openGameID = viewModel.eventID.uuidString
            PushNotificationService.clearDelivered(thread: "game:\(viewModel.eventID.uuidString)")
        }
        .onDisappear {
            if AppGroupStore.openGameID == viewModel.eventID.uuidString { AppGroupStore.openGameID = nil }
        }
        .task(id: viewModel.eventID) {
            // You joined from the map: once the push has settled, land on the court.
            guard appViewModel.arrivingIn == viewModel.eventID else { return }
            try? await Task.sleep(for: .milliseconds(500))
            appViewModel.finishArriving()
        }
    }

    private func load() async {
        await store.loadGame(viewModel.eventID)
        // Guest previews have no attendee names to fetch.
        if let event = store.game(viewModel.eventID), !event.hidesPeople {
            await store.loadAttendees(viewModel.eventID)
        }
    }

    /// Guests, and games that hide their people, get the account prompt instead of the list.
    private func showsAccountPrompt(for event: Game?) -> Bool {
        store.isGuest || event?.hidesPeople == true
    }

    /// Who's going / court tap: guests get the account card instead of empty faces.
    private func openWhoIsGoing() {
        if showsAccountPrompt(for: store.game(viewModel.eventID)) {
            appViewModel.requireAccount(.whosGoing)
        } else {
            viewModel.showsWhoIsGoing = true
        }
    }

    private func content(_ event: Game) -> some View {
        @Bindable var viewModel = viewModel
        let state = event.status()
        let isOver = event.isCancelled || event.hasEnded()

        // The court stays put and the sheet scrolls up over it.
        return CourtScaffold(
            activity: event.activity, lineup: store.lineup(for: event), capacity: event.capacity,
            holdsYou: appViewModel.arrivingIn == event.id, showsOpenSpots: !isOver,
            onTap: { openWhoIsGoing() },
            tapHint: showsAccountPrompt(for: event) ? "Create an account to see who's going" : "Shows who's going",
            onSheetUnderBar: { isUnder in
                withAnimation(.easeOut(duration: 0.2)) { isTitleUnderBar = isUnder }
            }
        ) {
            sheet(event, state: state)
        }
        .refreshable { await load() }
        // Nothing dims the court behind the bar's two buttons; the bar only steps in once the
        // sheet's own title has scrolled up under it.
        .appScrollEdgeEffectHidden(!isTitleUnderBar, for: .top)
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The title is in the content; the bar shows it once that one has scrolled away.
            ToolbarItem(placement: .principal) {
                Text(verbatim: event.title)
                    .font(.rounded(.headline, .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .opacity(isTitleUnderBar ? 1 : 0)
                    .accessibilityHidden(!isTitleUnderBar)
                    // The bar keeps its text small; a long press shows the title big (A11Y-24).
                    .accessibilityShowsLargeContentViewer { Text(verbatim: event.title) }
            }
            ToolbarItem(placement: .topBarTrailing) { overflowMenu(event, state: state).tint(Theme.ink) }
        }
        // Over the court the bar's glass buttons keep ink on the sport color in dark mode; over
        // the sheet they follow it.
        .toolbarColorScheme(isTitleUnderBar ? nil : .light, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar(event, state: state)
        }
        .sheet(isPresented: $viewModel.showsWhoIsGoing) {
            WhoIsGoingSheet(eventID: event.id)
        }
        .sheet(isPresented: $viewModel.showsInvite) {
            InviteSheet(event: event)
        }
        .sheet(item: $viewModel.reportTarget) { ReportSheet(target: $0) }
        .sheet(isPresented: $viewModel.addsToCalendar) {
            CalendarEditor(event: event).ignoresSafeArea()
        }
        .confirmationDialog("Open in", isPresented: $viewModel.choosesMapsApp) {
            Button("Apple Maps") { viewModel.openInAppleMaps(event) }
            Button("Google Maps") {
                if let url = EventDetailViewModel.googleMapsURL(for: event) { openURL(url) }
            }
        }
        .leaveGameDialog($viewModel.leaving)
        .cancelGameDialog($viewModel.cancelling)
        .sensoryFeedback(.success, trigger: state == .going)
        .onChange(of: state) { old, new in
            if let message = viewModel.joinAnnouncement(from: old, to: new, for: event) { Announce.post(message) }
        }
        #if DEBUG
        .onAppear {
            // `-screen who|who-beta|report|invite|invite-code|calendar|leave`: open a sheet or dialog on this game.
            switch UserDefaults.standard.string(forKey: "screen") {
            case "who", "who-beta", "block": viewModel.showsWhoIsGoing = true
            case "report", "report-sent": viewModel.reportTarget = .person(event.host)
            case "invite", "invite-code": viewModel.showsInvite = true
            case "calendar": viewModel.addsToCalendar = true
            case "leave": viewModel.leaving = event
            default: break
            }
        }
        #endif
    }

    // MARK: Content sheet

    private func sheet(_ event: Game, state: GameStatus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: event.title)
                    .font(.rounded(.title, .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: event.hostLine)
                    .font(.rounded(.subheadline))
                    .foregroundStyle(Theme.mutedLarge)
            }

            availability(event, state: state)

            VStack(alignment: .leading, spacing: 12) {
                if let notes = event.notes { hostNote(notes, event: event) }
                detailsCard(event, state: state)
            }
        }
    }

    /// "Room for 4 more" · **Who's going ›**, and the line under it once you're in. Who's going
    /// goes under the headline at accessibility sizes (A11Y-06).
    private func availability(_ event: Game, state: GameStatus) -> some View {
        let headline = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))

        return VStack(alignment: .leading, spacing: 4) {
            headline {
                Text(verbatim: viewModel.headline(for: event))
                    .font(.rounded(.headline, .bold))
                    .foregroundStyle(viewModel.isCelebrating(event) ? Theme.accentText : Theme.ink)
                    .contentTransition(.opacity)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 12) }
                Button {
                    openWhoIsGoing()
                } label: {
                    HStack(spacing: 4) {
                        Text("Who's going")
                            .buttonShapeUnderline()
                        RowAccessory(font: .caption.weight(.bold), color: Theme.ink)
                    }
                    .font(.rounded(.subheadline, .bold))
                    .foregroundStyle(Theme.accentText)
                    // 44 pt tall to tap, without moving the line (A11Y-19).
                    .tapTarget(.vertical, 13)
                }
                .buttonStyle(.plain)
                .padding(.vertical, -13)
            }
            if let detail = viewModel.detail(for: event, chatEnabled: store.isChatEnabled) {
                Text(verbatim: detail)
                    .font(.rounded(.subheadline))
                    .foregroundStyle(Theme.mutedLarge)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: state)
    }

    /// "Alex says": the host's note, next to their token.
    private func hostNote(_ notes: String, event: Game) -> some View {
        HStack(alignment: .top, spacing: 12) {
            PersonAvatar(person: event.host, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: viewModel.noteLabel(for: event))
                    .font(.rounded(.footnote, .bold))
                    .foregroundStyle(Theme.muted)
                Text(verbatim: notes)
                    .font(.rounded(.subheadline))
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // "Alex says" and the note in one stop (A11Y-13). The token stays out: combined, its
            // fixed-size initials would join the element.
            .accessibilityElement(children: .combine)
        }
        .padding(14)
        .background(Theme.paper, in: .rect(cornerRadius: 18))
    }

    private func detailsCard(_ event: Game, state: GameStatus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            detailRow("clock") {
                Text(verbatim: EventFormat.dayAndTime(event.startsAt))
                    .font(.rounded(.callout, .bold))
                    .foregroundStyle(Theme.ink)
                Text(verbatim: EventFormat.startsIn(event))
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.muted)
            }
            // The time and how soon it starts in one stop (A11Y-13).
            .accessibilityElement(children: .combine)

            // The address doubles as a way into Maps once the card's button is Add to calendar.
            Button {
                viewModel.openInMaps(event)
            } label: {
                detailRow(nil) {
                    Text(verbatim: event.place.name)
                        .font(.rounded(.subheadline, .bold))
                        .foregroundStyle(Theme.ink)
                    Text(verbatim: event.place.name == event.place.street ? event.place.locality : event.place.address)
                        .font(.rounded(.footnote))
                        .foregroundStyle(Theme.mutedLarge)
                    if let meetPoint = event.meetPoint {
                        Text(verbatim: meetPoint)
                            .font(.rounded(.footnote))
                            .foregroundStyle(Theme.mutedLarge)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens directions in Maps")

            if event.meetPoint == nil, state == .hosting {
                Button {
                    appViewModel.presentGameForm(editing: event.id)
                } label: {
                    Label("Add a meet-up spot so people know where to find you", systemImage: "flag")
                        .buttonShapeUnderline()
                        .labelStyle(IconRowLabelStyle(iconWidth: 20, spacing: 12))
                        .font(.rounded(.subheadline, .bold))
                        .foregroundStyle(Theme.accentText)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }

            if state == .going || state == .hosting {
                Button("Add to calendar", systemImage: "calendar.badge.plus") { viewModel.addsToCalendar = true }
                    .pill(.secondary, size: .regular)
            } else {
                Button("Open in Maps", systemImage: "arrow.up.forward.square") { viewModel.openInMaps(event) }
                    .pill(.secondary, size: .regular)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 20)
    }

    /// `systemImage` nil draws the place pin.
    private func detailRow(_ systemImage: String?, @ViewBuilder text: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).font(.body.weight(.medium))
                } else {
                    PlaceIcon(size: 20)
                }
            }
            .foregroundStyle(Theme.ink)
            .frame(width: 20, height: 22)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) { text() }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Actions

    private func overflowMenu(_ event: Game, state: GameStatus) -> some View {
        Menu("More", systemImage: "ellipsis") {
            let isSaved = store.isSaved(event.id)
            if state != .hosting {
                Button(isSaved ? "Remove bookmark" : "Bookmark", systemImage: isSaved ? "bookmark.fill" : "bookmark") {
                    if store.isGuest {
                        appViewModel.requireAccount(.save)
                    } else {
                        store.toggleSaved(event.id)
                    }
                }
            }
            switch state {
            case .hosting:
                Button("Open group chat", systemImage: "bubble.left.and.bubble.right") {
                    appViewModel.path.append(.chat(event.id))
                }
                Button("Open in Maps", systemImage: "arrow.up.forward.square") { viewModel.openInMaps(event) }
                Button("Cancel plan", systemImage: "xmark.circle", role: .destructive) {
                    viewModel.cancelling = event
                }
            case .going:
                Button("Open in Maps", systemImage: "arrow.up.forward.square") { viewModel.openInMaps(event) }
                reportGameButton(event)
                Button("Leave plan", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    viewModel.leaving = event
                }
            default:
                Button("Open in Maps", systemImage: "arrow.up.forward.square") { viewModel.openInMaps(event) }
                reportGameButton(event)
            }
        }
    }

    private func reportGameButton(_ event: Game) -> some View {
        Button("Report plan", systemImage: "flag") {
            if store.isGuest {
                appViewModel.requireAccount(.report)
            } else {
                viewModel.reportTarget = .game(event.id)
            }
        }
    }

    /// The sticky bar: one green action, with a mint one beside it once you're in.
    @ViewBuilder
    private func actionBar(_ event: Game, state: GameStatus) -> some View {
        let canInvite = AppConfig.inviteURL != nil

        Group {
            switch state {
            case .open:
                barColumn(caption: store.isGuest
                    ? "Create a student account to take a spot."
                    : "One tap and you're in. Change your mind anytime.") {
                    Button("Count me in") {
                        if store.isGuest {
                            appViewModel.requireAccount(.join)
                        } else {
                            viewModel.join(in: store)
                        }
                    }
                    .pill(.primary)
                    .accessibilityIdentifier("detail-count-me-in")
                }
            case .going:
                PillPair {
                    Button("Open group chat") { appViewModel.path.append(.chat(event.id)) }
                        .pill(.primary)
                        .accessibilityIdentifier("detail-open-chat")
                    // Hidden until `AppConfig.appStoreID` is set (N27).
                    if canInvite {
                        Button("Invite a friend") { viewModel.showsInvite = true }
                            .pill(.secondary)
                    }
                }
            case .hosting:
                PillPair {
                    if canInvite {
                        Button("Share plan") { viewModel.showsInvite = true }
                            .pill(.primary)
                    } else {
                        Button("Open group chat") { appViewModel.path.append(.chat(event.id)) }
                            .pill(.primary)
                            .accessibilityIdentifier("detail-open-chat")
                    }
                    Button("Edit plan") { appViewModel.presentGameForm(editing: event.id) }
                        .pill(.secondary)
                }
            case .full:
                let isOn = store.hasSpotAlert(event.id)
                barColumn(caption: store.isGuest
                    ? "Create an account to hear when a spot opens."
                    : isOn
                    ? "We'll tell you in the app when someone drops out. Tap to turn it off."
                    : "We'll tell you in the app the moment someone drops out.") {
                    Button(isOn ? "Spot alert is on" : "Alert me if a spot opens") {
                        if store.isGuest {
                            appViewModel.requireAccount(.save)
                        } else {
                            withAnimation(.snappy) { store.toggleSpotAlert(event.id) }
                        }
                    }
                    .pill(isOn ? .secondary : .primary)
                    .sensoryFeedback(.selection, trigger: isOn)
                }
            case .ended, .cancelled:
                EmptyView()
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .readableColumn()
        .background(Theme.background)
        .animation(.snappy, value: state)
    }

    private func barColumn(caption: LocalizedStringKey, @ViewBuilder button: () -> some View) -> some View {
        VStack(spacing: 8) {
            button()
            Text(caption)
                .font(.rounded(.footnote))
                .foregroundStyle(Theme.mutedLarge)
                .multilineTextAlignment(.center)
        }
    }
}
