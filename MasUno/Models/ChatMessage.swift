import Foundation

struct ChatMessage: Identifiable, Hashable {
    var id = UUID()
    var sender: String
    var text: String
    var sentAt: Date
}
