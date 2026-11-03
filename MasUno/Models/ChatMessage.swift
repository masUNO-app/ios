import Foundation

/// A row in a game's group chat: a message, or a system line ("Maya created the chat").
struct ChatMessage: Identifiable, Hashable {
    enum Kind: Hashable {
        case message, system
    }

    var id = UUID()
    var kind: Kind = .message
    /// Empty for system rows.
    var sender: String = ""
    var text: String
    var sentAt: Date
}
