import XCTest

final class LanguageUITests: XCTestCase {
    @MainActor private func launch(languages: String, preference: String? = "system", screen: String = "settings") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-liveAuth", "NO", "-mockLocation", "YES", "-screen", screen,
                               "-AppleLanguages", languages, "-AppleLocale", "en_US"]
        if let preference { app.launchArguments += ["-appLanguage", preference] }
        app.launch()
        return app
    }

    @MainActor func testSpanishGameDetailsLocalizeSportsAndFormattedCopy() {
        let app = launch(languages: "(es-MX)", screen: "detail-open")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["detail-count-me-in"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Básquetbol")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "Hoy", "Mañana")).firstMatch.exists)
    }

    @MainActor private func select(_ option: String, in app: XCUIApplication) {
        app.buttons["app-language-picker"].tap()
        app.buttons[option].tap()
    }

    @MainActor func testSpanishDeviceLocalizesSettingsAndNotificationPreferences() {
        let app = launch(languages: "(es-MX)")
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Idioma"].exists)
        XCTAssertTrue(app.switches["Mensajes del grupo"].waitForExistence(timeout: 5))
        select("English", in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Group chat messages"].exists)
        select("Device language", in: app)
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 5))
    }

    @MainActor func testUnsupportedPrimaryLanguageUsesEnglishEvenWithSpanishSecond() {
        let app = launch(languages: "(fr-FR, es-MX)")
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Language"].exists)
    }

    @MainActor func testOverrideAppliesImmediatelyAndSurvivesRelaunch() {
        let app = launch(languages: "(en-US)")
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 20))
        select("Español", in: app)
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Mensajes del grupo"].exists)
        app.terminate()
        app.launchArguments = ["-liveAuth", "NO", "-mockLocation", "YES", "-screen", "settings",
                               "-AppleLanguages", "(en-US)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20))
        select("English", in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        select("Device language", in: app)
    }
}
