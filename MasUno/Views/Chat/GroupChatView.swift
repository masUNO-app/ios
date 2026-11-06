import SwiftUI

/// Figma: "Group chat" (341:1791), in its read-only form (SPEC §7.6.9, N14): the pinned card
/// and system rows from `game_activity`. No composer and no messages until E26 + B20 ship.
struct GroupChatView: View {
    @Environment(GameStore.self) private var store
    let eventID: UUID

    @State private var showsWhoIsGoing = false
    @State private var editsMeetUp = false

    var body: some View {
        if let event = store.game(eventID) {
            content(event)
        } else {
            ContentUnavailableView("This game isn't available.", systemImage: "bubble.left.and.bubble.right")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
        }
    }

    private func content(_ event: Game) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(store.activity(of: eventID)) { entry in
                    row(entry)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)
        }
        .defaultScrollAnchor(.bottom)
        .background(Theme.background)
        .safeAreaInset(edge: .top) { pinnedCard(event) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(event.title).font(.headline).foregroundStyle(Theme.ink)
                    Text("\(event.goingCount) going").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsWhoIsGoing = true } label: {
                    AvatarStack(names: store.attendees(of: eventID).map(\.person.displayName), maxVisible: 3, size: 26)
                }
                .accessibilityLabel("Who's going")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $showsWhoIsGoing) { WhoIsGoingSheet(eventID: eventID) }
        .sheet(isPresented: $editsMeetUp) { WhereToMeetSheet(event: event) }
        .refreshable { await load() }
        .task { await load() }
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.string(forKey: "screen") == "meetup" { editsMeetUp = true }
        }
        #endif
    }

    private func load() async {
        await store.loadAttendees(eventID)
        await store.loadActivity(eventID)
    }

    // MARK: Pinned card

    private func pinnedCard(_ event: Game) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(EventFormat.dayAndTime(event.startsAt), systemImage: "calendar")
            Label(event.place.titleLine, systemImage: "mappin.and.ellipse")
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(event.meetPoint ?? String(localized: "No meet-up spot yet"))
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: "flag")
                }
                Spacer(minLength: 8)
                if event.status() == .hosting {
                    Button("Edit") { editsMeetUp = true }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accentSoft)
                        .foregroundStyle(Theme.ink)
                        .controlSize(.small)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.ink)
        .labelStyle(MutedIconLabelStyle())
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 4)
    }

    // MARK: Timeline

    private func row(_ entry: GameActivityEntry) -> some View {
        VStack(spacing: 2) {
            Text(text(for: entry))
            Text(EventFormat.dayAndTime(entry.at)).font(.caption2)
        }
        .font(.caption)
        .foregroundStyle(Theme.muted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// "Maya created the chat", "Leo joined", "Leo left · a spot opened".
    private func text(for entry: GameActivityEntry) -> String {
        let name: String
        if entry.actor?.id == store.profile?.id {
            name = String(localized: "You")
        } else {
            name = entry.actor?.firstName ?? String(localized: "Someone")
        }
        return switch entry.kind {
        case .created: String(localized: "\(name) created the chat")
        case .joined: String(localized: "\(name) joined")
        case .left: String(localized: "\(name) left · a spot opened")
        case .meetPointUpdated: String(localized: "Meet-up spot updated")
        case .timeOrPlaceChanged: String(localized: "Time or place changed")
        case .cancelled: String(localized: "Game cancelled · Chat closed")
        }
    }
}
