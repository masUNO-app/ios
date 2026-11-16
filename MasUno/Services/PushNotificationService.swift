import Foundation
import Intents
import MapKit
import OSLog
import UIKit
import UserNotifications

/// Permission, the device token, categories and what a tap or action does (NOTIF §6.2, B16).
@Observable
final class PushNotificationService {
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private let repository: any NotificationRepository
    @ObservationIgnored private let games: any GameRepository
    @ObservationIgnored private let chat: any ChatRepository
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Logger(subsystem: "com.masuno.app", category: "Push")
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var lastUploaded: Date?
    @ObservationIgnored private var accountGeneration = 0
    @ObservationIgnored private var deviceTask: Task<Void, Never>?
    /// A tap that arrived before the interface was ready.
    @ObservationIgnored private(set) var pendingRoute: URL?
    /// Set by the root view. A nil URL only brings the app forward.
    @ObservationIgnored var onOpen: ((URL?) -> Void)?
    /// Re-reads the game a banner is about, so the screen is current.
    @ObservationIgnored var onRefreshGame: ((UUID) -> Void)?

    /// `sandbox` in Debug, `production` in Release. Must match the APNs environment of the build.
    static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    init(
        repository: any NotificationRepository, games: any GameRepository, chat: any ChatRepository,
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.games = games
        self.chat = chat
        self.defaults = defaults
        token = defaults.string(forKey: Self.tokenKey)
    }

    /// Categories exist before the person allows notifications, so a later push already has actions.
    func registerCategories() {
        let reply = UNTextInputNotificationAction(
            identifier: Self.reply, title: "Reply", options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Message"
        )
        let markRead = UNNotificationAction(identifier: Self.markRead, title: "Mark as read", options: [])
        let chat = UNNotificationCategory(identifier: "CHAT", actions: [reply, markRead], intentIdentifiers: [INSendMessageIntentIdentifier], options: [])
        let countMeIn = UNNotificationAction(identifier: Self.countMeIn, title: "Count me in", options: [.authenticationRequired])
        let joinCategories = ["SPOT_OPEN", "INTEREST", "SAVED_SOON"].map {
            UNNotificationCategory(identifier: $0, actions: [countMeIn], intentIdentifiers: [], options: [])
        }
        let directions = UNNotificationAction(identifier: Self.directions, title: "Directions", options: [.foreground])
        let reminder = UNNotificationCategory(identifier: "REMINDER", actions: [directions], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories(Set([chat, reminder] + joinCategories))
    }

    /// Asks iOS, then requests a device token when they allow it.
    /// - Returns: Whether iOS granted alert, sound or badge.
    @discardableResult
    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
            if granted { UIApplication.shared.registerForRemoteNotifications() }
            return granted
        } catch {
            logger.error("Permission request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Launch always uploads. Foreground uploads when the last one was more than an hour ago.
    /// - Parameter force: True on launch and sign-in, false on a return to the foreground.
    func refreshRegistration(force: Bool) async {
        await refreshAuthorization()
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
        guard let token else { return }
        if !force, let lastUploaded, Date().timeIntervalSince(lastUploaded) < 3600 { return }
        await upload(token)
    }

    /// The system handed us a token. A token we already uploaded this hour is left alone.
    func didRegister(token: String) async {
        let changed = self.token != token
        self.token = token
        defaults.set(token, forKey: Self.tokenKey)
        if !changed, let lastUploaded, Date().timeIntervalSince(lastUploaded) < 3600 { return }
        await upload(token)
    }

    func didFailToRegister(_ error: any Error) {
        logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Writes the signed-in person into the app group so chat notifications can name them.
    func noteAccount(_ id: UUID?) {
        accountGeneration += 1
        lastUploaded = nil
        AppGroupStore.myID = id?.uuidString
    }

    /// Drops this phone's token while the session is still valid.
    /// - Returns: False when the server still has the token. The local copy is kept so sign-out can try again.
    @discardableResult
    func unregister() async -> Bool {
        let generation = accountGeneration
        let prior = deviceTask
        let task = Task { @MainActor in
            await prior?.value
            guard self.accountGeneration == generation else { return true }
            if let token = self.token {
                do {
                    try await self.repository.unregisterDevice(token: token)
                } catch {
                    self.logger.error("Couldn't unregister the device token: \(error.localizedDescription, privacy: .public)")
                    return self.accountGeneration != generation
                }
            }
            // Sign-in may have queued a new registration during the network call. Keep its
            // local state; the queued upload runs after this old server unregister finishes.
            if self.accountGeneration == generation { self.discardLocalDevice() }
            return true
        }
        deviceTask = Task { _ = await task.value }
        return await task.value
    }

    /// Forgets the token and the signed-in person on this phone. Account deletion does this even
    /// when the server call failed, because the account is gone and the token cascades.
    func discardLocalDevice() {
        accountGeneration += 1
        AppGroupStore.clearAccount()
        token = nil
        defaults.removeObject(forKey: Self.tokenKey)
        lastUploaded = nil
    }

    func fetchPrefs() async throws -> NotificationPrefs {
        try await repository.fetchPrefs()
    }

    func setPrefs(_ prefs: NotificationPrefs) async throws {
        try await repository.setPrefs(prefs)
    }

    /// The primer's tips switch. Does not rewrite the other flags.
    func setWinback(_ on: Bool) async throws {
        try await repository.setWinback(on)
    }

    /// Hide a banner for the chat or game already on screen. Everything else shows.
    /// The open game is refreshed first, including when the banner itself is hidden.
    func presentationOptions(for payload: NotificationPayload?) -> UNNotificationPresentationOptions {
        guard let payload else { return [.banner, .sound, .list] }
        if let gameID = payload.gameID { onRefreshGame?(gameID) }
        if payload.kind == "chat_message", payload.gameID?.uuidString == AppGroupStore.openChatID {
            return []
        }
        if payload.kind != "chat_message", payload.gameID?.uuidString == AppGroupStore.openGameID {
            return []
        }
        return [.banner, .sound, .list]
    }

    /// A tap or a long-press action. Runs with the stored session.
    func handle(action: String, payload: NotificationPayload?, reply: String?) async {
        guard let payload else { return }
        if let outboxID = payload.outboxID {
            do {
                try await repository.markOpened(outboxID)
            } catch {
                logger.error("Couldn't mark notification opened: \(error.localizedDescription, privacy: .public)")
            }
        }
        switch action {
        case Self.reply:
            await sendReply(reply, in: payload)
        case Self.markRead:
            await markRead(payload)
        case Self.countMeIn:
            await countMeIn(payload)
        case Self.directions:
            openDirections(payload)
        default:
            deliver(payload.routeURL())
        }
    }

    /// The root view calls this once it can route.
    func consumePendingRoute() -> URL? {
        let url = pendingRoute
        pendingRoute = nil
        return url
    }

    /// Removes delivered notifications for one thread, such as `game:<id>` or `chat:<id>`.
    static func clearDelivered(thread: String) {
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let identifiers = notifications
                .filter { $0.request.content.threadIdentifier == thread }
                .map(\.request.identifier)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    /// True while iOS hasn't been asked and this account hasn't passed on the primer twice.
    func shouldOfferPrimer(accountID: UUID?) -> Bool {
        guard let accountID, authorizationStatus == .notDetermined else { return false }
        return declines(for: accountID) < 2
    }

    func recordPrimerDecline(accountID: UUID) {
        defaults.set(declines(for: accountID) + 1, forKey: declineKey(accountID))
    }

    /// Closing the primer. Turn on is not a decline. A swipe and Not now each count once.
    func recordPrimerClose(accepted: Bool, accountID: UUID?) {
        guard !accepted, let accountID else { return }
        recordPrimerDecline(accountID: accountID)
    }

    func recordPrimerAccepted(accountID: UUID) {
        defaults.set(2, forKey: declineKey(accountID))
    }

    // MARK: Actions

    private func upload(_ token: String) async {
        let generation = accountGeneration
        let prior = deviceTask
        let task = Task { @MainActor in
            await prior?.value
            guard self.accountGeneration == generation, self.token == token else { return }
            await self.uploadNow(token, generation: generation)
        }
        deviceTask = task
        await task.value
    }

    private func uploadNow(_ token: String, generation: Int) async {
        let locale = Locale.preferredLanguages.first ?? "en"
        do {
            try await repository.registerDevice(
                token: token, environment: Self.environment, locale: locale, appVersion: AppConfig.currentVersion
            )
            if accountGeneration == generation { lastUploaded = .now }
        } catch {
            logger.error("Couldn't register the device token: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sendReply(_ text: String?, in payload: NotificationPayload) async {
        guard let gameID = payload.gameID, let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            _ = try await chat.sendMessage(gameID: gameID, body: text, clientID: UUID())
        } catch {
            logger.error("Reply from a notification failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func markRead(_ payload: NotificationPayload) async {
        guard let gameID = payload.gameID else { return }
        do {
            try await chat.markRead(gameID: gameID)
        } catch {
            logger.error("Mark as read failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func countMeIn(_ payload: NotificationPayload) async {
        guard let gameID = payload.gameID else { return }
        do {
            _ = try await games.joinGame(id: gameID)
        } catch let error as DomainError where error == .full {
            await announceSpotTaken()
        } catch {
            logger.error("Count me in failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func announceSpotTaken() async {
        let content = UNMutableNotificationContent()
        content.title = "Someone beat you to it"
        content.body = "That game just filled up."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logger.error("Couldn't post the full-game notice: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func openDirections(_ payload: NotificationPayload) {
        guard let place = payload.place else { return }
        let item = MKMapItem(location: CLLocation(latitude: place.lat, longitude: place.lng), address: nil)
        item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
        deliver(payload.routeURL())
    }

    private func deliver(_ url: URL?) {
        if let onOpen {
            onOpen(url)
        } else {
            pendingRoute = url
        }
    }

    private func declines(for accountID: UUID) -> Int {
        defaults.integer(forKey: declineKey(accountID))
    }

    private func declineKey(_ accountID: UUID) -> String {
        "notificationDeclines.\(accountID.uuidString)"
    }

    private static let tokenKey = "apnsDeviceToken"
    private static let reply = "REPLY"
    private static let markRead = "MARK_READ"
    private static let countMeIn = "COUNT_ME_IN"
    private static let directions = "DIRECTIONS"
}
