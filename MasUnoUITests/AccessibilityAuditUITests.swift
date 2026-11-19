import XCTest

/// Apple's accessibility audit (A11Y-29) on each design-review screen (`-screen …`), at the default
/// text size and the largest accessibility size, plus a contrast pass in dark mode. Anything the audit
/// finds fails the test unless it's in `AuditKnownIssue.all`. CI runs this on iOS 26.5 only.
final class AccessibilityAuditUITests: XCTestCase {
    /// Screens that must pass the audit, grouped so one test stays well under CI's per-test limit and
    /// each group reports its own failures. Add a screen when it's fixed; never remove one.
    private enum Screens {
        static let map = ["map", "popup", "search", "filter", "saved", "all-games"]
        static let detail = ["detail-open", "detail-in", "detail-full", "detail-hosting", "who", "report"]
        static let form = ["add", "form-error", "picker"]
        static let me = ["chat", "me", "me-hosting", "profile", "invites", "settings", "blocked"]
        static let onboarding = ["onboarding-signup", "onboarding-signin", "onboarding-pending",
                                 "onboarding-about", "onboarding-guidelines"]
    }

    @MainActor func testMapScreens() { audit(Screens.map) }
    @MainActor func testDetailScreens() { audit(Screens.detail) }
    @MainActor func testFormScreens() { audit(Screens.form) }
    @MainActor func testMeScreens() { audit(Screens.me) }
    @MainActor func testOnboardingScreens() { audit(Screens.onboarding) }

    @MainActor func testMapScreensAtLargestText() { audit(Screens.map, size: .largest) }
    @MainActor func testDetailScreensAtLargestText() { audit(Screens.detail, size: .largest) }
    @MainActor func testFormScreensAtLargestText() { audit(Screens.form, size: .largest) }
    @MainActor func testMeScreensAtLargestText() { audit(Screens.me, size: .largest) }
    @MainActor func testOnboardingScreensAtLargestText() { audit(Screens.onboarding, size: .largest) }

    /// Contrast only, at the default size, with the app forced dark (`-appearance dark`). Its known
    /// issues are listed under the screen's name with a "dark-" in front, since the light list's
    /// reasons (ratios, glass) don't carry over.
    @MainActor func testScreensInDarkMode() {
        audit(Screens.map + Screens.detail + Screens.form + Screens.me + Screens.onboarding, dark: true)
    }

    /// Audits each screen in turn. A finding on one screen is recorded and the rest still run.
    @MainActor
    private func audit(_ screens: [String], size: AuditKnownIssue.Size = .standard, dark: Bool = false) {
        continueAfterFailure = true
        // Text-size checks enlarge the text, which can move or swap elements (stacked buttons at
        // accessibility sizes); run them after the others so contrast and the rest see a still screen.
        let textSize: XCUIAccessibilityAuditType = [.dynamicType, .textClipped]
        let passes: [XCUIAccessibilityAuditType] = dark
            ? [.contrast]
            : size == .largest ? [[.dynamicType, .textClipped, .hitRegion]] : [.all.subtracting(textSize), textSize]
        var used = Set<Int>()
        // What a screen's findings are listed under.
        let listed = { (screen: String) in dark ? "dark-\(screen)" : screen }
        for launched in screens {
            let screen = listed(launched)
            var app = launch(launched, size: size, dark: dark)
            XCTContext.runActivity(named: "Audit \(screen)\(size == .largest ? " at AX5" : "")") { _ in
                do {
                    var unknown = Set<String>()
                    try Self.audit(app, passes) { issue in
                        if let index = AuditKnownIssue.match(issue, on: screen, size: size) {
                            used.insert(index)
                        } else {
                            unknown.insert(Self.key(issue))
                        }
                        return true
                    }
                    guard !unknown.isEmpty else { return }
                    // An app that's slow to settle can miss the audit's own text-size change and report
                    // every label. Audit again; only what comes up both times is suspect.
                    Thread.sleep(forTimeInterval: 2)
                    var repeated = Set<String>()
                    try Self.audit(app, passes) { issue in
                        let key = Self.key(issue)
                        if AuditKnownIssue.match(issue, on: screen, size: size) == nil, unknown.contains(key) {
                            repeated.insert(key)
                        }
                        return true
                    }
                    guard !repeated.isEmpty else { return }
                    // On a simulator that's been busy for a while, a known finding's element can be gone
                    // by the time its label is read, so it arrives unnamed. A fresh launch settles that;
                    // whatever isn't listed then fails.
                    app.terminate()
                    app = launch(launched, size: size, dark: dark)
                    try Self.audit(app, passes) { issue in
                        if let index = AuditKnownIssue.match(issue, on: screen, size: size) {
                            used.insert(index)
                            return true
                        }
                        Self.log(issue, on: screen, size: size)
                        return false
                    }
                } catch {
                    XCTFail("Couldn't audit \(screen): \(error)")
                }
            }
            app.terminate()
        }
        // Entries that didn't come up may be fixed: a hint for shrinking the list, not a failure,
        // since some findings depend on timing or Apple Maps content.
        for (index, entry) in AuditKnownIssue.all.enumerated() where !used.contains(index) && entry.applies(to: size) {
            let here = entry.screens.filter(screens.map(listed).contains)
            guard !here.isEmpty else { continue }
            print("AUDIT-UNSEEN \(here) .\(size) .\(AuditKnownIssue.name(of: entry.type)) \"\(entry.element)\": \(entry.reason)")
        }
    }

    /// Opens `screen` on mocks and waits for its sheet or popup, which open a moment after launch.
    @MainActor
    private func launch(_ screen: String, size: AuditKnownIssue.Size, dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-liveAuth", "NO", "-mockLocation", "YES", "-screen", screen,
                               "-notificationSettingsDelay", "60",
                               "-appLanguage", "system", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-appearance", dark ? "dark" : "system"]
        if size == .largest {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 20)
        Thread.sleep(forTimeInterval: 4)
        return app
    }

    @MainActor
    private static func audit(_ app: XCUIApplication, _ passes: [XCUIAccessibilityAuditType],
                              _ handler: @escaping (XCUIAccessibilityAuditIssue) throws -> Bool) throws {
        for types in passes {
            try app.performAccessibilityAudit(for: types, handler)
        }
    }

    @MainActor
    private static func key(_ issue: XCUIAccessibilityAuditIssue) -> String {
        "\(issue.auditType.rawValue) \(AuditKnownIssue.label(of: issue))"
    }

    /// Prints a new finding in the shape of an `AuditKnownIssue` line, for adding it on purpose.
    @MainActor
    private static func log(_ issue: XCUIAccessibilityAuditIssue, on screen: String, size: AuditKnownIssue.Size) {
        let label = AuditKnownIssue.label(of: issue)
        print("AUDIT-ISSUE .init([\"\(screen)\"], .\(size), .\(AuditKnownIssue.name(of: issue.auditType)), \"\(label)\", \"\(issue.compactDescription)\"),")
    }
}
