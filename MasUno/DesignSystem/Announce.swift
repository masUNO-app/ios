import Accessibility
import Foundation

/// VoiceOver announcements for results that don't move focus (joined, copied, sent, errors).
/// Pass an already-localized message, e.g. `Announce.post(String.app("Copied"))`.
enum Announce {
    typealias Priority = AttributeScopes.AccessibilityAttributes.AnnouncementPriorityAttribute.AnnouncementPriority

    /// Speaks `message` with VoiceOver, without moving focus. `.high` interrupts; use it only for errors.
    static func post(_ message: String, priority: Priority? = nil) {
        var text = AttributedString(message)
        if let priority { text.accessibilitySpeechAnnouncementPriority = priority }
        AccessibilityNotification.Announcement(text).post()
    }
}
