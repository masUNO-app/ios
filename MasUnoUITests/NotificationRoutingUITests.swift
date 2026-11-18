import XCTest

/// Use real push routing and SwiftUI destinations, including notification cleanup callbacks.
final class NotificationRoutingUITests: XCTestCase {
    @MainActor private func openNotification(screen: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-liveAuth", "NO", "-mockLocation", "YES", "-screen", screen,
                               "-notificationSettingsDelay", "60",
                               "-appLanguage", "system", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor func testChatNotificationOpensChatAndCanGoBackToTheGame() {
        let app = openNotification(screen: "push-chat")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Mute chat"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.state, .runningForeground)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["detail-open-chat"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor func testGameNotificationOpensTheGame() {
        let app = openNotification(screen: "push-game")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["detail-open-chat"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.state, .runningForeground)
    }
}
