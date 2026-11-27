import XCTest

/// Launching the app on mocks at a design-review screen (`-screen …`), for the newer UI tests.
enum UITestApp {
    /// The largest accessibility text size (AX5).
    static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    @MainActor
    static func launch(screen: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-liveAuth", "NO", "-esports", "NO", "-mockLocation", "YES", "-screen", screen,
                               "-notificationSettingsDelay", "60",
                               "-appLanguage", "system", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        return app
    }
}

extension XCTestCase {
    /// Waits for `element` to be on screen and tappable. Generous, since a loaded CI runner can take
    /// seconds per lookup; it returns as soon as the element is ready.
    @MainActor
    func assertHittable(_ element: XCUIElement, _ message: @autoclosure () -> String, timeout: TimeInterval = 20,
                        file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed, message(), file: file, line: line)
    }

    /// Swipes up, as someone would, until `element` is tappable or `attempts` swipes have gone by, then
    /// asserts it's tappable. For content that scrolls at the largest text sizes.
    @MainActor
    func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication, _ message: @autoclosure () -> String,
                          attempts: Int = 6, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 20), message(), file: file, line: line)
        for _ in 0..<attempts where !element.isHittable {
            app.swipeUp()
        }
        assertHittable(element, message(), file: file, line: line)
    }
}
