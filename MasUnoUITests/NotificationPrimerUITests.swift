import XCTest

/// These exercise SwiftUI presentation, where missing environment objects trap at runtime.
/// Repositories stay on mocks; no event or RSVP is sent to a hosted backend.
final class NotificationPrimerUITests: XCTestCase {
    @MainActor private func checkPrimer(after screen: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-liveAuth", "NO", "-mockLocation", "YES", "-screen", screen,
                               "-notificationDeclines.00000000-0000-0000-0000-000000000099", "0"]
        app.launch()
        let dismiss = app.buttons["Not now"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 20), "Successful \(screen) must present the primer without terminating")
        XCTAssertEqual(app.state, .runningForeground)
        dismiss.tap()
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
        app.terminate()
    }

    @MainActor func testJoinPresentsAndDismissesPrimer() { checkPrimer(after: "join") }
    @MainActor func testCreatePresentsAndDismissesPrimer() { checkPrimer(after: "create-primer") }
}
