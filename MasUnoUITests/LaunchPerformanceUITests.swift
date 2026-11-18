import XCTest

/// Launch time on mocks, to compare before and after changes that could move it (OPT-02, OPT-12).
/// Run it locally; CI skips it because shared runners make the numbers meaningless.
final class LaunchPerformanceUITests: XCTestCase {
    @MainActor func testLaunchPerformance() {
        let app = XCUIApplication()
        app.launchArguments = ["-liveAuth", "NO", "-mockLocation", "YES",
                               "-appLanguage", "system", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        measure(metrics: [XCTApplicationLaunchMetric()]) { app.launch() }
        app.terminate()
    }
}
