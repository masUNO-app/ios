import MapKit
import SwiftUI

/// Figma: "Event detail" (341:2586) and "You're in" (341:2989), plus the 1.0 states
/// from SPEC §7.6.4 (Full, Hosting, Ended, Cancelled). No group chat during the program.
struct EventDetailView: View {
    @Environment(EventStore.self) private var store
    @Environment(AppViewModel.self) private var appViewModel
    @State private var viewModel: EventDetailViewModel

    init(eventID: SportsEvent.ID) {
        _viewModel = State(initialValue: EventDetailViewModel(eventID: eventID))
    }

    var body: some View {
        if let event = viewModel.event(in: store) {
            content(event)
        } else {
            ContentUnavailableView("This game isn't available.", systemImage: "sportscourt")
                .background(Theme.background)
        }
    }

    private func content(_ event: SportsEvent) -> some View {
        @Bindable var viewModel = viewModel
        let state = viewModel.state(of: event)

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
                        Text("\(Person.firstName(event.host)) can see you joined. Check where to meet and who's going.")
                    }
                }
                if !event.notes.isEmpty {
                    section("About") { Text(event.notes) }
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
            ToolbarItem(placement: .topBarTrailing) { overflowMenu(event, state: state) }
        }
        .safeAreaInset(edge: .bottom) { bottomBar(event, state: state) }
        .sheet(isPresented: $viewModel.showsWhoIsGoing) {
            WhoIsGoingSheet(eventID: event.id)
        }
        .sheet(item: $viewModel.reportTarget) { ReportSheet(target: $0) }
        #if DEBUG
        .onAppear {
            // `-screen who` / `-screen report`: open the safety sheets on this game.
            switch UserDefaults.standard.string(forKey: "screen") {
            case "who": viewModel.showsWhoIsGoing = true
            case "report": viewModel.reportTarget = .person(event.host)
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
            Text("We'll let the \(event.attendees.count - 1) people who are going know. This can't be undone.")
        }
    }

    // MARK: Sections

    private func mapHeader(_ event: SportsEvent) -> some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: event.coordinate, latitudinalMeters: 500, longitudinalMeters: 500
        ))) {
            Annotation(event.title, coordinate: event.coordinate, anchor: .bottom) {
                VStack(spacing: -6) {
                    ZStack {
                        Circle().fill(Theme.pin).frame(width: 40, height: 40)
                        Text(event.sport.emoji).font(.system(size: 24))
                    }
                    Triangle().fill(Theme.pin).frame(width: 14, height: 10)
                }
                .shadow(color: Theme.shadow, radius: 3, y: 2)
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

    private func infoCard(_ event: SportsEvent, state: EventDetailViewModel.State) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            detailRow("clock", title: EventFormat.dayAndTime(event.start), subtitle: EventFormat.startsIn(event))
            detailRow("mappin.and.ellipse", title: event.venue.name, subtitle: event.venue.fullAddress)
            if !event.meetUpSpot.isEmpty {
                detailRow("flag", title: event.meetUpSpot, subtitle: nil)
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

    private func whoIsGoingRow(_ event: SportsEvent) -> some View {
        Button {
            viewModel.showsWhoIsGoing = true
        } label: {
            HStack(spacing: 10) {
                AvatarStack(names: store.visibleAttendees(of: event), size: 30)
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

    private func overflowMenu(_ event: SportsEvent, state: EventDetailViewModel.State) -> some View {
        Menu("More", systemImage: "ellipsis") {
            switch state {
            case .hosting:
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

    private func reportGameButton(_ event: SportsEvent) -> some View {
        Button("Report game", systemImage: "flag") { viewModel.reportTarget = .game(event.id) }
    }

    @ViewBuilder
    private func bottomBar(_ event: SportsEvent, state: EventDetailViewModel.State) -> some View {
        switch state {
        case .open:
            // TODO(auth): verify student email before the first join (E5/B5).
            barButton("Join game") { viewModel.join(in: store) }
        case .hosting:
            barButton("Edit game") { appViewModel.presentGameForm(editing: event.id) }
        case .full:
            Text("Spots open up when someone leaves — check back.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 12)
                .background(Theme.background)
        case .going, .ended, .cancelled:
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
