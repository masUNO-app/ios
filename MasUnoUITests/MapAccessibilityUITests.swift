import XCTest

/// What VoiceOver gets on the map (A11Y-02): pins that say more than their title, group pins that
/// name their sports and open their list, and the List games sheet. Custom actions and focus aren't
/// visible to XCUITest, so `-screen all-games` opens the sheet that "List games" opens.
final class MapAccessibilityUITests: XCTestCase {
    @MainActor
    private func launch(screen: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-liveAuth", "NO", "-mockLocation", "YES", "-screen", screen,
            "-notificationSettingsDelay", "60",
            "-appLanguage", "system", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        return app
    }

    @MainActor
    func testPinsReadTheirTagRoomAndTime() {
        let app = launch(screen: "map")
        defer { app.terminate() }

        let pin = app.buttons["Basketball: After-work hoops"]
        XCTAssertTrue(pin.waitForExistence(timeout: 20))
        let value = pin.value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("Soon, Room for 4 more, Today, "), value)
        XCTAssertTrue(value.contains(", starts in "), value)
        XCTAssertFalse(value.contains("·"), value)
        XCTAssertFalse(pin.isSelected)
    }

    @MainActor
    func testOpenPopupMarksItsPinSelected() {
        let app = launch(screen: "popup")
        defer { app.terminate() }

        let summary = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", "After-work hoops, Basketball")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Basketball: After-work hoops"].isSelected)
    }

    @MainActor
    func testGroupPinNamesItsSportsAndListsThem() {
        let app = launch(screen: "groups")
        defer { app.terminate() }

        // `-screen groups` zooms out until every game shares one pin.
        let group = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "games here")).firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 20))
        let value = group.value as? String ?? ""
        XCTAssertTrue(value.contains("Basketball") && value.contains(" and "), value)

        group.tap()
        XCTAssertTrue(app.staticTexts["Close enough to share a pin. Zoom in to see each one."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testListGamesSheetListsEveryGameOnTheMap() {
        let app = launch(screen: "all-games")
        defer { app.terminate() }

        let chip = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "games nearby")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 20))
        // Titled like the chip, without the group pin's line.
        XCTAssertTrue(app.staticTexts[chip.label].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Close enough to share a pin. Zoom in to see each one."].exists)
        let count = Int(chip.label.split(separator: " ").first ?? "") ?? 0
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "room for"))
        XCTAssertEqual(rows.count, count)

        // Opens the game: the sheet closes and the back button names the map.
        rows.firstMatch.tap()
        XCTAssertTrue(app.navigationBars.buttons["Map"].waitForExistence(timeout: 10))
    }
}
