import Foundation
import Observation

/// One game's chat timeline (SPEC §7.6.9, Appendix A item 5, E26): the latest page of messages, then
/// live; older pages on request; sends that show right away and can be retried.
@Observable
final class ChatViewModel {
    /// A message of yours the server hasn't confirmed. `id` is its client ID.
    struct Pending: Identifiable, Hashable {
        let id: UUID
        var body: String
        var sentAt: Date
        /// Set when the send failed; nil while it's on its way.
        var error: DomainError?
    }

    enum Row: Identifiable, Hashable {
        case day(Date)
        case message(ChatMessage, showsSender: Bool)
        case activity(GameActivityEntry)
        case pending(Pending)

        var id: String {
            switch self {
            case .day(let date): "day-\(date.timeIntervalSinceReferenceDate)"
            case .message(let message, _): message.id.uuidString
            case .activity(let entry): entry.id.uuidString
            case .pending(let pending): pending.id.uuidString
            }
        }
    }

    static let pageSize = 50
    /// How often an open chat checks for new messages, in case the live channel is down.
    static let pollInterval: Duration = .seconds(15)
    static let healthyPollInterval: Duration = .seconds(60)
    /// Messages from the same person this close together share one name line.
    private static let runGap: TimeInterval = 5 * 60

    let gameID: UUID
    private(set) var messages: [ChatMessage] = []
    private(set) var pending: [Pending] = []
    private(set) var state = GameStore.LoadState.idle
    /// There are messages before the oldest one loaded.
    private(set) var hasOlder = false
    private(set) var isLoadingOlder = false
    /// A refresh can fail without invalidating a successfully loaded empty conversation.
    private(set) var refreshError: DomainError?
    private(set) var isConnected = false
    private(set) var hasLoaded = false
    var draft = ""
    /// Shown above the composer when the text filter refuses a draft.
    var draftError: String?
    /// "Before you chat" needs an answer.
    var asksForRules = false

    /// Privacy invalidation is independent of account changes: incoming blocks are not exposed
    /// as IDs, so a new revision must discard every cached page and ask the server again.
    private struct Context: Equatable {
        let sessionID: UUID
        let generation: UUID
        let privacyRevision: Int
        let isMember: Bool
    }
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var context: Context?
    @ObservationIgnored private var authorizedContext: Context?
    @ObservationIgnored private var opening = UUID()
    @ObservationIgnored private var latestRead: ReadFlight?
    @ObservationIgnored private var incrementalRead: ReadFlight?
    @ObservationIgnored private var updateRefresh: Task<Void, Never>?
    @ObservationIgnored private var needsMessages = false
    @ObservationIgnored private var needsActivity = false
    @ObservationIgnored private var sendTasks: [UUID: (id: UUID, task: Task<ChatMessage, any Error>)] = [:]

    /// Each waiter owns its cancellation. Only the last departing waiter cancels the shared read.
    private final class ReadFlight {
        let id = UUID()
        let session: Context
        let task: Task<[ChatMessage], any Error>
        let reads = SharedReadPool<Int, [ChatMessage]>(resource: "chat")
        var waiters: Set<UUID> = []
        var published = false

        init(session: Context, fetch: @escaping @MainActor () async throws -> [ChatMessage]) {
            self.session = session
            task = Task { try await fetch() }
        }
    }

    init(gameID: UUID) {
        self.gameID = gameID
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Timeline

    /// Messages and system rows in time order with a row for each new day, then unsent messages.
    /// People you blocked are left out, including ones blocked a moment ago.
    func rows(in store: GameStore, calendar: Calendar = .current) -> [Row] {
        guard hasAccess(in: store), context == nil || context == currentContext(in: store) else { return [] }
        let visible = messages.filter { !store.isBlocked($0.sender.id) }
        var activity = store.activity(of: gameID)
        // Until the older pages are loaded, system rows from before them would bunch up at the top.
        if hasOlder, let oldest = visible.first?.createdAt { activity.removeAll { $0.at < oldest } }

        var timeline = visible.map { (date: $0.createdAt, row: Row.message($0, showsSender: true)) }
            + activity.map { (date: $0.at, row: Row.activity($0)) }
        timeline.sort { $0.date < $1.date }
        timeline += pending.map { (date: $0.sentAt, row: Row.pending($0)) }

        var rows: [Row] = []
        var lastDay: Date?
        var previous: ChatMessage?
        for (date, row) in timeline {
            let day = calendar.startOfDay(for: date)
            if day != lastDay {
                rows.append(.day(day))
                lastDay = day
                previous = nil
            }
            if case .message(let message, _) = row {
                let continuesRun = previous.map {
                    $0.sender.id == message.sender.id && message.createdAt.timeIntervalSince($0.createdAt) < Self.runGap
                } ?? false
                rows.append(.message(message, showsSender: !continuesRun))
                previous = message
            } else {
                rows.append(row)
                previous = nil
            }
        }
        return rows
    }

    // MARK: Loading

    /// The scene owns this task. A failed or ended subscription reconnects, with reconciliation
    /// after each connection gap. The same activity channel also keeps the read-only hub current.
    func open(in store: GameStore) async {
        prepare(in: store)
        let session = currentContext(in: store)
        guard await authorize(session, in: store) else { return }
        let operation = UUID()
        opening = operation
        defer {
            if opening == operation {
                isConnected = false
                updateRefresh?.cancel()
                updateRefresh = nil
                needsMessages = false
                needsActivity = false
            }
        }
        if store.isChatEnabled {
            if hasLoaded { await fetchNew(in: store) } else { await reload(in: store) }
        }
        var failures = 0
        while !Task.isCancelled, isCurrent(session, in: store), opening == operation {
            isConnected = false
            for await update in store.chat.updates(gameID: gameID) {
                guard !Task.isCancelled, isCurrent(session, in: store), opening == operation else { return }
                switch update {
                case .connected:
                    isConnected = true
                    failures = 0
                    if store.isChatEnabled { await fetchNew(in: store) }
                    await store.loadActivity(gameID)
                case .disconnected:
                    isConnected = false
                case .message:
                    enqueueUpdate(activity: false, in: store, session: session, operation: operation)
                case .activity:
                    enqueueUpdate(activity: true, in: store, session: session, operation: operation)
                }
            }
            isConnected = false
            guard !Task.isCancelled, isCurrent(session, in: store), opening == operation else { return }
            let delays: [Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(30)]
            let delay = delays[min(failures, delays.count - 1)]
            failures += 1
            do { try await Task.sleep(for: delay) } catch { return }
            if store.isChatEnabled { await fetchNew(in: store) }
            await store.loadActivity(gameID)
        }
    }

    /// Consume a burst while its reads run, retaining a follow-up invalidation rather than
    /// fetching once per buffered broadcast. Neither message nor activity demand can be lost.
    private func enqueueUpdate(activity: Bool, in store: GameStore, session: Context, operation: UUID) {
        needsMessages = needsMessages || !activity
        needsActivity = needsActivity || activity
        guard updateRefresh == nil else { return }
        updateRefresh = Task { [weak self] in
            guard let self else { return }
            defer { if opening == operation { updateRefresh = nil } }
            while !Task.isCancelled, isCurrent(session, in: store), opening == operation,
                  needsMessages || needsActivity {
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                let messages = needsMessages
                let activity = needsActivity
                needsMessages = false
                needsActivity = false
                if messages, store.isChatEnabled { await fetchNew(in: store) }
                if activity {
                    async let rows: Void = store.loadActivity(gameID)
                    async let attendees: Void = store.loadAttendees(gameID)
                    async let game: Void = store.loadGame(gameID)
                    _ = await (rows, attendees, game)
                }
            }
        }
    }

    /// A slow healthy reconciliation, or a faster fallback when the live channel is unavailable.
    /// Scene gating in GroupChatView cancels this while inactive.
    func poll(in store: GameStore, every interval: Duration = pollInterval) async {
        prepare(in: store)
        let session = currentContext(in: store)
        guard await authorize(session, in: store) else { return }
        while !Task.isCancelled, isCurrent(session, in: store) {
            do { try await Task.sleep(for: isConnected ? max(interval, Self.healthyPollInterval) : interval) }
            catch { return }
            guard !Task.isCancelled, isCurrent(session, in: store) else { return }
            if store.isChatEnabled { await fetchNew(in: store) }
            await store.loadActivity(gameID)
        }
    }

    func reload(in store: GameStore) async {
        guard !Task.isCancelled else { return }
        prepare(in: store)
        let session = currentContext(in: store)
        guard await authorize(session, in: store) else { return }
        let flight: ReadFlight
        if let existing = latestRead, existing.session == session {
            flight = existing
        } else {
            if !hasLoaded { state = .loading }
            refreshError = nil
            let repository = store.chat
            flight = ReadFlight(session: session) { [gameID] in
                try await repository.fetchMessages(gameID: gameID, before: nil, limit: Self.pageSize)
            }
            latestRead = flight
        }
        let waiter = UUID()
        flight.waiters.insert(waiter)
        defer { release(waiter, from: flight) }
        let result = await wait(for: flight, waiter: waiter)
        guard !Task.isCancelled, isCurrent(session, in: store), latestRead?.id == flight.id, !flight.published else { return }
        flight.published = true
        switch result {
        case .success(let page):
            // Refreshing the newest page does not discard knowledge about older pages already read.
            let hadEarlier = messages.first.map { first in page.first.map { first.createdAt < $0.createdAt } ?? false } ?? false
            merge(page)
            if !hadEarlier { hasOlder = page.count == Self.pageSize }
            hasLoaded = true
            state = .loaded
            refreshError = nil
            store.succeeded("chat:\(gameID)")
            await store.markChatRead(gameID)
        case .failure(let error):
            if OperationCancellation.isCancellation(error) {
                state = hasLoaded ? .loaded : .idle
                return
            }
            let domain = store.domainError(error)
            store.noteFailure(domain, resource: "chat:\(gameID)")
            if hasLoaded {
                state = .loaded
                refreshError = domain
            } else {
                state = .failed(domain)
            }
        }
    }

    /// Everything since the newest message, with overlap for delayed arrivals. Equivalent reads
    /// share a task; the repository pages catch-up results beyond the server's response cap.
    func fetchNew(in store: GameStore) async {
        guard !Task.isCancelled else { return }
        prepare(in: store)
        guard hasLoaded, let newest = messages.last?.createdAt else { return await reload(in: store) }
        let session = currentContext(in: store)
        guard await authorize(session, in: store) else { return }
        let flight: ReadFlight
        if let existing = incrementalRead, existing.session == session {
            flight = existing
        } else {
            let repository = store.chat
            flight = ReadFlight(session: session) { [gameID] in
                try await repository.fetchMessages(gameID: gameID, since: newest.addingTimeInterval(-5))
            }
            incrementalRead = flight
        }
        let waiter = UUID()
        flight.waiters.insert(waiter)
        defer { release(waiter, from: flight) }
        let result = await wait(for: flight, waiter: waiter)
        guard !Task.isCancelled, isCurrent(session, in: store), incrementalRead?.id == flight.id, !flight.published else { return }
        flight.published = true
        switch result {
        case .success(let fresh):
            let known = Set(messages.map(\.id))
            merge(fresh)
            store.succeeded("chat:\(gameID)")
            if fresh.contains(where: { !known.contains($0.id) }) { await store.markChatRead(gameID) }
        case .failure(let error):
            if !OperationCancellation.isCancellation(error) { store.noteFailure(store.domainError(error), resource: "chat:\(gameID)") }
        }
    }

    func loadOlder(in store: GameStore) async {
        guard !Task.isCancelled else { return }
        prepare(in: store)
        guard hasOlder, !isLoadingOlder, let oldest = messages.first else { return }
        let session = currentContext(in: store)
        guard await authorize(session, in: store) else { return }
        isLoadingOlder = true
        defer { if isCurrent(session, in: store) { isLoadingOlder = false } }
        do {
            let page = try await store.chat.fetchMessages(gameID: gameID, before: ChatMessageCursor(oldest), limit: Self.pageSize)
            guard !Task.isCancelled, isCurrent(session, in: store) else { return }
            hasOlder = page.count == Self.pageSize
            merge(page)
        } catch {
            if isCurrent(session, in: store), !OperationCancellation.isCancellation(error) { store.noteFailure(store.domainError(error), resource: "chat:\(gameID)") }
        }
    }

    /// Called when a cached screen loses access, even if it no longer renders the timeline.
    func synchronize(in store: GameStore) {
        prepare(in: store)
    }

    private func currentContext(in store: GameStore) -> Context {
        Context(sessionID: store.sessionID, generation: generation, privacyRevision: store.privacyRevision,
                isMember: hasAccess(in: store))
    }

    private func hasAccess(in store: GameStore) -> Bool {
        !store.isGuest && store.game(gameID)?.isGoing == true
    }

    private func prepare(in store: GameStore) {
        var next = currentContext(in: store)
        guard context != next else { return }
        let firstOpen = context == nil
        let losesOwnDraft = context?.sessionID != next.sessionID || !next.isMember
        generation = UUID()
        next = currentContext(in: store)
        opening = UUID()
        updateRefresh?.cancel()
        updateRefresh = nil
        needsMessages = false
        needsActivity = false
        latestRead?.reads.cancelAll()
        incrementalRead?.reads.cancelAll()
        latestRead?.task.cancel()
        incrementalRead?.task.cancel()
        latestRead = nil
        incrementalRead = nil
        for delivery in sendTasks.values { delivery.task.cancel() }
        sendTasks = [:]
        if !firstOpen {
            messages = []
            if losesOwnDraft {
                pending = []
                draft = ""
                draftError = nil
                asksForRules = false
            } else {
                // Own text is safe to retain while membership survives. A cancelled send may
                // already have arrived; keep its client ID so an explicit retry cannot duplicate it.
                for index in pending.indices where pending[index].error == nil {
                    pending[index].error = .unknown("send_outcome_unknown")
                }
            }
            state = .idle
            hasOlder = false
            isLoadingOlder = false
            hasLoaded = false
            refreshError = nil
            isConnected = false
        }
        context = next
        // The first screen can use the store's loaded membership. A privacy revision needs a
        // new membership read before any chat page is accepted, even if the game is cached.
        authorizedContext = firstOpen && next.isMember ? next : nil
    }

    private func authorize(_ session: Context, in store: GameStore) async -> Bool {
        guard isCurrent(session, in: store) else { return false }
        if authorizedContext == session { return true }
        await store.loadGame(gameID)
        guard !Task.isCancelled, isCurrent(session, in: store) else {
            prepare(in: store)
            return false
        }
        authorizedContext = session
        return true
    }

    private func isCurrent(_ session: Context, in store: GameStore) -> Bool {
        context == session && currentContext(in: store) == session && session.isMember
    }

    private func wait(for flight: ReadFlight, waiter: UUID) async -> Result<[ChatMessage], any Error> {
        do {
            let messages = try await flight.reads.value(for: 0) { try await flight.task.value }
            return .success(messages)
        } catch {
            return .failure(error)
        }
    }

    private func release(_ waiter: UUID, from flight: ReadFlight) {
        flight.waiters.remove(waiter)
        guard flight.waiters.isEmpty else { return }
        if !flight.published { flight.task.cancel() }
        if latestRead?.id == flight.id {
            latestRead = nil
            if state == .loading { state = hasLoaded ? .loaded : .idle }
        }
        if incrementalRead?.id == flight.id { incrementalRead = nil }
    }

    // MARK: Sending

    /// Shows the message right away, then sends it. The same checks as the server's text filter run
    /// first, so an obvious refusal never leaves the composer.
    func send(in store: GameStore) {
        prepare(in: store)
        guard hasAccess(in: store), authorizedContext == context else { return }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        if TextFilter.hasLink(body) {
            draftError = TextFilter.linkMessage
            return
        }
        guard TextFilter.isFriendly(body) else {
            draftError = TextFilter.message
            return
        }
        draft = ""
        draftError = nil
        let message = Pending(id: UUID(), body: body, sentAt: .now)
        pending.append(message)
        Task { await deliver(message.id, in: store) }
    }

    /// "Tap to retry". The client ID stays the same, so a send that did arrive isn't posted twice.
    func retry(_ id: UUID, in store: GameStore) {
        prepare(in: store)
        guard hasAccess(in: store), authorizedContext == context else { return }
        guard let index = pending.firstIndex(where: { $0.id == id }), pending[index].error != nil else { return }
        pending[index].error = nil
        Task { await deliver(id, in: store) }
    }

    func discard(_ id: UUID) {
        pending.removeAll { $0.id == id }
    }

    /// "Before you chat": I agree. Sends anything that was waiting on it.
    func acceptRules(in store: GameStore) async {
        prepare(in: store)
        let session = currentContext(in: store)
        guard await authorize(session, in: store) else { return }
        do {
            try await store.acceptChatRules()
            guard isCurrent(session, in: store) else { return }
            asksForRules = false
            for message in pending where message.error == .chatRulesRequired { retry(message.id, in: store) }
        } catch {
            guard isCurrent(session, in: store), !OperationCancellation.isCancellation(error) else { return }
            store.notice = store.domainError(error).message
        }
    }

    func deliver(_ id: UUID, in store: GameStore) async {
        prepare(in: store)
        guard let message = pending.first(where: { $0.id == id }) else { return }
        let session = currentContext(in: store)
        guard await authorize(session, in: store) else { return }
        let delivery: (id: UUID, task: Task<ChatMessage, any Error>)
        if let existing = sendTasks[id] {
            delivery = existing
        } else {
            let repository = store.chat
            delivery = (UUID(), Task { [weak self, gameID] in
                guard self?.isCurrent(session, in: store) == true else { throw CancellationError() }
                return try await repository.sendMessage(gameID: gameID, body: message.body, clientID: id)
            })
            sendTasks[id] = delivery
        }
        defer { if sendTasks[id]?.id == delivery.id { sendTasks[id] = nil } }
        do {
            let sent = try await delivery.task.value
            guard isCurrent(session, in: store) else { return }
            merge([sent])
        } catch {
            guard isCurrent(session, in: store) else { return }
            // A cancelled send has an uncertain outcome. The stable client ID makes explicit retry safe.
            let error = OperationCancellation.isCancellation(error) ? DomainError.unknown("send_outcome_unknown") : store.domainError(error)
            store.noteFailure(error)
            if error == .chatRulesRequired { asksForRules = true }
            if let index = pending.firstIndex(where: { $0.id == id }) { pending[index].error = error }
        }
    }

    /// Adds messages without repeating any, keeps them in order, and drops the unsent copy of each
    /// one that has now arrived.
    private func merge(_ incoming: [ChatMessage]) {
        guard !incoming.isEmpty else { return }
        var byID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for message in incoming { byID[message.id] = message }
        messages = byID.values.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        let arrived = Set(incoming.map(\.clientID))
        pending.removeAll { arrived.contains($0.id) }
    }
}
