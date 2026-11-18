import Intents
import UserNotifications

/// Rewrites a chat push into a communication notification: the sender's initials and the sport badge.
/// If drawing or donating fails, iOS keeps the plain alert from the payload.
nonisolated final class NotificationService: UNNotificationServiceExtension {
    private let pending = PendingDelivery()

    nonisolated override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let pending = pending
        pending.handler = contentHandler
        pending.fallback = request.content
        // A copy, so the timeout path and the rewrite don't share one object.
        // The task only captures the job, which is sendable. The alert stays inside it.
        let job = RewriteJob(
            content: (request.content.mutableCopy() as? UNNotificationContent) ?? request.content,
            pending: pending
        )
        Task { await job.run() }
    }

    nonisolated override func serviceExtensionTimeWillExpire() {
        pending.finishWithFallback()
    }

    /// Builds the intent iOS uses for the Messages-style banner.
    /// - Parameter content: The alert APNs delivered.
    /// - Returns: The rewritten content, or the original when this isn't a chat we can draw.
    fileprivate static func communicationContent(from content: UNNotificationContent) async -> UNNotificationContent {
        guard let payload = NotificationPayload(userInfo: content.userInfo),
              payload.kind == "chat_message",
              let sender = payload.sender,
              let game = payload.game,
              let gameID = payload.gameID
        else { return content }

        let senderPerson = INPerson(
            personHandle: INPersonHandle(value: sender.id.uuidString, type: .unknown),
            nameComponents: nil,
            displayName: sender.name,
            image: INImage(imageData: AvatarRenderer.person(id: sender.id, initials: sender.initials)),
            contactIdentifier: nil,
            customIdentifier: sender.id.uuidString,
            isMe: false
        )
        let meID = AppGroupStore.myID ?? "me"
        let me = INPerson(
            personHandle: INPersonHandle(value: meID, type: .unknown),
            nameComponents: nil,
            displayName: nil,
            image: nil,
            contactIdentifier: nil,
            customIdentifier: meID,
            isMe: true
        )
        let others = payload.others.prefix(2).map { person in
            INPerson(
                personHandle: INPersonHandle(value: person.id.uuidString, type: .unknown),
                nameComponents: nil,
                displayName: person.name,
                image: INImage(imageData: AvatarRenderer.person(id: person.id, initials: initials(of: person.name))),
                contactIdentifier: nil,
                customIdentifier: person.id.uuidString,
                isMe: false
            )
        }
        let message = payload.communicationBody(fallback: content.body)
        let intent = INSendMessageIntent(
            recipients: [me] + others,
            outgoingMessageType: .outgoingMessageText,
            content: message,
            speakableGroupName: INSpeakableString(spokenPhrase: game.title),
            conversationIdentifier: gameID.uuidString,
            serviceName: nil,
            sender: senderPerson,
            attachments: nil
        )
        intent.setImage(INImage(imageData: AvatarRenderer.sport(slug: game.sport)), forParameterNamed: \.speakableGroupName)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        do {
            try await interaction.donate()
            // updating(from:) adds the sender header, but retains the APNs alert body.
            // Remove its sender prefix first, leaving the original fallback intact.
            guard let communication = content.mutableCopy() as? UNMutableNotificationContent else { return content }
            communication.body = message
            return try communication.updating(from: intent)
        } catch {
            return content
        }
    }

    private static func initials(of name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

/// Owns the alert for the rewrite task. The task captures this box, not the notification content.
nonisolated private final class RewriteJob: @unchecked Sendable {
    private let content: UNNotificationContent
    private let pending: PendingDelivery

    init(content: UNNotificationContent, pending: PendingDelivery) {
        self.content = content
        self.pending = pending
    }

    func run() async {
        let updated = await NotificationService.communicationContent(from: content)
        pending.finish(updated)
    }
}

/// Holds the completion handler so the time-limit callback can still answer.
/// Nonisolated on purpose: the service extension is not on the main actor, and this box is only a lock.
nonisolated private final class PendingDelivery: @unchecked Sendable {
    var handler: ((UNNotificationContent) -> Void)?
    var fallback: UNNotificationContent?
    private let lock = NSLock()

    func finish(_ content: UNNotificationContent) {
        lock.lock()
        let handler = self.handler
        self.handler = nil
        lock.unlock()
        handler?(content)
    }

    func finishWithFallback() {
        lock.lock()
        let handler = self.handler
        let fallback = self.fallback
        self.handler = nil
        lock.unlock()
        if let handler, let fallback { handler(fallback) }
    }
}
