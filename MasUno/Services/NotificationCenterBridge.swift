import UIKit
import UserNotifications

/// Receives the APNs token and notification taps. SwiftUI owns this object through
/// `@UIApplicationDelegateAdaptor`. `PushNotificationService` does the work on the main actor.
nonisolated final class NotificationCenterBridge: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let serviceBox = ServiceBox()

    /// The delegate has to exist before `didFinishLaunching` returns. A cold-launch tap can arrive
    /// before the SwiftUI task connects the service, so that tap is kept and replayed.
    nonisolated func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MainActor.assumeIsolated {
            // Before the delegate is set, so a background action has a service without a scene.
            let push = AppLaunch.services.push
            _ = serviceBox.install(push)
            push.registerCategories()
            UNUserNotificationCenter.current().delegate = self
        }
        return true
    }

    /// Called once the app has built its services. The real app installs the service before the
    /// delegate is set, so this replay is empty there. It stays for a `connect` that runs first.
    @MainActor
    func connect(_ service: PushNotificationService) async {
        let waiting = serviceBox.install(service)
        UNUserNotificationCenter.current().delegate = self
        service.registerCategories()
        for tap in waiting {
            await service.handle(action: tap.action, payload: tap.payload, reply: tap.reply)
        }
    }

    nonisolated func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let service = serviceBox.current()
        Task { @MainActor in
            await service?.didRegister(token: token)
        }
    }

    nonisolated func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        let service = serviceBox.current()
        Task { @MainActor in
            service?.didFailToRegister(error)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let payload = NotificationPayload(userInfo: notification.request.content.userInfo)
        let service = serviceBox.current()
        return await MainActor.run {
            service?.presentationOptions(for: payload) ?? [.banner, .sound, .list]
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let payload = NotificationPayload(userInfo: response.notification.request.content.userInfo)
        let reply = (response as? UNTextInputNotificationResponse)?.userText
        let tap = PendingTap(action: action, payload: payload, reply: reply)
        await perform(tap)
    }

    /// A background launch has not restored the session yet. A foreground tap already has one.
    @MainActor
    private func perform(_ tap: PendingTap) async {
        // Opening the UI queues its route through launch. Only background actions need
        // a restored session here; launch already restores it for a normal tap.
        let needsRestore = tap.action != UNNotificationDefaultActionIdentifier
            && AppLaunch.services.auth.state == .loading
        await handleNotificationTap(
            drop: AppViewModel.isSignOutPending(),
            restoreSession: needsRestore,
            box: serviceBox,
            tap: tap,
            restore: { await AppLaunch.services.auth.restoreSession() }
        ) { service, tap in
            await service.handle(action: tap.action, payload: tap.payload, reply: tap.reply)
        }
    }
}

/// Runs a tap. A sign-out that is still dropping its token is ignored. The session is restored
/// only while launch has not finished, so a foreground tap is not held up on a profile read.
@MainActor
func handleNotificationTap(
    drop: Bool = false,
    restoreSession: Bool,
    box: ServiceBox,
    tap: PendingTap,
    restore: @escaping @MainActor () async -> Void = {},
    handle: @escaping @MainActor (PushNotificationService, PendingTap) async -> Void
) async {
    guard !drop else { return }
    if restoreSession { await restore() }
    if let service = box.service(for: tap) {
        await handle(service, tap)
    }
}

/// A tap that arrived before the service existed. Only the decoded, sendable payload is kept.
nonisolated struct PendingTap: Sendable {
    let action: String
    let payload: NotificationPayload?
    let reply: String?
}

/// Lets the nonisolated delegate callbacks reach the main-actor service.
/// `didFinishLaunching` installs the service before the delegate is set, so a tap can't
/// arrive first in the app. The queue stays for a `connect` that runs before that install.
/// Nonisolated so the bridge can create it outside the main actor.
nonisolated final class ServiceBox: @unchecked Sendable {
    nonisolated(unsafe) private var service: PushNotificationService?
    private var pending: [PendingTap] = []
    private let lock = NSLock()

    /// Stores the service and returns taps that arrived before it.
    func install(_ service: PushNotificationService) -> [PendingTap] {
        lock.lock()
        defer { lock.unlock() }
        self.service = service
        let waiting = pending
        pending = []
        return waiting
    }

    func current() -> PushNotificationService? {
        lock.lock()
        defer { lock.unlock() }
        return service
    }

    /// The service, when it exists. Otherwise keeps the tap for `install`.
    func service(for tap: PendingTap) -> PushNotificationService? {
        lock.lock()
        defer { lock.unlock() }
        if let service { return service }
        pending.append(tap)
        return nil
    }
}
