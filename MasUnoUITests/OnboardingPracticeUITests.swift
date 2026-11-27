import XCTest

/// The practice round by tapping, as someone new would (Figma "Onboarding, reimagined", 0R): the
/// spotlit pin and buttons must take taps through the dimmed map.
final class OnboardingPracticeUITests: XCTestCase {
    @MainActor func testJoiningThenHostingAPretendPlan() {
        let app = UITestApp.launch(screen: "onboarding-welcome")
        defer { app.terminate() }

        assertHittable(app.buttons["Show me how it works"], "Welcome opens")
        app.buttons["Show me how it works"].tap()

        assertHittable(app.buttons["Basketball"], "What do you play? lists the sports")
        app.buttons["Basketball"].tap()
        app.buttons["Continue"].tap()

        assertHittable(app.buttons["Start practice round"], "How do you want to start? opens")
        app.buttons["Start practice round"].tap()

        let pin = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Basketball:")).firstMatch
        assertHittable(pin, "The spotlit pin takes a tap")
        pin.tap()

        let countMeIn = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Count me in")).firstMatch
        assertHittable(countMeIn, "The plan's card opens")
        countMeIn.tap()

        assertHittable(app.buttons["Try hosting a plan too"], "You land on the court")
        app.buttons["Try hosting a plan too"].tap()

        assertHittable(app.buttons["Make a plan"], "Make a plan is spotlit")
        app.buttons["Make a plan"].tap()

        assertHittable(app.buttons["Create plan"], "The form opens, filled in")
        app.buttons["Create plan"].tap()

        assertHittable(app.buttons["Keep this plan"], "Your plan is ready")
        app.buttons["Keep this plan"].tap()

        XCTAssertTrue(app.staticTexts["Practice round done"].waitForExistence(timeout: 20), "Make it official says the practice is done")
        XCTAssertTrue(app.buttons["Create account"].exists)
    }
}
