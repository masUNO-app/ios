import UIKit
import UserNotifications

/// Receives the APNs token and notification taps. SwiftUI owns this object through
/// `@UIApplicationDelegateAdaptor`. `PushNotificationService` does the work on the main actor.
nonisolated final class NotificationCenterBridge: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private let serviceBox = ServiceBox()

    /// Called once the app has built its services. Registers the categories and becomes the notification delegate.
    @MainActor
    func connect(_ service: PushNotificationService) {
        serviceBox.service = service
        UNUserNotificationCenter.current().delegate = self
        service.registerCategories()
    }

    nonisolated func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let service = serviceBox.service
        Task { @MainActor in
            await service?.didRegister(token: token)
        }
    }

    nonisolated func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        let service = serviceBox.service
        Task { @MainActor in
            service?.didFailToRegister(error)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        let service = serviceBox.service
        return await MainActor.run {
            service?.presentationOptions(for: userInfo) ?? [.banner, .sound, .list]
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let reply = (response as? UNTextInputNotificationResponse)?.userText
        let service = serviceBox.service
        await service?.handle(action: action, userInfo: userInfo, reply: reply)
    }
}

/// Lets the nonisolated delegate callbacks reach the main-actor service.
/// The service is only swapped once, at launch, before any callback.
private final class ServiceBox: @unchecked Sendable {
    nonisolated(unsafe) var service: PushNotificationService?
}
