import MapKit
import SwiftUI

/// Figma: "Event detail" (341:2586) and "You're in" (341:2989), plus the 1.0 states
/// from SPEC §7.6.4 (Full, Hosting, Ended, Cancelled).
struct EventDetailView: View {
    @Environment(GameStore.self) private var store
    @Environment(AppViewModel.self) private var appViewModel
    @State private var viewModel: EventDetailViewModel

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
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
        }
        .task(id: viewModel.eventID) {
            await store.loadGame(viewModel.eventID)
            await store.loadAttendees(viewModel.eventID)
        }
    }

    private func content(_ event: Game) -> some View {
        @Bindable var viewModel = viewModel
        let state = event.status()

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                mapHeader(event)

                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.ink)
                    Text(event.hostLine)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    StatusChip(viewModel.chipText(for: event), systemImage: viewModel.chipIcon(for: event))
                        .padding(.top, 2)
                }

                infoCard(event, state: state)

                if state == .going {
                    section("Before you go") {
                        // Read-only group chat copy (SPEC §7.2, N14).
                        Text("\(event.host.firstName) can see you joined. Check where to meet and who's going.")
                    }
                }
                if let notes = event.notes {
                    section("About") { Text(notes) }
                }
                section("Who's going") { whoIsGoingRow(event) }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        // The large title is in the content, so the bar stays empty.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { BookmarkButton(event: event, inToolbar: true) }
            ToolbarItem(placement: .topBarTrailing) { overflowMenu(event, state: state).tint(Theme.ink) }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar(event, state: state)
                .padding(.top, 12)
                .background(Theme.background)
                .overlay(alignment: .top) { Divider().overlay(Theme.hairline) }
        }
        .sheet(isPresented: $viewModel.showsWhoIsGoing) {
            WhoIsGoingSheet(eventID: event.id)
        }
        .sheet(item: $viewModel.reportTarget) { ReportSheet(target: $0) }
        .sheet(isPresented: $viewModel.addsToCalendar) {
            CalendarEditor(event: event).ignoresSafeArea()
        }
        #if DEBUG
        .onAppear {
            // `-screen who` / `-screen report`: open the safety sheets on this game.
            switch UserDefaults.standard.string(forKey: "screen") {
            case "who": viewModel.showsWhoIsGoing = true
            case "report": viewModel.reportTarget = .person(event.host)
            case "calendar": viewModel.addsToCalendar = true
            default: break
            }
        }
        #endif
        .alert(Text("Leave \(event.title)?"), isPresented: $viewModel.confirmsLeave) {
            Button("Leave game", role: .destructive) { viewModel.leave(in: store) }
            Button("Stay in", role: .cancel) {}
        } message: {
            Text("Your spot opens up for someone else.")
        }
        .alert(Text("Cancel \(event.title)?"), isPresented: $viewModel.confirmsCancel) {
            Button("Cancel game", role: .destructive) { viewModel.cancel(in: store) }
            Button("Keep game", role: .cancel) {}
        } message: {
            Text("We'll let the \(event.goingCount - 1) people who are going know. This can't be undone.")
        }
    }

    // MARK: Sections

    private func mapHeader(_ event: Game) -> some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: event.coordinate, latitudinalMeters: 500, longitudinalMeters: 500
        ))) {
            Annotation(event.title, coordinate: event.coordinate, anchor: .bottom) {
                PinMarker(size: 40) {
                    Text(event.activity.emoji).font(.system(size: 24))
                }
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)
        .frame(height: 130)
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.hairline))
        .accessibilityHidden(true)
    }

    private func infoCard(_ event: Game, state: GameStatus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            detailRow("clock", title: EventFormat.dayAndTime(event.startsAt), subtitle: EventFormat.startsIn(event))
            detailRow("mappin.and.ellipse", title: event.place.name, subtitle: event.place.address)
            if let meetPoint = event.meetPoint {
                detailRow("flag", title: meetPoint, subtitle: nil)
            } else if state == .hosting {
                Button {
                    appViewModel.presentGameForm(editing: event.id)
                } label: {
                    Label("Add a meet-up spot so people know where to find you", systemImage: "flag")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .multilineTextAlignment(.leading)
                }
                .labelStyle(MutedIconLabelStyle())
            }
            Button("Open in Maps", systemImage: "arrow.up.right.square") { viewModel.openInMaps(event) }
                .buttonStyle(.glassProminent)
                .tint(Theme.accentSoft)
                .foregroundStyle(Theme.ink)
                .controlSize(.large)
                .buttonSizing(.flexible)
                .confirmationDialog("Open in", isPresented: $viewModel.choosesMapsApp) {
                    Button("Apple Maps") { viewModel.openInAppleMaps(event) }
                    Button("Google Maps") { viewModel.openInGoogleMaps(event) }
                }
            if state == .going || state == .hosting {
                Button("Add to calendar", systemImage: "calendar.badge.plus") { viewModel.addsToCalendar = true }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accentSoft)
                    .foregroundStyle(Theme.ink)
                    .controlSize(.large)
                    .buttonSizing(.flexible)
            }
        }
        .padding(16)
        .cardSurface()
    }

    private func detailRow(_ systemImage: String, title: String, subtitle: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.muted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            content()
                .font(.body)
                .foregroundStyle(Theme.ink)
        }
    }

    private func whoIsGoingRow(_ event: Game) -> some View {
        Button {
            viewModel.showsWhoIsGoing = true
        } label: {
            HStack(spacing: 10) {
                AvatarStack(names: store.attendees(of: event.id).map(\.person.displayName), size: 30)
                Text(viewModel.goingNames(for: event, in: store))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Who's going: \(viewModel.goingNames(for: event, in: store))"))
    }

    // MARK: Actions

    private func overflowMenu(_ event: Game, state: GameStatus) -> some View {
        Menu("More", systemImage: "ellipsis") {
            switch state {
            case .hosting:
                inviteLink(event)
                Button("Cancel game", systemImage: "xmark.circle", role: .destructive) {
                    viewModel.confirmsCancel = true
                }
            case .going:
                Button("Leave game", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    viewModel.confirmsLeave = true
                }
                reportGameButton(event)
            default:
                reportGameButton(event)
            }
        }
    }

    /// TODO/TEMP(E19): shares an App Store search link (`AppConfig.inviteURL`) until the
    /// listing exists; the friend signs in with their own Tec email.
    private func inviteLink(_ event: Game) -> some View {
        ShareLink(
            item: AppConfig.inviteURL,
            subject: Text(event.title),
            message: Text(viewModel.inviteMessage(for: event))
        ) {
            Label("Invite a friend", systemImage: "person.badge.plus")
        }
    }

    private func reportGameButton(_ event: Game) -> some View {
        Button("Report game", systemImage: "flag") { viewModel.reportTarget = .game(event.id) }
    }

    @ViewBuilder
    private func bottomBar(_ event: Game, state: GameStatus) -> some View {
        switch state {
        case .open:
            barButton("Join game") { viewModel.join(in: store) }
        case .going:
            VStack(spacing: 10) {
                barButton("Open group chat") { appViewModel.path.append(.chat(event.id)) }
                inviteLink(event)
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accentSoft)
                    .foregroundStyle(Theme.ink)
                    .controlSize(.large)
                    .buttonSizing(.flexible)
                    .fontWeight(.semibold)
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 8)
            }
        case .hosting:
            VStack(spacing: 10) {
                barButton("Open group chat") { appViewModel.path.append(.chat(event.id)) }
                Button("Edit game") { appViewModel.presentGameForm(editing: event.id) }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accentSoft)
                    .foregroundStyle(Theme.ink)
                    .controlSize(.large)
                    .buttonSizing(.flexible)
                    .fontWeight(.semibold)
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 8)
            }
        case .full:
            Text("Spots open up when someone leaves — check back.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 12)
        case .ended, .cancelled:
            EmptyView()
        }
    }

    private func barButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .buttonSizing(.flexible)
            .fontWeight(.semibold)
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 8)
    }
}
