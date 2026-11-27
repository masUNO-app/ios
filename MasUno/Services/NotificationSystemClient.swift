import UIKit
import UserNotifications

/// Permission and APNs registration use a boundary that mock runs can replace.
@MainActor
protocol NotificationSystemClient {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func registerForRemoteNotifications()
    func setCategories(_ categories: Set<UNNotificationCategory>)
    func add(_ request: UNNotificationRequest) async throws
}

struct LiveNotificationSystemClient: NotificationSystemClient {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func setCategories(_ categories: Set<UNNotificationCategory>) {
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }
}

#if DEBUG
final class MockNotificationSystemClient: NotificationSystemClient {
    var status: UNAuthorizationStatus = .notDetermined
    var grantsAuthorization = true
    var settingsDelay: Duration = .zero
    private(set) var registrationRequests = 0
    private(set) var categories: Set<UNNotificationCategory> = []
    private(set) var requests: [UNNotificationRequest] = []

    func authorizationStatus() async -> UNAuthorizationStatus {
        if settingsDelay > .zero { try? await Task.sleep(for: settingsDelay) }
        return status
    }

    func requestAuthorization() async throws -> Bool {
        status = grantsAuthorization ? .authorized : .denied
        return grantsAuthorization
    }

    func registerForRemoteNotifications() { registrationRequests += 1 }
    func setCategories(_ categories: Set<UNNotificationCategory>) { self.categories = categories }
    func add(_ request: UNNotificationRequest) async throws { requests.append(request) }
}
#endif
