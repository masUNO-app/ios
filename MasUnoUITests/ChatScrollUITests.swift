import XCTest

/// Keep the latest conversation visible through keyboard and composer layout changes.
final class ChatScrollUITests: XCTestCase {
    @MainActor private func launchChat() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-liveAuth", "NO", "-mockLocation", "YES", "-screen", "chat-long",
                               "-chatScrollUITest", "YES",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor func testTypingInLongChatKeepsLatestMessagesVisible() {
        let app = launchChat()
        defer { app.terminate() }

        let latest = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Message 60")).firstMatch
        assertVisible(latest, timeout: 20)
        let composer = app.descendants(matching: .any).matching(identifier: "chat-composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5), app.debugDescription)
        composer.tap()
        assertVisible(latest)
        composer.typeText("Checking the chat while I type a longer message that wraps onto multiple lines in the composer.")
        assertVisible(latest)
        XCTAssertLessThanOrEqual(latest.frame.maxY, composer.frame.minY)
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        app.buttons["chat-test-receive"].tap()
        let incoming = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "New live message")).firstMatch
        assertVisible(incoming)
        XCTAssertTrue((composer.value as? String)?.contains("Checking the chat") == true, "A live refresh must retain the draft")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        app.buttons["Send"].tap()
        let sent = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Checking the chat while I type")).firstMatch
        XCTAssertFalse((composer.value as? String)?.contains("Checking the chat") == true)
        assertVisible(sent)
    }

    @MainActor func testReadingOlderMessagesIsPreservedWhileTypingAndReceiving() {
        let app = launchChat()
        defer { app.terminate() }
        let latest = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Message 60")).firstMatch
        assertVisible(latest, timeout: 20)
        app.scrollViews.firstMatch.swipeDown(velocity: .slow)
        XCTAssertFalse(latest.isHittable)
        let messages = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "Message [0-9]+"))
        guard let visible = messages.allElementsBoundByIndex.first(where: \.isHittable) else {
            XCTFail("Expected an older message on screen")
            return
        }
        let anchor = app.staticTexts[visible.label]
        let composer = app.descendants(matching: .any).matching(identifier: "chat-composer").firstMatch
        composer.tap()
        composer.typeText("Replying while reading earlier messages")
        assertVisible(anchor)
        let receive = app.buttons["chat-test-receive"]
        receive.tap()
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "New live message"), object: receive)
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 5), .completed)
        assertVisible(anchor)
        XCTAssertFalse(latest.isHittable, "Receiving must not pull someone away from older messages")

        app.buttons["Send"].tap()
        let sent = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Replying while reading earlier messages")).firstMatch
        XCTAssertFalse((composer.value as? String)?.contains("Replying while reading") == true)
        assertVisible(sent)
    }

    @MainActor private func assertVisible(_ element: XCUIElement, timeout: TimeInterval = 5,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: timeout), .completed,
                       "Latest messages must remain visible while composing", file: file, line: line)
    }
}
