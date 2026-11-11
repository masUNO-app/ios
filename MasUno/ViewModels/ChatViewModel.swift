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
    /// Messages from the same person this close together share one name line.
    private static let runGap: TimeInterval = 5 * 60

    let gameID: UUID
    private(set) var messages: [ChatMessage] = []
    private(set) var pending: [Pending] = []
    private(set) var state = GameStore.LoadState.idle
    /// There are messages before the oldest one loaded.
    private(set) var hasOlder = false
    private(set) var isLoadingOlder = false
    var draft = ""
    /// Shown above the composer when the text filter refuses a draft.
    var draftError: String?
    /// "Before you chat" needs an answer.
    var asksForRules = false

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

    /// Loads the latest page, then follows the game's channel until the screen closes.
    func open(in store: GameStore) async {
        await reload(in: store)
        for await update in store.chat.updates(gameID: gameID) {
            switch update {
            case .message:
                await fetchNew(in: store)
            case .activity:
                await store.loadActivity(gameID)
                await store.loadAttendees(gameID)
                await store.loadGame(gameID)
            }
        }
    }

    /// The safety net under the live channel: runs until the screen closes.
    func poll(in store: GameStore, every interval: Duration = pollInterval) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            if Task.isCancelled { return }
            await fetchNew(in: store)
            await store.loadActivity(gameID)
        }
    }

    func reload(in store: GameStore) async {
        if state == .idle { state = .loading }
        do {
            let page = try await store.chat.fetchMessages(gameID: gameID, before: nil, limit: Self.pageSize)
            merge(page)
            hasOlder = page.count == Self.pageSize
            state = .loaded
            await store.markChatRead(gameID)
        } catch {
            let error = store.domainError(error)
            store.noteFailure(error)
            state = messages.isEmpty ? .failed(error) : .loaded
        }
    }

    /// Everything since the newest message we have, reaching back a little for one that was
    /// written at the same moment but landed later.
    func fetchNew(in store: GameStore) async {
        guard state == .loaded, let newest = messages.last?.createdAt else { return await reload(in: store) }
        guard let fresh = try? await store.chat.fetchMessages(gameID: gameID, since: newest.addingTimeInterval(-5)) else { return }
        let known = Set(messages.map(\.id))
        merge(fresh)
        if fresh.contains(where: { !known.contains($0.id) }) { await store.markChatRead(gameID) }
    }

    func loadOlder(in store: GameStore) async {
        guard hasOlder, !isLoadingOlder, let oldest = messages.first?.createdAt else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let page = try await store.chat.fetchMessages(gameID: gameID, before: oldest, limit: Self.pageSize)
            hasOlder = page.count == Self.pageSize
            merge(page)
        } catch {
            store.noteFailure(store.domainError(error))
        }
    }

    // MARK: Sending

    /// Shows the message right away, then sends it. The same checks as the server's text filter run
    /// first, so an obvious refusal never leaves the composer.
    func send(in store: GameStore) {
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
        guard let index = pending.firstIndex(where: { $0.id == id }), pending[index].error != nil else { return }
        pending[index].error = nil
        Task { await deliver(id, in: store) }
    }

    func discard(_ id: UUID) {
        pending.removeAll { $0.id == id }
    }

    /// "Before you chat": I agree. Sends anything that was waiting on it.
    func acceptRules(in store: GameStore) async {
        do {
            try await store.acceptChatRules()
            asksForRules = false
            for message in pending where message.error == .chatRulesRequired { retry(message.id, in: store) }
        } catch {
            store.notice = store.domainError(error).message
        }
    }

    func deliver(_ id: UUID, in store: GameStore) async {
        guard let message = pending.first(where: { $0.id == id }) else { return }
        do {
            merge([try await store.chat.sendMessage(gameID: gameID, body: message.body, clientID: id)])
        } catch {
            let error = store.domainError(error)
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
