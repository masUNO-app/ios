import Accessibility
import SwiftUI

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

extension View {
    /// Speaks `message` each time it changes and then holds still for `delay`, so typing a search
    /// is read once, not per letter. Not when the view appears: what's on screen then is read as
    /// part of moving there.
    func announcesChanges(of message: String, after delay: Duration = .milliseconds(500)) -> some View {
        modifier(ChangeAnnouncer(message: message, delay: delay))
    }
}

private struct ChangeAnnouncer: ViewModifier {
    let message: String
    let delay: Duration
    /// The last message spoken, or the first one shown.
    @State private var spoken: String?

    func body(content: Content) -> some View {
        content.task(id: message) {
            guard let last = spoken else {
                spoken = message
                return
            }
            guard message != last else { return }
            do { try await Task.sleep(for: delay) } catch { return }
            self.spoken = message
            Announce.post(message)
        }
    }
}
