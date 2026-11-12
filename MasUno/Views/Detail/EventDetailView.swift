import MapKit
import SwiftUI

/// Figma: "Game details" (408:3506 and one per sport), "You're in" (408:3632), "Game's full" and
/// "Your game is live!", plus the ended and cancelled states from SPEC §7.6.4. A full-bleed
/// court with the lineup on it, and a content sheet that overlaps it.
struct EventDetailView: View {
    @Environment(GameStore.self) private var store
    @Environment(AppViewModel.self) private var appViewModel
    @State private var viewModel: EventDetailViewModel
    @State private var size = CGSize(width: CourtArt.designWidth, height: 874)
    /// The sheet has scrolled far enough that its title is under the navigation bar.
    @State private var isTitleUnderBar = false

    /// The court stops growing here, so the header doesn't swallow a big screen.
    private static let maxCourtWidth: CGFloat = 480

    init(eventID: UUID) {
        _viewModel = State(initialValue: EventDetailViewModel(eventID: eventID))
    }

    var body: some View {
        Group {
            if let event = store.game(viewModel.eventID) {
                content(event)
            } else if store.isMissing(viewModel.eventID) {
                ContentUnavailableView("This game isn't available.", systemImage: "sportscourt")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            } else if store.isOffline {
                RetryCard(message: "Couldn't load this game.") { await load() }
                    .padding(.horizontal, Theme.gutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
        }
        .task(id: viewModel.eventID) { await load() }
        .task(id: viewModel.eventID) {
            // You joined from the map: once the push has settled, land on the court.
            guard appViewModel.arrivingIn == viewModel.eventID else { return }
            try? await Task.sleep(for: .milliseconds(500))
            appViewModel.finishArriving()
        }
    }

    private func load() async {
        await store.loadGame(viewModel.eventID)
        await store.loadAttendees(viewModel.eventID)
    }

    private func content(_ event: Game) -> some View {
        @Bindable var viewModel = viewModel
        let state = event.status()
        let scale = min(size.width, Self.maxCourtWidth) / CourtArt.designWidth
        // The sheet's rounded top rides up over the court.
        let courtWindow = CourtHeader.designHeight * scale - Theme.Radius.sheet

        let isOver = event.isCancelled || event.hasEnded()

        // The court stays put and the sheet scrolls up over it.
        return ScrollView {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: courtWindow)
                    .contentShape(.rect)
                    .onTapGesture { viewModel.showsWhoIsGoing = true }
                    .accessibilityHidden(true)

                sheet(event, state: state)
                    // Always reaches the bottom, so the court only ever shows above it.
                    .frame(minHeight: size.height - courtWindow, alignment: .top)
                    .background {
                        // Carries on under the sheet when it bounces past the bottom.
                        UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.sheet, topTrailingRadius: Theme.Radius.sheet)
                            .fill(Theme.background)
                            .padding(.bottom, -size.height)
                    }
            }
        }
        .ignoresSafeArea(edges: .top)
        // The indicator would run down the court.
        .scrollIndicators(.hidden)
        .background(alignment: .top) {
            CourtHeader(
                activity: event.activity, lineup: store.lineup(for: event),
                capacity: event.capacity, scale: scale,
                holdsYou: appViewModel.arrivingIn == event.id, showsOpenSpots: !isOver
            ) {
                viewModel.showsWhoIsGoing = true
            }
            .frame(maxHeight: .infinity, alignment: .top)
            // Sport color behind the court for the pull-down bounce.
            .background(event.activity.color)
            .ignoresSafeArea()
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .refreshable { await load() }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y > courtWindow - 70
        } action: { _, isUnder in
            withAnimation(.easeOut(duration: 0.2)) { isTitleUnderBar = isUnder }
        }
        // Nothing dims the court behind the bar's two buttons; the bar only steps in once the
        // sheet's own title has scrolled up under it.
        .scrollEdgeEffectHidden(!isTitleUnderBar, for: .top)
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
            }
            ToolbarItem(placement: .topBarTrailing) { overflowMenu(event, state: state).tint(Theme.ink) }
        }
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
            Button("Google Maps") { viewModel.openInGoogleMaps(event) }
        }
        .leaveGameDialog($viewModel.leaving)
        .cancelGameDialog($viewModel.cancelling)
        .sensoryFeedback(.success, trigger: state == .going)
        #if DEBUG
        .onAppear {
            // `-screen who|report|invite|calendar|leave`: open a sheet or dialog on this game.
            switch UserDefaults.standard.string(forKey: "screen") {
            case "who", "block": viewModel.showsWhoIsGoing = true
            case "report", "report-sent": viewModel.reportTarget = .person(event.host)
            case "invite": viewModel.showsInvite = true
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

            availability(event)

            VStack(alignment: .leading, spacing: 12) {
                if let notes = event.notes { hostNote(notes, event: event) }
                detailsCard(event, state: state)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .readableColumn()
    }

    /// "Room for 4 more" · **Who's going ›**, and the line under it once you're in.
    private func availability(_ event: Game) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: viewModel.headline(for: event))
                    .font(.rounded(.headline, .bold))
                    .foregroundStyle(viewModel.isCelebrating(event) ? Theme.accent : Theme.ink)
                    .contentTransition(.opacity)
                Spacer(minLength: 12)
                Button {
                    viewModel.showsWhoIsGoing = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Who's going")
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.ink)
                    }
                    .font(.rounded(.subheadline, .bold))
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            if let detail = viewModel.detail(for: event, chatEnabled: store.isChatEnabled) {
                Text(verbatim: detail)
                    .font(.rounded(.subheadline))
                    .foregroundStyle(Theme.mutedLarge)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: event.status())
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
        }
        .padding(14)
        .background(.white, in: .rect(cornerRadius: 18))
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
                        .labelStyle(IconRowLabelStyle(iconWidth: 20, spacing: 12))
                        .font(.rounded(.subheadline, .bold))
                        .foregroundStyle(Theme.accent)
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
                    store.toggleSaved(event.id)
                }
            }
            switch state {
            case .hosting:
                Button("Open group chat", systemImage: "bubble.left.and.bubble.right") {
                    appViewModel.path.append(.chat(event.id))
                }
                Button("Open in Maps", systemImage: "arrow.up.forward.square") { viewModel.openInMaps(event) }
                Button("Cancel game", systemImage: "xmark.circle", role: .destructive) {
                    viewModel.cancelling = event
                }
            case .going:
                Button("Open in Maps", systemImage: "arrow.up.forward.square") { viewModel.openInMaps(event) }
                reportGameButton(event)
                Button("Leave game", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    viewModel.leaving = event
                }
            default:
                reportGameButton(event)
            }
        }
    }

    private func reportGameButton(_ event: Game) -> some View {
        Button("Report game", systemImage: "flag") { viewModel.reportTarget = .game(event.id) }
    }

    /// The sticky bar: one green action, with a mint one beside it once you're in.
    @ViewBuilder
    private func actionBar(_ event: Game, state: GameStatus) -> some View {
        let canInvite = AppConfig.inviteURL != nil

        Group {
            switch state {
            case .open:
                barColumn(caption: "One tap and you're in. Change your mind anytime.") {
                    Button("Count me in") { viewModel.join(in: store) }
                        .pill(.primary)
                }
            case .going:
                HStack(spacing: 10) {
                    Button("Open group chat") { appViewModel.path.append(.chat(event.id)) }
                        .pill(.primary)
                    // Hidden until `AppConfig.appStoreID` is set (N27).
                    if canInvite {
                        Button("Invite a friend") { viewModel.showsInvite = true }
                            .pill(.secondary)
                    }
                }
            case .hosting:
                HStack(spacing: 10) {
                    if canInvite {
                        Button("Share game") { viewModel.showsInvite = true }
                            .pill(.primary)
                    } else {
                        Button("Open group chat") { appViewModel.path.append(.chat(event.id)) }
                            .pill(.primary)
                    }
                    Button("Edit game") { appViewModel.presentGameForm(editing: event.id) }
                        .pill(.secondary)
                }
            case .full:
                let isOn = store.hasSpotAlert(event.id)
                barColumn(caption: isOn
                    ? "We'll tell you in the app when someone drops out. Tap to turn it off."
                    : "We'll tell you in the app the moment someone drops out.") {
                    Button(isOn ? "Spot alert is on" : "Alert me if a spot opens") {
                        withAnimation(.snappy) { store.toggleSpotAlert(event.id) }
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
