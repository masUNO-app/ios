import SwiftUI

/// Figma: "Group chat" (341:1791 and one per sport; SPEC §7.6.9, §7.7.3, Appendix A). A band in
/// the sport's color with faint court lines, the pinned card, system rows from `game_activity`
/// (joins as a "+1" pill) and, when `chat_enabled` is on, messages and a composer (E26): theirs
/// on white, yours in the sport's color. With it off, this is the read-only hub (N14).
struct GroupChatView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let eventID: UUID

    @State private var viewModel: ChatViewModel
    @State private var showsWhoIsGoing = false
    @State private var editsMeetUp = false
    @State private var reportTarget: ReportSubject?
    @State private var blockTarget: PersonSummary?
    @State private var position = ScrollPosition(edge: .bottom)
    /// The first page is on screen, so from here a new row is news worth animating to.
    @State private var hasShownLatest = false
    @FocusState private var composerIsFocused: Bool

    /// How far the sport band reaches down from the top of the screen.
    private static let bandHeight: CGFloat = 175

    init(eventID: UUID) {
        self.eventID = eventID
        _viewModel = State(initialValue: ChatViewModel(gameID: eventID))
    }

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
        let rows = store.isChatEnabled ? viewModel.rows(in: store) : store.activity(of: eventID).map(ChatViewModel.Row.activity)
        let lastJoin = Self.latestJoin(in: store.activity(of: eventID))

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                if store.isChatEnabled { olderMessages }
                ForEach(rows) { row in
                    rowView(row, in: event, lastJoin: lastJoin)
                }
            }
            .padding(.horizontal, 19)
            .padding(.vertical, 12)
            .readableColumn()
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { pinnedCard(event) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.isChatEnabled { bottomBar(event) }
        }
        .background { band(event) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(verbatim: event.title)
                        .font(.rounded(.headline, .bold))
                    Text(verbatim: "\(event.activity.emoji) \(event.activity.name) · \(String(localized: "\(event.goingCount) going"))")
                        .font(.rounded(.caption))
                }
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsWhoIsGoing = true } label: {
                    let people = store.lineup(for: event)
                    TokenStack(
                        people: Array(people.people.prefix(3)),
                        extra: event.goingCount - min(people.people.count, 3),
                        maxVisible: 3, size: 30, ring: 2
                    )
                }
                .accessibilityLabel("Who's going")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $showsWhoIsGoing) { WhoIsGoingSheet(eventID: eventID) }
        .sheet(isPresented: $editsMeetUp) { WhereToMeetSheet(event: event) }
        .sheet(item: $reportTarget) { ReportSheet(target: $0) }
        .dialog(isPresented: $viewModel.asksForRules, isDismissable: false) {
            ChatRulesDialog(gameTitle: event.title) { agreed in
                if agreed {
                    Task { await viewModel.acceptRules(in: store) }
                } else {
                    dismiss()
                }
            }
        }
        .blockDialog($blockTarget)
        .refreshable { await load() }
        .task { await load() }
        .task(id: store.isChatEnabled) {
            guard store.isChatEnabled else { return }
            // Asked once per account, the first time you open any chat you can post in.
            if event.isChatOpen(), let profile = store.profile, profile.chatRulesAcceptedAt == nil {
                viewModel.asksForRules = true
            }
            await viewModel.open(in: store)
        }
        .task(id: store.isChatEnabled) {
            guard store.isChatEnabled else { return }
            await viewModel.poll(in: store)
        }
        // Follow the conversation: a new last row scrolls into view; loading older pages doesn't.
        // While the chat is still loading, land on the newest message without a visible scroll.
        .onChange(of: rows.last?.id) {
            if hasShownLatest {
                withAnimation { position.scrollTo(edge: .bottom) }
            } else {
                position.scrollTo(edge: .bottom)
            }
            if !store.isChatEnabled || viewModel.state == .loaded { hasShownLatest = true }
        }
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.string(forKey: "screen") == "meetup" { editsMeetUp = true }
        }
        #endif
    }

    private func load() async {
        await store.loadAttendees(eventID)
        await store.loadActivity(eventID)
        if store.isChatEnabled, viewModel.state != .idle { await viewModel.reload(in: store) }
    }

    // MARK: Band and pinned card

    /// The sport's color across the top, with the top of its court drawn faintly, over the page.
    private func band(_ event: Game) -> some View {
        VStack(spacing: 0) {
            event.activity.color
                .overlay(alignment: .top) {
                    GeometryReader { geo in
                        CourtArt(kind: event.activity.court, scale: geo.size.width / CourtArt.designWidth * 1.05)
                            .frame(height: 400)
                            .offset(y: -44)
                            .opacity(0.45)
                    }
                }
                .frame(height: Self.bandHeight)
                .clipped()
            Theme.surface2
        }
        .ignoresSafeArea()
    }

    private func pinnedCard(_ event: Game) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(EventFormat.dayAndTime(event.startsAt), systemImage: "calendar")
            Label {
                Text(verbatim: event.place.name)
            } icon: {
                PlaceIcon(size: 16)
            }
            HStack(alignment: .center) {
                Label {
                    Text(event.meetPoint ?? String(localized: "No meet-up spot yet"))
                        .fontWeight(.bold)
                } icon: {
                    Image(systemName: "flag")
                }
                Spacer(minLength: 8)
                if event.status() == .hosting {
                    Button("Edit") { editsMeetUp = true }
                        .pill(.secondary, expands: false, size: .small)
                }
            }
        }
        .font(.rounded(.footnote))
        .foregroundStyle(Theme.ink)
        .labelStyle(IconRowLabelStyle(iconWidth: 16, spacing: 10))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.separator))
        .shadow(color: Theme.ink.opacity(0.06), radius: 6, y: 2)
        .padding(.horizontal, 15)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .readableColumn()
    }

    // MARK: Timeline

    @ViewBuilder
    private var olderMessages: some View {
        if case .failed = viewModel.state {
            RetryCard(message: "Couldn't load messages.") { await viewModel.reload(in: store) }
        } else if viewModel.hasOlder {
            Button("Earlier messages") { Task { await viewModel.loadOlder(in: store) } }
                .pill(.quiet, expands: false, size: .small)
                .disabled(viewModel.isLoadingOlder)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func rowView(_ row: ChatViewModel.Row, in event: Game, lastJoin: UUID?) -> some View {
        switch row {
        case .day(let date):
            Text(EventFormat.day(date))
                .font(.rounded(.caption, .bold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.separator, in: .capsule)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        case .activity(let entry):
            // One pill, for the newest join: a long run of them would bury the conversation.
            if entry.id == lastJoin {
                joinPill(entry, in: event)
            } else {
                systemRow(entry)
            }
        case .message(let message, let showsSender):
            if message.sender.id == store.profile?.id {
                ownMessage(message.body, color: event.activity.color, caption: showsSender ? Text(message.createdAt, format: .dateTime.hour().minute()) : nil)
                    .contextMenu { copyButton(message.body) }
            } else {
                theirMessage(message, showsSender: showsSender, isHost: message.sender.id == event.host.id)
            }
        case .pending(let pending):
            pendingMessage(pending, color: event.activity.color)
        }
    }

    /// The newest join, if nobody has left since: only that one can say how much room is left now.
    private static func latestJoin(in activity: [GameActivityEntry]) -> UUID? {
        guard let last = activity.last(where: { $0.kind == .joined || $0.kind == .left }), last.kind == .joined else { return nil }
        return last.id
    }

    private func name(of entry: GameActivityEntry) -> String {
        if entry.actor?.id == store.profile?.id { return String(localized: "You") }
        return entry.actor?.firstName ?? String(localized: "Someone")
    }

    /// "+1 Emilio took a spot · room for 3 more", or "took the last spot · game is full".
    private func joinPill(_ entry: GameActivityEntry, in event: Game) -> some View {
        let name = name(of: entry)
        let text: String = if event.isFull {
            String(localized: "\(name) took the last spot · game is full")
        } else {
            String(localized: "\(name) took a spot · \(event.roomPhrase)")
        }

        return HStack(spacing: 8) {
            Circle()
                .fill(event.activity.color)
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1.5))
                .overlay {
                    Text(verbatim: "+1")
                        .font(.rounded(size: 10))
                        .foregroundStyle(Theme.ink)
                }
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.rounded(.footnote, .bold))
                .foregroundStyle(Theme.ink)
        }
        .padding(.leading, 5)
        .padding(.trailing, 14)
        .padding(.vertical, 5)
        .background(Theme.card, in: .capsule)
        .overlay(Capsule().strokeBorder(Theme.hairline))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

    private func systemRow(_ entry: GameActivityEntry) -> some View {
        Text(verbatim: text(for: entry))
            .font(.rounded(.caption))
            .foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
    }

    /// "Maya created the chat", "Leo left · a spot opened", "Meet-up spot updated · 5:42 PM".
    private func text(for entry: GameActivityEntry) -> String {
        let name = name(of: entry)
        let time = entry.at.formatted(date: .omitted, time: .shortened)
        return switch entry.kind {
        case .created: String(localized: "\(name) created the chat")
        case .joined: String(localized: "\(name) took a spot")
        case .left: String(localized: "\(name) left · a spot opened")
        case .meetPointUpdated: String(localized: "Meet-up spot updated · \(time)")
        case .timeOrPlaceChanged: String(localized: "Time or place changed · \(time)")
        case .cancelled: String(localized: "Game cancelled · Chat closed")
        }
    }

    /// "Maya C. · Host · 5:42 PM" over a white bubble. Touch and hold to report or block.
    private func theirMessage(_ message: ChatMessage, showsSender: Bool, isHost: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if showsSender {
                PersonAvatar(person: message.sender, size: 30)
            } else {
                Color.clear.frame(width: 30, height: 1)
            }
            VStack(alignment: .leading, spacing: 3) {
                if showsSender {
                    HStack(spacing: 4) {
                        Text(verbatim: message.sender.displayName)
                        if isHost { Text("· Host") }
                        Text(verbatim: "· \(message.createdAt.formatted(date: .omitted, time: .shortened))")
                    }
                    .font(.rounded(.caption))
                    .foregroundStyle(Theme.muted)
                }
                Text(verbatim: message.body)
                    .font(.rounded(.callout))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .background(Theme.card, in: .rect(cornerRadius: 20))
                    .contentShape(.contextMenuPreview, .rect(cornerRadius: 20))
                    .contextMenu {
                        copyButton(message.body)
                        Button("Report message", systemImage: "exclamationmark.bubble") { reportTarget = .message(message) }
                        Button("Block \(message.sender.displayName)", systemImage: "nosign", role: .destructive) {
                            blockTarget = message.sender
                        }
                    }
            }
            Spacer(minLength: 40)
        }
        .padding(.top, showsSender ? 4 : 0)
        .accessibilityElement(children: .combine)
    }

    /// Your bubble, in the sport's color with ink text; the time sits under it.
    private func ownMessage(_ body: String, color: Color, caption: Text?, isFaded: Bool = false) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(verbatim: body)
                .font(.rounded(.callout))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(color.opacity(isFaded ? 0.5 : 1), in: .rect(cornerRadius: 20))
                .contentShape(.contextMenuPreview, .rect(cornerRadius: 20))
            if let caption {
                caption.font(.rounded(.caption)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 60)
        .padding(.top, caption == nil ? 0 : 4)
    }

    /// Your message on its way, or one that didn't send: "Not sent · Tap to retry".
    private func pendingMessage(_ pending: ChatViewModel.Pending, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            ownMessage(pending.body, color: color, caption: nil, isFaded: true)
            if let error = pending.error {
                Label(failureText(error), systemImage: "exclamationmark.circle.fill")
                    .font(.rounded(.caption))
                    .foregroundStyle(Theme.error)
            } else {
                Text("Sending…").font(.rounded(.caption)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contentShape(.rect)
        .onTapGesture { viewModel.retry(pending.id, in: store) }
        .contextMenu {
            if pending.error != nil {
                Button("Try again", systemImage: "arrow.clockwise") { viewModel.retry(pending.id, in: store) }
                Button("Delete", systemImage: "trash", role: .destructive) { viewModel.discard(pending.id) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(pending.error == nil ? [] : .isButton)
    }

    /// A lost connection only needs another try; anything else says why.
    private func failureText(_ error: DomainError) -> String {
        switch error {
        case .offline, .unknown: String(localized: "Not sent · Tap to retry")
        default: String(localized: "Not sent · \(error.message)")
        }
    }

    private func copyButton(_ text: String) -> some View {
        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
    }

    // MARK: Composer

    @ViewBuilder
    private func bottomBar(_ event: Game) -> some View {
        if event.isChatOpen() {
            composer(event)
        } else if event.isGoing {
            // The server refuses messages here too (`cancelled`, `ended`).
            Text(event.isCancelled ? "This game was cancelled, so the chat is closed." : "This chat closed 24 hours after the game ended.")
                .font(.rounded(.footnote))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 12)
        }
    }

    /// Glass "Message" field with a send button in the sport's color.
    private func composer(_ event: Game) -> some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 6) {
            if let error = viewModel.draftError {
                Text(error)
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.error)
                    .padding(.horizontal, 14)
            }
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.rounded(.body))
                    .focused($composerIsFocused)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 23))
                    .onChange(of: viewModel.draft) {
                        if viewModel.draft.count > ChatMessage.bodyLimit {
                            viewModel.draft = String(viewModel.draft.prefix(ChatMessage.bodyLimit))
                        }
                        viewModel.draftError = nil
                    }
                Button("Send", systemImage: "arrow.up") { viewModel.send(in: store) }
                    .labelStyle(.iconOnly)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.ink)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(event.activity.color)
                    // Stays in the sport's color; an empty draft just doesn't send.
                    .opacity(viewModel.canSend ? 1 : 0.75)
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .readableColumn()
        // Solid, so messages don't show through under the field.
        .background(Theme.surface2)
    }
}
