import SwiftUI

/// Figma: "Group chat" (341:1791). Not connected yet: shows the game's mock timeline and a
/// disabled composer ("Messages are coming soon") until the chat backend ships.
struct GroupChatView: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let eventID: SportsEvent.ID

    @State private var showsWhoIsGoing = false
    @State private var editsMeetUp = false
    @State private var showsRules = false

    var body: some View {
        if let event = store.event(eventID) {
            content(event)
        } else {
            ContentUnavailableView("This game isn't available.", systemImage: "bubble.left.and.bubble.right")
                .background(Theme.background)
        }
    }

    private func content(_ event: SportsEvent) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                dayChip("Today")
                ForEach(event.messages) { message in
                    row(message, in: event)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)
        }
        .defaultScrollAnchor(.bottom)
        .background(Theme.background)
        .safeAreaInset(edge: .top) { pinnedCard(event) }
        .safeAreaInset(edge: .bottom) { composer }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(event.title).font(.headline).foregroundStyle(Theme.ink)
                    Text("\(event.attendees.count) going").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsWhoIsGoing = true } label: {
                    AvatarStack(names: store.visibleAttendees(of: event), maxVisible: 3, size: 26)
                }
                .accessibilityLabel("Who's going")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $showsWhoIsGoing) { WhoIsGoingSheet(eventID: event.id) }
        .sheet(isPresented: $editsMeetUp) { WhereToMeetSheet(event: event) }
        .sheet(isPresented: $showsRules) {
            ChatRulesSheet(gameTitle: event.title) { agreed in
                showsRules = false
                if agreed { store.hasAgreedToChatRules = true } else { dismiss() }
            }
        }
        .onAppear {
            store.markChatRead(event.id)
            if !store.hasAgreedToChatRules { showsRules = true }
            #if DEBUG
            if UserDefaults.standard.string(forKey: "screen") == "meetup" { editsMeetUp = true }
            #endif
        }
    }

    // MARK: Pinned card

    private func pinnedCard(_ event: SportsEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(EventFormat.dayAndTime(event.start), systemImage: "calendar")
            Label(event.venue.titleLine, systemImage: "mappin.and.ellipse")
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(event.meetUpSpot.isEmpty ? String(localized: "No meet-up spot yet") : event.meetUpSpot)
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: "flag")
                }
                Spacer(minLength: 8)
                if event.isHostedByYou {
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

    private func dayChip(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.hairline, in: .capsule)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func row(_ message: ChatMessage, in event: SportsEvent) -> some View {
        let time = message.sentAt.formatted(date: .omitted, time: .shortened)
        switch message.kind {
        case .system:
            Text(message.text)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
        case .message where message.sender == Person.you:
            VStack(alignment: .trailing, spacing: 4) {
                bubble(message.text, isMine: true)
                Text(time).font(.caption2).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .message:
            HStack(alignment: .bottom, spacing: 8) {
                Avatar(name: message.sender, size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(caption(for: message, in: event, time: time))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    bubble(message.text, isMine: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Maya C. · Host · 5:42 PM"
    private func caption(for message: ChatMessage, in event: SportsEvent, time: String) -> String {
        let name = Person.display(message.sender)
        return message.sender == event.host
            ? String(localized: "\(name) · Host · \(time)")
            : String(localized: "\(name) · \(time)")
    }

    private func bubble(_ text: String, isMine: Bool) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(isMine ? Theme.onAccent : Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isMine ? Theme.accent : Theme.card, in: .rect(cornerRadius: 20))
            .overlay {
                if !isMine { RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.hairline) }
            }
            .frame(maxWidth: 280, alignment: isMine ? .trailing : .leading)
    }

    // MARK: Composer

    /// Disabled until the chat backend is connected.
    private var composer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                TextField("Messages are coming soon", text: .constant(""))
                    .disabled(true)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Theme.card, in: .capsule)
                    .overlay(Capsule().strokeBorder(Theme.hairline))
                Button("Send", systemImage: "arrow.up") {}
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .disabled(true)
            }
            Text("For now, the meet-up spot and who's going are pinned here.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.background)
    }
}
