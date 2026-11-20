import XCTest

/// The core loop at the largest accessibility text size (AX5): each action is on screen, can be tapped,
/// and does what it says. This is the release criterion for large text (A11Y P0), and it replaces the
/// audit's Dynamic Type and clipped-text passes, which flagged text that read in full.
final class LargeTextUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ screen: String, _ extra: [String] = []) -> XCUIApplication {
        UITestApp.launch(screen: screen, UITestApp.largestText + extra)
    }

    /// Join an open game, get past the notification primer, and land in the game.
    @MainActor func testJoiningAGame() {
        // Shows the primer on the first join, as for a new account.
        let app = launch("detail-open", ["-notificationDeclines.00000000-0000-0000-0000-000000000099", "0"])
        defer { app.terminate() }

        let join = app.buttons["detail-count-me-in"]
        assertHittable(join, "Count me in must be reachable at AX5")
        join.tap()

        // At AX5 the primer's card scrolls, and its buttons start below the fold.
        let notNow = app.buttons["Not now"]
        scrollToHittable(notNow, in: app, "The primer's Not now must be reachable at AX5, scrolling if needed")
        notNow.tap()

        assertHittable(app.buttons["detail-open-chat"], "After joining, Open group chat must be reachable at AX5")
    }

    /// A full game: turn on the spot alert.
    @MainActor func testSpotAlertOnAFullGame() {
        let app = launch("detail-full")
        defer { app.terminate() }

        let alert = app.buttons["Alert me if a spot opens"]
        assertHittable(alert, "Alert me if a spot opens must be reachable at AX5")
        alert.tap()
        assertHittable(app.buttons["Spot alert is on"], "The alert's on state must show at AX5")
    }

    /// Write in the group chat and send.
    @MainActor func testSendingAChatMessage() {
        let app = launch("chat")
        defer { app.terminate() }

        let composer = app.descendants(matching: .any)["chat-composer"]
        assertHittable(composer, "The composer must be reachable at AX5")
        composer.tap()
        composer.typeText("See you there")
        let send = app.buttons["Send"]
        assertHittable(send, "Send must be reachable at AX5 with the keyboard up")
        send.tap()

        let sent = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "See you there")).firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 20), "The sent message must show in the chat")
        XCTAssertFalse((composer.value as? String)?.contains("See you there") == true, "Sending clears the composer")
    }

    /// The last onboarding step: the guidelines scroll, and I agree is reachable at the end.
    @MainActor func testAgreeingToTheGuidelines() {
        let app = launch("onboarding-guidelines")
        defer { app.terminate() }

        scrollToHittable(app.buttons["I agree"], in: app, "I agree must be reachable at AX5, scrolling if needed")
    }
}
