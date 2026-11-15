import SwiftUI
import UIKit

@main
struct MasUnoApp: App {
    @UIApplicationDelegateAdaptor(NotificationCenterBridge.self) private var notifications

    init() {
        Theme.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(notifications: notifications)
        }
    }
}
