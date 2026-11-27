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
            if isUnitTestHost {
                // Unit tests construct their own services. Rendering the map here starts
                // location and Metal work unrelated to those tests on the same main actor.
                Color.clear
            } else {
                ContentView(notifications: notifications)
            }
        }
    }

    private var isUnitTestHost: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        #else
        false
        #endif
    }
}
