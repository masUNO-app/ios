import Foundation

/// "@Maya C." in a chat message (NOTIF §3.5). The text carries the name; the message carries the ID,
/// which is what the server checks and notifies, even when Maya muted the game.
nonisolated enum Mention {
    /// The server keeps at most this many per message.
    static let limit = 10
    /// A first name is short; past this the "@" is just text.
    private static let queryLimit = 30

    /// "@Maya C.", exactly what the server looks for in the text.
    static func token(for person: PersonSummary) -> String { "@\(person.displayName)" }

    /// The first name being typed after an "@" at the end of `text`, without the "@". Empty right
    /// after the "@". Nil when the end isn't a mention: no "@", an "@" inside a word (an email),
    /// or a space or line break since it.
    static func query(in text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        if at > text.startIndex, !text[text.index(before: at)].isWhitespace { return nil }
        let query = text[text.index(after: at)...]
        guard query.count <= queryLimit, !query.contains(where: \.isWhitespace), !query.contains("@") else { return nil }
        return String(query)
    }

    /// The people whose first name starts with `query`, ignoring case and accents, in the order given.
    static func suggestions(for query: String, among people: [PersonSummary]) -> [PersonSummary] {
        let typed = fold(query)
        return people.filter { typed.isEmpty || fold($0.firstName).hasPrefix(typed) }
    }

    /// Where the mentions in a message's text are, each marked if it's you. A name is found only for
    /// an ID the message mentions; overlapping matches keep the earlier one.
    /// - Parameters:
    ///   - body: The message text.
    ///   - mentions: The IDs the message mentions.
    ///   - names: Display names you know, by ID (the game's people and you).
    ///   - me: Your ID.
    static func ranges(
        in body: String, mentions: [UUID], names: [UUID: String], me: UUID?
    ) -> [(range: Range<String.Index>, isMe: Bool)] {
        var found: [(range: Range<String.Index>, isMe: Bool)] = []
        for id in Set(mentions) {
            guard let name = names[id], !name.isEmpty else { continue }
            let token = "@\(name)"
            var start = body.startIndex
            while let range = body.range(of: token, range: start..<body.endIndex) {
                found.append((range, id == me))
                start = range.upperBound
            }
        }
        found.sort { $0.range.lowerBound < $1.range.lowerBound || ($0.range.lowerBound == $1.range.lowerBound && $0.isMe) }
        var kept: [(range: Range<String.Index>, isMe: Bool)] = []
        for match in found where kept.last.map({ $0.range.upperBound <= match.range.lowerBound }) ?? true {
            kept.append(match)
        }
        return kept
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// The people a draft mentions, kept in step with its text: picking a suggestion adds one, and
/// deleting or changing the inserted name drops it.
nonisolated struct MentionDraft: Equatable, Sendable {
    private(set) var people: [PersonSummary] = []

    var ids: [UUID] { people.map(\.id) }

    /// Replaces the "@…" being typed at the end of `text` with "@Maya C. " and records Maya.
    /// - Parameters:
    ///   - person: The suggestion picked.
    ///   - text: The draft. Unchanged when it doesn't end in a mention being typed.
    mutating func insert(_ person: PersonSummary, into text: inout String) {
        guard Mention.query(in: text) != nil, let at = text.lastIndex(of: "@") else { return }
        text = String(text[..<at]) + Mention.token(for: person) + " "
        if !people.contains(where: { $0.id == person.id }) { people.append(person) }
    }

    /// Keeps each person only while their "@Name" is still in `text`, as many times as it appears.
    mutating func reconcile(with text: String) {
        var left: [String: Int] = [:]
        people = people.filter { person in
            let token = Mention.token(for: person)
            let available = left[token] ?? text.components(separatedBy: token).count - 1
            guard available > 0 else { return false }
            left[token] = available - 1
            return true
        }
    }

    mutating func removeAll() {
        people = []
    }
}
