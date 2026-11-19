import XCTest

/// "@" in the chat composer lists the game's people; picking one writes "@Maya C. " and sends the mention.
final class ChatMentionUITests: XCTestCase {
    @MainActor func testTypingAtPickingAMemberAndSending() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-liveAuth", "NO", "-mockLocation", "YES", "-screen", "chat",
                               "-notificationSettingsDelay", "60",
                               "-appLanguage", "system", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        // The mock chat has a message from Sam, the host, mentioning you; VoiceOver reads it as written.
        let mention = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Sam L., host: Welcome @Emilio G.!")).firstMatch
        XCTAssertTrue(mention.waitForExistence(timeout: 20), app.debugDescription)

        let composer = app.descendants(matching: .any).matching(identifier: "chat-composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("Thanks @")
        let suggestions = app.descendants(matching: .any).matching(identifier: "chat-mention-suggestions").firstMatch
        XCTAssertTrue(suggestions.waitForExistence(timeout: 5), "Typing @ lists the people to mention")
        XCTAssertTrue(app.buttons["Sam L."].exists, "The host is listed")
        XCTAssertFalse(app.buttons["Emilio G."].exists, "You are not")

        composer.typeText("Ma")
        let maya = app.buttons["Maya C."]
        XCTAssertTrue(maya.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Sam L."].exists, "Typing the first name filters the list")
        maya.tap()
        XCTAssertTrue((composer.value as? String)?.hasSuffix("Thanks @Maya C. ") == true, "\(composer.value ?? "")")
        XCTAssertFalse(suggestions.exists, "The list closes once a name is picked")

        composer.typeText("on it")
        app.buttons["Send"].tap()
        let sent = app.staticTexts["You: Thanks @Maya C. on it"]
        XCTAssertTrue(sent.waitForExistence(timeout: 5), app.debugDescription)
    }
}
