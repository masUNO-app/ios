import XCTest

/// Who's going: the report-and-block menu beside each person.
final class WhoIsGoingUITests: XCTestCase {
    /// The whole circle opens the menu, not just the "•••" glyph in its middle.
    @MainActor
    func testReportMenuOpensFromAnywhereOnItsCircle() {
        continueAfterFailure = false
        let app = UITestApp.launch(screen: "who")
        defer { app.terminate() }

        let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Report or block")).firstMatch
        assertHittable(menu, "The first person's menu button")
        XCTAssertGreaterThanOrEqual(menu.frame.width, 30, "\(menu.frame)")

        // Near the top edge, then near the left edge: both off the glyph.
        for offset in [CGVector(dx: 0.5, dy: 0.15), CGVector(dx: 0.15, dy: 0.5)] {
            menu.coordinate(withNormalizedOffset: offset).tap()
            let report = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT label BEGINSWITH %@", "Report ", "Report or block")).firstMatch
            XCTAssertTrue(report.waitForExistence(timeout: 5), "Tapping at \(offset) opens the menu")
            // Close it by tapping the sheet's title area.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.12)).tap()
            XCTAssertTrue(report.waitForNonExistence(timeout: 5))
        }
    }
}
