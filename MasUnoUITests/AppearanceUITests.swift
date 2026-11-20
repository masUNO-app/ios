import XCTest

/// Settings › Appearance: System, Light or Dark, applied at once and kept across launches.
final class AppearanceUITests: XCTestCase {
    @MainActor private func launch(_ app: XCUIApplication, appearance: String? = nil) {
        app.launchArguments = ["-liveAuth", "NO", "-mockLocation", "YES", "-screen", "settings",
                               "-appLanguage", "system", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let appearance { app.launchArguments += ["-appearance", appearance] }
        app.launch()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 20))
    }

    @MainActor private func select(_ option: String, in app: XCUIApplication) {
        app.buttons["appearance-picker"].tap()
        app.buttons[option].tap()
    }

    /// The screen's background, from a point in the left margin halfway down.
    @MainActor private func backgroundIsDark(_ app: XCUIApplication) -> Bool {
        guard let image = app.screenshot().image.cgImage,
              let point = image.cropping(to: CGRect(x: image.width / 50, y: image.height / 2, width: 1, height: 1)),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.draw(point, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        return (Int(data[0]) + Int(data[1]) + Int(data[2])) / 3 < 80
    }

    /// Waits for the screen to settle on light or dark after a change.
    @MainActor private func waitFor(dark: Bool, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date.now.addingTimeInterval(5)
        while backgroundIsDark(app) != dark, Date.now < deadline { RunLoop.current.run(until: .now + 0.3) }
        XCTAssertEqual(backgroundIsDark(app), dark, dark ? "Expected dark mode" : "Expected light mode", file: file, line: line)
    }

    @MainActor func testChoiceAppliesImmediatelyAndSurvivesRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // The simulator is light, so System starts light.
        launch(app, appearance: "system")
        waitFor(dark: false, in: app)
        select("Dark", in: app)
        waitFor(dark: true, in: app)
        app.terminate()

        // No launch argument this time: the stored choice.
        launch(app)
        // Puts System back for the other tests, whatever happens below.
        defer {
            if app.buttons["appearance-picker"].exists { select("System", in: app) }
            app.terminate()
        }
        waitFor(dark: true, in: app)
        select("Light", in: app)
        waitFor(dark: false, in: app)
        select("System", in: app)
        waitFor(dark: false, in: app)
    }

    @MainActor func testLaunchArgumentForcesDark() {
        let app = XCUIApplication()
        launch(app, appearance: "dark")
        defer { app.terminate() }
        waitFor(dark: true, in: app)
    }
}
