import XCTest

/// Apple's accessibility audit (A11Y-29) on each design-review screen (`-screen …`), at the default
/// text size and the largest accessibility size. Anything the audit finds fails the test unless it's
/// in `AuditKnownIssue.all`. CI runs this on iOS 26.5 only.
final class AccessibilityAuditUITests: XCTestCase {
    /// Screens that must pass the audit, grouped so one test stays well under CI's per-test limit and
    /// each group reports its own failures. Add a screen when it's fixed; never remove one.
    private enum Screens {
        static let map = ["map", "popup", "search", "filter", "saved"]
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

    /// Audits each screen in turn. A finding on one screen is recorded and the rest still run.
    @MainActor
    private func audit(_ screens: [String], size: AuditKnownIssue.Size = .standard) {
        continueAfterFailure = true
        let types: XCUIAccessibilityAuditType = size == .largest ? [.dynamicType, .textClipped, .hitRegion] : .all
        var used = Set<Int>()
        for screen in screens {
            let app = XCUIApplication()
            app.launchArguments = ["-liveAuth", "NO", "-mockLocation", "YES", "-screen", screen,
                                   "-notificationSettingsDelay", "60",
                                   "-appLanguage", "system", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            if size == .largest {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            app.launch()
            // Debug screens open their sheet or popup a moment after launch; audit once they've settled.
            _ = app.wait(for: .runningForeground, timeout: 20)
            Thread.sleep(forTimeInterval: 4)
            XCTContext.runActivity(named: "Audit \(screen)\(size == .largest ? " at AX5" : "")") { _ in
                do {
                    var unknown = Set<String>()
                    try app.performAccessibilityAudit(for: types) { issue in
                        if let index = AuditKnownIssue.match(issue, on: screen, size: size) {
                            used.insert(index)
                        } else {
                            unknown.insert(Self.key(issue))
                        }
                        return true
                    }
                    guard !unknown.isEmpty else { return }
                    // An app that's slow to settle can miss the audit's own text-size change and report
                    // every label. Audit again; only what comes up both times fails.
                    Thread.sleep(forTimeInterval: 2)
                    try app.performAccessibilityAudit(for: types) { issue in
                        guard AuditKnownIssue.match(issue, on: screen, size: size) == nil,
                              unknown.contains(Self.key(issue)) else { return true }
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
            let here = entry.screens.filter(screens.contains)
            guard !here.isEmpty else { continue }
            print("AUDIT-UNSEEN \(here) .\(size) .\(AuditKnownIssue.name(of: entry.type)) \"\(entry.element)\": \(entry.reason)")
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
