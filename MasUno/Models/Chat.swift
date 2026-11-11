import Foundation

/// A message in a game's group chat (`game_messages`, SPEC §7.6.9 and Appendix A).
nonisolated struct ChatMessage: Identifiable, Hashable, Sendable {
    static let bodyLimit = 1000
    /// The server closes a chat this long after its game ends.
    static let closesAfterEnd: TimeInterval = 24 * 3600

    let id: UUID
    var gameID: UUID
    var sender: PersonSummary
    var body: String
    /// The ID the sender's phone gave this send, so a retry never posts twice.
    var clientID: UUID
    var createdAt: Date
}

/// What a game's chat channel says changed. It carries no content: the app reads the rows itself.
nonisolated enum ChatUpdate: Hashable, Sendable {
    /// A new message.
    case message
    /// A new system row: someone joined or left, or the host changed or cancelled the game.
    case activity
}

extension Game {
    /// Whether you can still post: you're in the game, it isn't cancelled, and it ended under 24 hours ago.
    func isChatOpen(now: Date = .now) -> Bool {
        isGoing && !isCancelled && now < endsAt.addingTimeInterval(ChatMessage.closesAfterEnd)
    }
}
