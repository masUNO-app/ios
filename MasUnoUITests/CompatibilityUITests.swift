import XCTest

/// Run on both iOS 18 and the newest simulator: these exercise the alternate controls and
/// toolbar through their real navigation paths. Every launch uses the in-memory backend.
final class CompatibilityUITests: XCTestCase {
    @MainActor
    private func launch(screen: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-liveAuth", "NO", "-esports", "NO", "-mockLocation", "YES", "-screen", screen,
            "-notificationSettingsDelay", "60",
            "-appLanguage", "system", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        return app
    }

    @MainActor
    private func assertHittable(
        _ element: XCUIElement, timeout: TimeInterval = 5,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [ready], timeout: timeout), .completed,
            "Expected \(element.label) to be visible and tappable", file: file, line: line
        )
    }

    @MainActor
    func testMapActionsOpenUsableSheetsAndProfile() {
        let app = launch(screen: "map")
        defer { app.terminate() }

        let filter = app.buttons["Filter"]
        let addGame = app.buttons["Make a plan"]
        let me = app.buttons["Me"]
        let location = app.buttons["Show my location"]
        assertHittable(filter, timeout: 20)
        assertHittable(addGame)
        assertHittable(me)
        assertHittable(location)

        // The recenter control follows the avatar's measured position. Verify it stays above
        // the avatar with each OS's toolbar geometry, without depending on a fixed button size.
        XCTAssertFalse(location.frame.intersects(me.frame), "Recenter must not cover the profile button")
        XCTAssertLessThanOrEqual(location.frame.maxY, me.frame.minY, "Recenter must sit above the profile button")
        let controls = XCTAttachment(screenshot: app.screenshot())
        controls.name = "map-controls"
        controls.lifetime = .keepAlways
        add(controls)

        filter.tap()
        XCTAssertTrue(app.staticTexts["Filter plans"].waitForExistence(timeout: 5))

        let basketball = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Basketball")).firstMatch
        XCTAssertTrue(basketball.waitForExistence(timeout: 5))
        basketball.tap()
        app.buttons["Close"].tap()

        // The selected chip must update the actual map filter, beyond merely dismissing a sheet.
        XCTAssertTrue(app.buttons["Filter · 1"].waitForExistence(timeout: 5))
        assertHittable(addGame)
        addGame.tap()
        // Any element type: the field box merges the text field with its label.
        let name = app.descendants(matching: .any)["game-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Create plan"].exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))

        assertHittable(me)
        me.tap()
        XCTAssertTrue(app.navigationBars["Me"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Settings"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["Going"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["Hosting"].exists)
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testNonMemberCannotReadOrSendInChat() {
        let app = launch(screen: "chat-unavailable")
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["This chat isn't available."].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Send"].exists)
        XCTAssertFalse(app.buttons["Who's going"].exists)
        let denied = XCTAttachment(screenshot: app.screenshot())
        denied.name = "chat-access-denied"
        denied.lifetime = .keepAlways
        add(denied)
    }

    @MainActor
    func testGuestAccountActionContinuesToSignUp() {
        let app = launch(screen: "guest")
        defer { app.terminate() }
        let account = app.buttons["Account"]
        XCTAssertTrue(account.waitForExistence(timeout: 20))
        account.tap()
        XCTAssertTrue(app.staticTexts["Your account"].waitForExistence(timeout: 5))

        app.buttons["Create account"].tap()
        XCTAssertTrue(app.staticTexts["Create your account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["At least 8 characters"].exists)
        // The older-system pill style must preserve the underlying button's disabled state.
        XCTAssertFalse(app.buttons["Create account"].isEnabled)
        XCTAssertEqual(app.state, .runningForeground)
    }
}
