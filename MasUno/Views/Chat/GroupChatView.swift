import SwiftUI

/// Figma: "Group chat" (341:1791 and one per sport; SPEC §7.6.9, §7.7.3, Appendix A). A band in
/// the sport's color with faint court lines, the pinned card, system rows from `game_activity`
/// (joins as a "+1" pill) and, when `chat_enabled` is on, messages and a composer (E26): theirs
/// on white, yours in the sport's color. With it off, this is the read-only hub (N14).
struct GroupChatView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let eventID: UUID

    @State private var viewModel: ChatViewModel
    @State private var showsWhoIsGoing = false
    @State private var editsMeetUp = false
    @State private var reportTarget: ReportSubject?
    @State private var blockTarget: PersonSummary?
    @State private var position = ScrollPosition(edge: .bottom)
    /// The first page is on screen, so from here a new row is news worth animating to.
    @State private var hasShownLatest = false
    @State private var loadedEmpty = false
    @State private var followsLatest = true
    @State private var isUserScrolling = false

    private static let bottomID = "chat-bottom"

    private struct ScrollMetrics: Equatable {
        let nearBottom: Bool
        let viewportHeight: CGFloat
        let contentHeight: CGFloat

        init(_ geometry: ScrollGeometry) {
            nearBottom = geometry.visibleRect.maxY >= geometry.contentSize.height - 80
            viewportHeight = geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
            contentHeight = geometry.contentSize.height
        }
    }

    private struct Lifecycle: Hashable {
        let active: Bool
        let messaging: Bool
        let session: UUID
        let privacyRevision: Int
    }
    @FocusState private var composerIsFocused: Bool

    /// How far the sport band reaches down from the top of the screen.
    private static let bandHeight: CGFloat = 175

    init(eventID: UUID) {
        self.eventID = eventID
        _viewModel = State(initialValue: ChatViewModel(gameID: eventID))
    }

    var body: some View {
        // Read once: each lookup filters against blocked people.
        let event = store.game(eventID)
        return Group {
            if let event, event.isGoing, !store.isGuest {
                content(event)
            } else if event == nil, !store.isMissing(eventID), !store.isOffline {
                ProgressView()
                    .accessibilityLabel(Text("Loading chat"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            } else if event == nil, store.isOffline {
                RetryCard(message: "Couldn't load this game.") { await store.loadGame(eventID) }
                    .padding(.horizontal, Theme.gutter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            } else {
                ContentUnavailableView("This chat isn't available.", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
        }
        // Cached navigation can outlive membership. Clear the model even when its content
        // has disappeared, and fence old network responses before they can restore messages.
        .onChange(of: store.privacyRevision, initial: true) { _, _ in viewModel.synchronize(in: store) }
        .onChange(of: event?.isGoing) { _, _ in viewModel.synchronize(in: store) }
        .task(id: eventID) {
            // A notification can open a chat that is absent from the cached lists.
            // Do not depend on the detail screen underneath becoming visible first.
            if store.game(eventID) == nil { await store.loadGame(eventID) }
        }
    }

    private func content(_ event: Game) -> some View {
        let state = event.status()
        let activity = store.activity(of: eventID)
        let rows = store.isChatEnabled ? viewModel.rows(in: store, activity: activity) : activity.map(ChatViewModel.Row.activity)
        let lastJoin = Self.latestJoin(in: activity)
        let newest = Self.newestMessage(in: rows)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                if store.isChatEnabled { olderMessages }
                ForEach(rows) { row in
                    rowView(row, in: event, lastJoin: lastJoin)
                }
                Color.clear.frame(height: 1).id(Self.bottomID)
            }
            .scrollTargetLayout()
            .padding(.horizontal, 19)
            .padding(.vertical, 12)
            .foldColumn()
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(followsLatest ? .bottom : nil, for: .sizeChanges)
        .onScrollPhaseChange { _, phase in
            isUserScrolling = phase == .interacting || phase == .decelerating
        }
        .onScrollGeometryChange(for: ScrollMetrics.self) { ScrollMetrics($0) } action: { old, new in
            // Keyboard/composer resizing is not a gesture away from the conversation.
            if isUserScrolling {
                followsLatest = new.nearBottom
            } else if followsLatest,
                      old.viewportHeight != new.viewportHeight || old.contentHeight != new.contentHeight {
                position.scrollTo(id: Self.bottomID, anchor: .bottom)
            }
        }
        .onChange(of: composerIsFocused) { _, focused in
            if focused, followsLatest { position.scrollTo(id: Self.bottomID, anchor: .bottom) }
        }
        .onChange(of: viewModel.pending) { old, new in
            if let error = ChatViewModel.newFailure(from: old, to: new) {
                Announce.post(ChatViewModel.failureText(error), priority: .high)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            pinnedCard(event, state: state)
                .background(alignment: .top) { bandCover(event) }
        }
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
                    Text(verbatim: "\(event.activity.emoji) \(event.activity.name) · \(String.app("\(event.goingCount) going"))")
                        .font(.rounded(.caption))
                }
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                // One stop, without the emoji next to the sport's name (A11Y-11).
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(event.title), \(event.activity.name), \(String.app("\(event.goingCount) going"))"))
                // The bar keeps its text small; a long press shows the title big (A11Y-24).
                .accessibilityShowsLargeContentViewer { Text(verbatim: event.title) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(event.chatMuted ? "Unmute chat" : "Mute chat", systemImage: event.chatMuted ? "bell.slash" : "bell") {
                    Task { await store.setChatMuted(event.id, muted: !event.chatMuted) }
                }
                .labelStyle(.iconOnly)
                .tint(.black)
            }
            .appSharedBackgroundVisibility(.visible)
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
                .accessibilityShowsLargeContentViewer { Label("Who's going", systemImage: "person.2") }
            }
            .appSharedBackgroundVisibility(.hidden)
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
        .refreshable { await load(includeMessages: true) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                AppGroupStore.openChatID = eventID.uuidString
                PushNotificationService.clearDelivered(thread: "chat:\(eventID.uuidString)")
            } else if AppGroupStore.openChatID == eventID.uuidString {
                AppGroupStore.openChatID = nil
            }
        }
        .onDisappear {
            if AppGroupStore.openChatID == eventID.uuidString { AppGroupStore.openChatID = nil }
        }
        .task(id: Lifecycle(active: scenePhase == .active, messaging: store.isChatEnabled, session: store.sessionID, privacyRevision: store.privacyRevision)) {
            guard scenePhase == .active else { return }
            let session = store.sessionID
            let privacy = store.privacyRevision
            await load(includeMessages: false)
            guard !Task.isCancelled, store.sessionID == session, store.privacyRevision == privacy else { return }
            guard let current = store.game(eventID), current.isGoing else { return }
            if store.isChatEnabled, current.isChatOpen(), let profile = store.profile, profile.chatRulesAcceptedAt == nil {
                viewModel.asksForRules = true
            }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await viewModel.open(in: store) }
                group.addTask { await viewModel.poll(in: store) }
            }
        }
        // Follow the conversation: a new last row scrolls into view; loading older pages doesn't.
        // While the chat is still loading, land on the newest message without a visible scroll.
        .onChange(of: rows.last?.id) {
            let sentHere: Bool = if case .pending = rows.last { true } else { false }
            if sentHere { followsLatest = true }
            if hasShownLatest {
                // A jump under Reduce Motion (A11Y-18).
                if followsLatest { withAnimation(reduceMotion ? nil : .default) { position.scrollTo(id: Self.bottomID, anchor: .bottom) } }
            } else {
                position.scrollTo(id: Self.bottomID, anchor: .bottom)
            }
            if !store.isChatEnabled || viewModel.state == .loaded { hasShownLatest = true }
        }
        // An empty chat has no newest message to compare with, so remember that it loaded empty.
        .onChange(of: viewModel.state) {
            if viewModel.state == .loaded { loadedEmpty = newest == nil }
        }
        .onChange(of: newest) { old, new in
            defer { if new != nil { loadedEmpty = false } }
            guard let new, Self.announces(new, after: old, shownLatest: hasShownLatest,
                                          loadedEmpty: loadedEmpty, myID: store.profile?.id) else { return }
            Announce.post(String.app("\(new.sender.displayName): \(new.body)"))
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            // Toolbar items don't expose an accessibility value on iOS 27, so the UI tests read the
            // newest message from here.
            if UserDefaults.standard.bool(forKey: "chatScrollUITest") {
                Color.clear
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityIdentifier("chat-test-latest")
                    .accessibilityValue(Text(verbatim: viewModel.messages.last?.body ?? ""))
            }
        }
        .toolbar {
            if UserDefaults.standard.bool(forKey: "chatScrollUITest"), let backend = store.chat as? MockBackend {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String("Receive test message"), systemImage: "arrow.down.message") {
                        backend.now += 1
                        backend.receiveMessage(from: MockFixtures.sam, in: eventID, body: "New live message")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("chat-test-receive")
                }
            }
        }
        .onAppear {
            if UserDefaults.standard.string(forKey: "screen") == "meetup" { editsMeetUp = true }
        }
        #endif
    }

    private func load(includeMessages: Bool) async {
        let session = store.sessionID
        let privacy = store.privacyRevision
        await store.loadGame(eventID)
        guard !Task.isCancelled, store.sessionID == session, store.privacyRevision == privacy,
              store.game(eventID)?.isGoing == true else {
            viewModel.synchronize(in: store)
            return
        }
        async let attendees: Void = store.loadAttendees(eventID)
        async let activity: Void = store.loadActivity(eventID)
        if includeMessages, store.isChatEnabled { await viewModel.reload(in: store) }
        _ = await (attendees, activity)
    }

    // MARK: Band and pinned card

    /// The sport's color across the top, with the top of its court drawn faintly, over the page.
    private func band(_ event: Game) -> some View {
        VStack(spacing: 0) {
            bandArt(event)
            Theme.surface2
        }
        .ignoresSafeArea()
    }

    /// The band again, in front of the messages, from the top edge to the bottom of the pinned
    /// card. With the navigation bar in the side bar, nothing else covers the strip above the
    /// card, so messages scrolled up would show through it. Drawn in the same space as `band`, so
    /// the two line up exactly.
    private func bandCover(_ event: Game) -> some View {
        bandArt(event)
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
            .ignoresSafeArea()
    }

    private func bandArt(_ event: Game) -> some View {
        event.activity.color
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    // Stops growing at the court headers' width, so a wide screen doesn't blow
                    // the net line up across the band. The art centers itself in the width.
                    CourtArt(kind: event.activity.court, scale: min(geo.size.width, CourtHeader.maxWidth) / CourtArt.designWidth * 1.05)
                        .frame(height: 400)
                        .offset(y: -44)
                        .opacity(0.45)
                }
            }
            .frame(height: Self.bandHeight)
            .clipped()
    }

    private func pinnedCard(_ event: Game, state: GameStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(verbatim: EventFormat.dayAndTime(event.startsAt))
            } icon: {
                Image(systemName: "calendar").accessibilityHidden(true)
            }
            Label {
                Text(verbatim: event.place.name)
            } icon: {
                PlaceIcon(size: 16)
            }
            HStack(alignment: .center) {
                Label {
                    Text(event.meetPoint ?? String.app("No meet-up spot yet"))
                        .fontWeight(.bold)
                } icon: {
                    Image(systemName: "flag").accessibilityHidden(true)
                }
                Spacer(minLength: 8)
                if state == .hosting {
                    Button("Edit") { editsMeetUp = true }
                        .pill(.secondary, expands: false, size: .small)
                        .accessibilityLabel(Text("Edit meet-up spot"))
                        .accessibilityInputLabels([Text("Edit")])
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
        .foldColumn()
    }

    // MARK: Timeline

    @ViewBuilder
    private var olderMessages: some View {
        if case .failed = viewModel.state {
            RetryCard(message: "Couldn't load messages.") { await viewModel.reload(in: store) }
        } else if viewModel.refreshError != nil {
            RetryCard(message: "Couldn't refresh messages.") { await viewModel.reload(in: store) }
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
                .accessibilityAddTraits(.isHeader)
        case .activity(let entry):
            // One pill, for the newest join: a long run of them would bury the conversation.
            if entry.id == lastJoin {
                joinPill(entry, in: event)
            } else {
                systemRow(entry)
            }
        case .message(let message, let showsSender):
            if message.sender.id == store.profile?.id {
                ownMessage(message.body, color: event.activity.color, time: showsSender ? message.createdAt : nil)
                    .contextMenu { copyButton(message.body) }
                    .accessibilityActions { copyButton(message.body) }
            } else {
                theirMessage(message, showsSender: showsSender, isHost: message.sender.id == event.host.id)
            }
        case .pending(let pending):
            pendingMessage(pending, color: event.activity.color)
        }
    }

    /// Whether VoiceOver reads out a new newest message: what others write once the chat is open,
    /// including the first message into a chat that loaded empty. Not the first page, your own
    /// sends, or an older message coming back to the end after someone is blocked.
    static func announces(_ new: ChatMessage, after old: ChatMessage?, shownLatest: Bool,
                          loadedEmpty: Bool, myID: UUID?) -> Bool {
        guard new.sender.id != myID else { return false }
        guard let old else { return loadedEmpty }
        return shownLatest && new.createdAt > old.createdAt
    }

    /// The newest message on screen, from anyone.
    private static func newestMessage(in rows: [ChatViewModel.Row]) -> ChatMessage? {
        for row in rows.reversed() {
            if case .message(let message, _) = row { return message }
        }
        return nil
    }

    /// The newest join, if nobody has left since: only that one can say how much room is left now.
    private static func latestJoin(in activity: [GameActivityEntry]) -> UUID? {
        guard let last = activity.last(where: { $0.kind == .joined || $0.kind == .left }), last.kind == .joined else { return nil }
        return last.id
    }

    private func name(of entry: GameActivityEntry) -> String {
        if entry.actor?.id == store.profile?.id { return String.app("You") }
        return entry.actor?.firstName ?? String.app("Someone")
    }

    /// "+1 Emilio took a spot · room for 3 more", or "took the last spot · game is full".
    private func joinPill(_ entry: GameActivityEntry, in event: Game) -> some View {
        let name = name(of: entry)
        let text: String = if event.isFull {
            String.app("\(name) took the last spot · game is full")
        } else {
            String.app("\(name) took a spot · \(event.roomPhrase)")
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
        // One element over the whole pill, so the "+1" isn't text outside any element.
        .accessibilityElement(children: .combine)
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
        let time = EventFormat.time(entry.at)
        return switch entry.kind {
        case .created: String.app("\(name) created the chat")
        case .joined: String.app("\(name) took a spot")
        case .left: String.app("\(name) left · a spot opened")
        case .meetPointUpdated: String.app("Meet-up spot updated · \(time)")
        case .timeOrPlaceChanged: String.app("Time or place changed · \(time)")
        case .cancelled: String.app("Game cancelled · Chat closed")
        }
    }

    /// "Maya C. · Host · 5:42 PM" over a white bubble. Touch and hold to report or block; with
    /// VoiceOver, one stop that names the sender on every bubble, with the same choices as actions.
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
                        Text(verbatim: "· \(EventFormat.time(message.createdAt))")
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
                    .contextMenu { messageActions(message) }
            }
            Spacer(minLength: 40)
        }
        .padding(.top, showsSender ? 4 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: isHost
            ? String.app("\(message.sender.displayName), host: \(message.body)")
            : String.app("\(message.sender.displayName): \(message.body)")))
        .accessibilityValue(Text(verbatim: EventFormat.time(message.createdAt)))
        .accessibilityAddTraits(.isStaticText)
        .accessibilityActions { messageActions(message) }
    }

    @ViewBuilder
    private func messageActions(_ message: ChatMessage) -> some View {
        copyButton(message.body)
        Button("Report message", systemImage: "exclamationmark.bubble") { reportTarget = .message(message) }
        Button("Block \(message.sender.displayName)", systemImage: "nosign", role: .destructive) {
            blockTarget = message.sender
        }
    }

    /// Your bubble, in the sport's color with ink text; the time, if any, sits under it.
    private func ownMessage(_ body: String, color: Color, time: Date?, isFaded: Bool = false) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(verbatim: body)
                .font(.rounded(.callout))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(color.opacity(isFaded ? 0.5 : 1), in: .rect(cornerRadius: 20))
                .contentShape(.contextMenuPreview, .rect(cornerRadius: 20))
            if let time {
                Text(time, format: .dateTime.hour().minute())
                    .font(.rounded(.caption))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 60)
        .padding(.top, time == nil ? 0 : 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: String.app("You: \(body)")))
        .accessibilityValue(Text(verbatim: time.map(EventFormat.time) ?? ""))
        .accessibilityAddTraits(.isStaticText)
    }

    /// Your message on its way, or one that didn't send: "Not sent · Tap to retry".
    private func pendingMessage(_ pending: ChatViewModel.Pending, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            ownMessage(pending.body, color: color, time: nil, isFaded: true)
            if let error = pending.error {
                Label(ChatViewModel.failureText(error), systemImage: "exclamationmark.circle.fill")
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
        // Retries without relying on a simulated tap (A11Y-20).
        .accessibilityAction { viewModel.retry(pending.id, in: store) }
        .accessibilityActions {
            if pending.error != nil {
                Button("Delete") { viewModel.discard(pending.id) }
            }
        }
    }

    private func copyButton(_ text: String) -> some View {
        Button("Copy", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = text
            Announce.post(String.app("Copied"))
        }
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
                .foldColumn(maxWidth: .infinity)
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
                    .accessibilityIdentifier("chat-composer")
                    .lineLimit(1...5)
                    .font(.rounded(.body))
                    .focused($composerIsFocused)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .appGlass(in: .rect(cornerRadius: 23))
                    .onChange(of: viewModel.draft) {
                        if viewModel.draft.count > ChatMessage.bodyLimit {
                            viewModel.draft = String(viewModel.draft.prefix(ChatMessage.bodyLimit))
                        }
                        viewModel.draftError = nil
                    }
                Button("Send", systemImage: "arrow.up") {
                    viewModel.send(in: store)
                    // Refused before it left; the reason shows above the field, out of focus.
                    if let error = viewModel.draftError { Announce.post(error, priority: .high) }
                }
                    .labelStyle(.iconOnly)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.ink)
                    .appProminentCircle(tint: event.activity.color)
                    // Stays in the sport's color; an empty draft just doesn't send.
                    .opacity(viewModel.canSend ? 1 : 0.75)
                    .accessibilityHint(viewModel.canSend ? Text(verbatim: "") : Text("Type a message first"))
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .foldColumn()
        // Solid, so messages don't show through under the field.
        .background(Theme.surface2)
    }
}

private extension View {
    /// `readableColumn()`, moved to one side when the Duo is partially open, so no bubble, card
    /// or field runs through the crease. Flat screens get exactly `readableColumn()`.
    func foldColumn(maxWidth: CGFloat = Theme.columnWidth) -> some View {
        modifier(FoldColumn(maxWidth: maxWidth))
    }
}

private struct FoldColumn: ViewModifier {
    var maxWidth: CGFloat
    /// The larger side of the fold, across this view's own width. Nil when the screen is flat.
    @State private var pane: ClosedRange<CGFloat>?

    func body(content: Content) -> some View {
        // The same chain either way, so a fold coming or going doesn't reset the composer's focus.
        content
            .frame(maxWidth: maxWidth)
            .frame(width: pane.map { $0.upperBound - $0.lowerBound })
            .padding(.leading, pane?.lowerBound ?? 0)
            .frame(maxWidth: .infinity, alignment: pane == nil ? .center : .leading)
            .onGeometryChange(for: ClosedRange<CGFloat>?.self) { proxy in
                guard let fold = proxy.activeFold else { return nil }
                let side = CGRect(origin: .zero, size: proxy.size).pane(avoiding: fold)
                // A crease running side to side leaves the full width: nothing to move.
                return side.width < proxy.size.width ? side.minX...side.maxX : nil
            } action: { pane = $0 }
    }
}
