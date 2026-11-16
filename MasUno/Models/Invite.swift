import Foundation

/// One of your invite codes (`my_invites`, N37). A code lets one waiting account in without the
/// team's approval. Members have 3; the team can give more.
nonisolated struct Invite: Identifiable, Hashable, Sendable {
    /// 8 characters, upper case, as the server stores it: "ABCDEFGH".
    let code: String
    var createdAt: Date
    var redeemedAt: Date?
    /// Who used it, as "Ana G.". Nil until they've set up a profile, or if either of you blocked the other.
    var redeemedBy: String?

    var id: String { code }
    var isUsed: Bool { redeemedAt != nil }

    /// "ABCD-EFGH": easier to read aloud and type than eight letters in a row.
    var displayCode: String { Self.display(code) }

    /// Splits a code in half with a dash. Anything that isn't 8 characters is left as it is.
    static func display(_ code: String) -> String {
        guard code.count == 8 else { return code }
        return "\(code.prefix(4))-\(code.suffix(4))"
    }

    /// What someone typed, the way the server compares it: trimmed, upper case, without spaces or dashes.
    /// Also drops the longer dashes that smart punctuation can turn a typed "-" into.
    static func normalized(_ typed: String) -> String {
        typed.uppercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "‐" && $0 != "–" && $0 != "—" }
    }
}
