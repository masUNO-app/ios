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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
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

    /// What the timeline's first load ran for. A new privacy revision (every return to the app) or
    /// session starts the wait again.
    private struct LoadKey: Hashable {
        let session: UUID
        let privacyRevision: Int
        let messaging: Bool
    }
    /// The key the game, its people and its activity last finished loading for.
    @State private var loadedFor: LoadKey?
    @FocusState private var composerIsFocused: Bool

    /// How far the sport band reaches down from the top of the screen.
    private static let bandHeight: CGFloat = 175

    init(eventID: UUID) {
        self.eventID = eventID
        _viewModel = State(initialValue: ChatViewModel(gameID: eventID))
    }

    private var loadKey: LoadKey {
        LoadKey(session: store.sessionID, privacyRevision: store.privacyRevision, messaging: store.isChatEnabled)
    }

    /// Everything the timeline shows is current: the game, its activity and, with messaging on, the
    /// latest page of messages, or its failure, so being offline never leaves a spinner. Until then
    /// the timeline waits behind one loading state instead of filling in piece by piece (empty, then
    /// system rows, then messages). The privacy guards still clear and re-check everything on a new
    /// revision; this only decides when the result is shown.
    private var isTimelineReady: Bool {
        guard loadedFor == loadKey else { return false }
        guard store.isChatEnabled else { return true }
        if viewModel.hasLoaded { return true }
        if case .failed = viewModel.state { return true }
        return false
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
                RetryCard(message: "Couldn't load this plan.") { await store.loadGame(eventID) }
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
        let names = mentionNames()
        let ready = isTimelineReady

        let chat = messageList(event, rows: rows, names: names, lastJoin: lastJoin, ready: ready)
        .safeAreaInset(edge: .top, spacing: 0) {
            pinnedCard(event, state: state)
                .background(alignment: .top) { bandCover(event) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.isChatEnabled { bottomBar(event) }
        }
        .background { band(event) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { chatToolbar(event) }
        // The bar sits on the band's sport color, so its title, buttons and glass stay light in
        // dark mode, with ink on the band as everywhere else.
        .toolbarColorScheme(.light, for: .navigationBar)
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
            loadedFor = LoadKey(session: session, privacyRevision: privacy, messaging: store.isChatEnabled)
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
            // Rows arriving behind the loading state aren't news; the timeline opens at the bottom.
            guard ready else { return }
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
        // A reload (a new privacy revision, every return to the app) rebuilds the timeline from
        // nothing, so it opens like the first time: at the newest row, without animating to it, and
        // without announcing rows that were already there.
        .onChange(of: ready) { _, ready in
            if ready {
                hasShownLatest = true
            } else {
                hasShownLatest = false
                followsLatest = true
                position = ScrollPosition(edge: .bottom)
            }
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
        return debugHooks(chat)
        #else
        return chat
        #endif
    }

    /// The timeline once it's ready, and one loading state until then. The scroll view isn't there
    /// while loading, so its geometry corrections don't run against a half-built timeline.
    @ViewBuilder
    private func messageList(_ event: Game, rows: [ChatViewModel.Row], names: [UUID: String], lastJoin: UUID?,
                             ready: Bool) -> some View {
        if ready {
            timeline(event, rows: rows, names: names, lastJoin: lastJoin)
        } else {
            ProgressView()
                .accessibilityLabel(Text("Loading chat"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The conversation and how it follows the newest message. Split out of `content(_:)` so each
    /// part type-checks in reasonable time on older compilers (the iOS 18 job).
    private func timeline(_ event: Game, rows: [ChatViewModel.Row], names: [UUID: String], lastJoin: UUID?) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                if store.isChatEnabled { olderMessages }
                ForEach(rows) { row in
                    rowView(row, in: event, lastJoin: lastJoin, names: names)
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
    }

    @ToolbarContentBuilder
    private func chatToolbar(_ event: Game) -> some ToolbarContent {
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

    #if DEBUG
    /// Test and screenshot hooks.
    private func debugHooks(_ content: some View) -> some View {
        content
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
            // `-screen chat-mention`: "@" typed, so the people to mention show above the field.
            if UserDefaults.standard.string(forKey: "screen") == "chat-mention" { viewModel.draft = "@" }
            // `-chatDraft "…"`: a typed draft, for screenshots of the send button ready to send.
            if let draft = UserDefaults.standard.string(forKey: "chatDraft") { viewModel.draft = draft }
        }
    }
    #endif

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
        .shadow(color: Theme.shadowInk.opacity(0.06), radius: 6, y: 2)
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
    private func rowView(_ row: ChatViewModel.Row, in event: Game, lastJoin: UUID?, names: [UUID: String]) -> some View {
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
                ownMessage(message.body, mentions: message.mentions, names: names, color: event.activity.color,
                           time: showsSender ? message.createdAt : nil)
                    .contextMenu { copyButton(message.body) }
                    .accessibilityActions { copyButton(message.body) }
            } else {
                theirMessage(message, names: names, showsSender: showsSender, isHost: message.sender.id == event.host.id)
            }
        case .pending(let pending):
            pendingMessage(pending, names: names, color: event.activity.color)
        }
    }

    /// Display names for the mentions in this chat: the game's people and you.
    private func mentionNames() -> [UUID: String] {
        var names = Dictionary(store.attendees(of: eventID).map { ($0.id, $0.person.displayName) },
                               uniquingKeysWith: { first, _ in first })
        if let me = store.profile?.summary { names[me.id] = me.displayName }
        return names
    }

    /// A message's text with its mentions in bold; a mention of you also in the accent color.
    /// VoiceOver reads the plain text from the bubble's label.
    private func messageText(_ body: String, mentions: [UUID], names: [UUID: String]) -> Text {
        guard !mentions.isEmpty else { return Text(verbatim: body) }
        var text = AttributedString()
        var cursor = body.startIndex
        for match in Mention.ranges(in: body, mentions: mentions, names: names, me: store.profile?.id) {
            text += AttributedString(String(body[cursor..<match.range.lowerBound]))
            var name = AttributedString(String(body[match.range]))
            name.font = .rounded(.callout, .bold)
            if match.isMe { name.foregroundColor = Theme.accentText }
            text += name
            cursor = match.range.upperBound
        }
        text += AttributedString(String(body[cursor...]))
        return Text(text)
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

    /// Your own rows get their own sentences ("You took a spot"), not "You" in the third-person one:
    /// Spanish conjugates the verb ("Te apuntaste", not "Tú se apuntó").
    private func isMine(_ entry: GameActivityEntry) -> Bool {
        entry.actor != nil && entry.actor?.id == store.profile?.id
    }

    private func name(of entry: GameActivityEntry) -> String {
        if isMine(entry) { return String.app("You") }
        return entry.actor?.firstName ?? String.app("Someone")
    }

    /// "+1 Emilio took a spot · room for 3 more", or "took the last spot · game is full".
    private func joinPill(_ entry: GameActivityEntry, in event: Game) -> some View {
        let name = name(of: entry)
        let mine = isMine(entry)
        let text: String = if event.isFull {
            mine ? String.app("You took the last spot · it's full") : String.app("\(name) took the last spot · it's full")
        } else {
            mine ? String.app("You took a spot · \(event.roomPhrase)") : String.app("\(name) took a spot · \(event.roomPhrase)")
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
                .inkOnColor()
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
        let mine = isMine(entry)
        let time = EventFormat.time(entry.at)
        return switch entry.kind {
        case .created: mine ? String.app("You created the chat") : String.app("\(name) created the chat")
        case .joined: mine ? String.app("You took a spot") : String.app("\(name) took a spot")
        case .left: mine ? String.app("You left · a spot opened") : String.app("\(name) left · a spot opened")
        case .meetPointUpdated: String.app("Meet-up spot updated · \(time)")
        case .timeOrPlaceChanged: String.app("Time or place changed · \(time)")
        case .cancelled: String.app("Plan cancelled · Chat closed")
        }
    }

    /// "Maya C. · Host · 5:42 PM" over a white bubble. Touch and hold to report or block; with
    /// VoiceOver, one stop that names the sender on every bubble, with the same choices as actions.
    private func theirMessage(_ message: ChatMessage, names: [UUID: String], showsSender: Bool, isHost: Bool) -> some View {
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
                messageText(message.body, mentions: message.mentions, names: names)
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

    /// Your bubble, in the sport's color with ink text; the time, if any, sits under it. Mentions are
    /// bold in ink, which is what reads on the sport color.
    private func ownMessage(
        _ body: String, mentions: [UUID], names: [UUID: String], color: Color, time: Date?, isFaded: Bool = false
    ) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            messageText(body, mentions: mentions, names: names)
                .font(.rounded(.callout))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(color.opacity(isFaded ? 0.5 : 1), in: .rect(cornerRadius: 20))
                // Faded over the light page even in dark mode, so the ink on it still reads.
                .background { if isFaded { RoundedRectangle(cornerRadius: 20).fill(Theme.surface2) } }
                .inkOnColor()
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
    private func pendingMessage(_ pending: ChatViewModel.Pending, names: [UUID: String], color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            ownMessage(pending.body, mentions: pending.mentions, names: names, color: color, time: nil, isFaded: true)
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
            Text(event.isCancelled ? "This plan was cancelled, so the chat is closed." : "This chat closed 24 hours after the plan wrapped.")
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
        let suggestions = viewModel.mentionSuggestions(in: store)

        return VStack(alignment: .leading, spacing: 6) {
            if !suggestions.isEmpty { mentionList(suggestions) }
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
                        viewModel.draftDidChange()
                    }
                Button("Send", systemImage: "arrow.up") {
                    viewModel.send(in: store)
                    // Refused before it left; the reason shows above the field, out of focus.
                    if let error = viewModel.draftError { Announce.post(error, priority: .high) }
                }
                    .labelStyle(.iconOnly)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.ink)
                    // The exact sport color in dark mode too, as on the band and the bubbles.
                    .appProminentCircle(tint: event.activity.color, solid: colorScheme == .dark)
                    .inkOnColor()
                    // Stays in the sport's color; an empty draft just doesn't send.
                    .opacity(viewModel.canSend ? 1 : 0.75)
                    // Faded over the light tray in dark mode too, so the ink arrow still shows.
                    .background { Circle().fill(Theme.surface2).inkOnColor() }
                    .accessibilityHint(viewModel.canSend ? Text(verbatim: "") : Text("Type a message first"))
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .foldColumn()
        // Solid, so messages don't show through under the field.
        .background(Theme.surface2)
        // The list shows up above the field without taking focus, so say it's there.
        .onChange(of: suggestions.isEmpty) { _, isEmpty in
            if !isEmpty { Announce.post(String.app("People to mention are above the message field")) }
        }
    }

    /// After "@" in the composer: the people you can mention, filtered as you type their first name.
    /// Picking one writes "@Maya C. " into the message.
    private func mentionList(_ people: [PersonSummary]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fewer rows at accessibility sizes, so the list doesn't cover the conversation.
            ForEach(people.prefix(typeSize.isAccessibilitySize ? 3 : 5)) { person in
                Button {
                    viewModel.mention(person)
                    composerIsFocused = true
                } label: {
                    HStack(spacing: 10) {
                        PersonAvatar(person: person, size: 28)
                            .accessibilityHidden(true)
                        Text(verbatim: person.displayName)
                            .font(.rounded(.body, .bold))
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: person.displayName))
                .accessibilityHint(Text("Adds them to your message"))
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.separator))
        .shadow(color: Theme.shadowInk.opacity(0.06), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("People to mention"))
        .accessibilityIdentifier("chat-mention-suggestions")
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
