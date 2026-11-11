import SwiftUI

/// Figma: "Group chat" (341:1791; SPEC §7.6.9, Appendix A). The pinned card, system rows from
/// `game_activity` and, when `chat_enabled` is on, messages and a composer (E26). With it off, this
/// is the read-only hub: no composer and no messages (N14).
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

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if store.isChatEnabled { olderMessages }
                ForEach(rows) { row in
                    rowView(row, in: event)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .safeAreaInset(edge: .top) { pinnedCard(event) }
        .safeAreaInset(edge: .bottom) {
            if store.isChatEnabled { bottomBar(event) }
        }
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
        .sheet(item: $reportTarget) { ReportSheet(target: $0) }
        .sheet(isPresented: $viewModel.asksForRules) {
            ChatRulesSheet(gameTitle: event.title) { agreed in
                if agreed {
                    Task { await viewModel.acceptRules(in: store) }
                } else {
                    viewModel.asksForRules = false
                    dismiss()
                }
            }
        }
        .blockConfirmation(person: $blockTarget)
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

    @ViewBuilder
    private var olderMessages: some View {
        if case .failed = viewModel.state {
            RetryCard(message: "Couldn't load messages.") { await viewModel.reload(in: store) }
        } else if viewModel.hasOlder {
            Button("Earlier messages") { Task { await viewModel.loadOlder(in: store) } }
                .buttonStyle(.glass)
                .controlSize(.small)
                .tint(Theme.ink)
                .disabled(viewModel.isLoadingOlder)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func rowView(_ row: ChatViewModel.Row, in event: Game) -> some View {
        switch row {
        case .day(let date):
            Text(EventFormat.day(date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.accentSoft, in: .capsule)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        case .activity(let entry):
            systemRow(entry)
        case .message(let message, let showsSender):
            if message.sender.id == store.profile?.id {
                ownMessage(message.body, caption: showsSender ? Text(message.createdAt, format: .dateTime.hour().minute()) : nil)
                    .contextMenu { copyButton(message.body) }
            } else {
                theirMessage(message, showsSender: showsSender, isHost: message.sender.id == event.host.id)
            }
        case .pending(let pending):
            pendingMessage(pending)
        }
    }

    private func systemRow(_ entry: GameActivityEntry) -> some View {
        Text(verbatim: "\(text(for: entry)) · \(entry.at.formatted(date: .omitted, time: .shortened))")
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
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

    /// "Maya C. · Host · 5:42 PM" over a card-colored bubble. Touch and hold to report or block.
    private func theirMessage(_ message: ChatMessage, showsSender: Bool, isHost: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if showsSender {
                Avatar(name: message.sender.displayName, size: 28)
            } else {
                Color.clear.frame(width: 28, height: 1)
            }
            VStack(alignment: .leading, spacing: 3) {
                if showsSender {
                    HStack(spacing: 4) {
                        Text(verbatim: message.sender.displayName).fontWeight(.semibold)
                        if isHost { Text("· Host") }
                        Text(verbatim: "· \(message.createdAt.formatted(date: .omitted, time: .shortened))")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                }
                Text(verbatim: message.body)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .cardSurface(radius: Theme.Radius.field)
                    .contentShape(.contextMenuPreview, .rect(cornerRadius: Theme.Radius.field))
                    .contextMenu {
                        copyButton(message.body)
                        Button("Report message", systemImage: "exclamationmark.bubble") { reportTarget = .message(message) }
                        Button("Block \(message.sender.displayName)", systemImage: "hand.raised", role: .destructive) {
                            blockTarget = message.sender
                        }
                    }
            }
            Spacer(minLength: 40)
        }
        .padding(.top, showsSender ? 6 : 0)
        .accessibilityElement(children: .combine)
    }

    private func ownMessage(_ body: String, caption: Text?, isFaded: Bool = false) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            if let caption {
                caption.font(.caption).foregroundStyle(Theme.muted)
            }
            Text(verbatim: body)
                .font(.body)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.accent.opacity(isFaded ? 0.55 : 1), in: .rect(cornerRadius: Theme.Radius.field))
                .contentShape(.contextMenuPreview, .rect(cornerRadius: Theme.Radius.field))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 60)
        .padding(.top, caption == nil ? 0 : 6)
    }

    /// Your message on its way, or one that didn't send: "Not sent · Tap to retry".
    private func pendingMessage(_ pending: ChatViewModel.Pending) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            ownMessage(pending.body, caption: nil, isFaded: true)
            if let error = pending.error {
                Label(failureText(error), systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.error)
            } else {
                Text("Sending…").font(.caption).foregroundStyle(Theme.muted)
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
            composer
        } else if event.isGoing {
            // The server refuses messages here too (`cancelled`, `ended`).
            Text(event.isCancelled ? "This game was cancelled, so the chat is closed." : "This chat closed 24 hours after the game ended.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 12)
        }
    }

    private var composer: some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 6) {
            if let error = viewModel.draftError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.error)
                    .padding(.horizontal, 14)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerIsFocused)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    .onChange(of: viewModel.draft) {
                        if viewModel.draft.count > ChatMessage.bodyLimit {
                            viewModel.draft = String(viewModel.draft.prefix(ChatMessage.bodyLimit))
                        }
                        viewModel.draftError = nil
                    }
                Button("Send", systemImage: "arrow.up") { viewModel.send(in: store) }
                    .labelStyle(.iconOnly)
                    .fontWeight(.semibold)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .disabled(!viewModel.canSend)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}
