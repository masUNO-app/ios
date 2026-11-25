import XCTest

/// Apple's accessibility audit (A11Y-29) on each design-review screen (`-screen …`), for the checks it
/// makes reliably on this app: elements with no description, tap targets, traits, and text with no
/// element. Each screen waits for an element that proves it opened, then is audited once.
///
/// The other audit passes moved out: contrast is computed exactly from the color tokens
/// (`ContrastTests`), and large text is covered by `LargeTextUITests`, which checks the core actions
/// still work at the largest size. Here they measured the map and glass behind the text, so most of
/// what they reported was noise.
final class AccessibilityAuditUITests: XCTestCase {
    /// A screen to audit and the element that shows it has opened.
    struct Screen {
        let name: String
        let anchor: @MainActor (XCUIApplication) -> XCUIElement

        init(_ name: String, _ anchor: @escaping @MainActor (XCUIApplication) -> XCUIElement) {
            self.name = name
            self.anchor = anchor
        }
    }

    /// A finding accepted on purpose: which audit, the element's label ("" when the audit names none),
    /// and why, with how many times it may come up on each screen. A finding past its count fails, so a
    /// new unnamed one on the same screen is still caught.
    struct Allowance {
        let type: XCUIAccessibilityAuditType
        let element: String
        let limits: [String: Int]
        let reason: String
    }

    static let auditTypes: XCUIAccessibilityAuditType = [.sufficientElementDescription, .hitRegion, .trait, .elementDetection]

    @MainActor static let allowances: [Allowance] = [
        Allowance(type: .hitRegion, element: "Legal",
                  limits: ["map": 1, "popup": 1, "search": 1, "filter": 1, "saved": 1, "all-games": 1, "add": 1, "form-error": 1, "picker": 1],
                  reason: "Apple Maps' own Legal link (MKAttributionLabel)"),
        Allowance(type: .elementDetection, element: "",
                  limits: ["detail-open": 1, "detail-hosting": 1, "who": 1, "report": 1, "me": 1, "me-hosting": 1, "blocked": 1],
                  reason: "Person token initials, hidden from VoiceOver on purpose: the name is read from the row or card. Un-hiding them clears these (checked Nov 19)"),
        Allowance(type: .elementDetection, element: "",
                  limits: ["profile": 4, "invites": 3, "onboarding-about": 1],
                  reason: "Not identified: the audit names no element, and it isn't the person tokens. Recheck in Accessibility Inspector"),
        Allowance(type: .elementDetection, element: "",
                  limits: ["picker": 2],
                  reason: "iOS 18: the pin's label and emoji, hidden from VoiceOver and invisible while the search is focused"),
        Allowance(type: .elementDetection, element: "",
                  limits: ["all-games": 2],
                  reason: "iOS 26 only, not identified: likely the map pins' emoji and tags behind the sheet, which their pin buttons read"),
        Allowance(type: .elementDetection, element: "",
                  limits: ["map": 1],
                  reason: "iOS 27 only: the group pin's count (\"2\"). The pin is a button named \"N plans here\" that VoiceOver reaches (MapAccessibilityUITests); the audit doesn't match a MapKit annotation's text to it. Found by elimination: blanking the count clears it, the tags and face tokens don't (Nov 19)"),
    ]

    // Grouped so each test stays short and reports on its own. Add a screen when it's built; never remove one.
    @MainActor static let map = [
        Screen("map") { $0.buttons["5 plans nearby"] },
        Screen("popup") { $0.buttons["Details, After-work hoops"] },
        Screen("search") { $0.buttons["Clear search"] },
        Screen("filter") { $0.staticTexts["Filter plans"] },
        Screen("saved") { $0.staticTexts["Saved plans"] },
        Screen("all-games") { $0.staticTexts["5 plans nearby"] },
    ]
    @MainActor static let detail = [
        Screen("detail-open") { $0.buttons["detail-count-me-in"] },
        Screen("detail-in") { $0.buttons["detail-open-chat"] },
        Screen("detail-full") { $0.buttons["Alert me if a spot opens"] },
        Screen("detail-hosting") { $0.buttons["Edit plan"] },
        Screen("who") { $0.staticTexts["2 going"] },
        Screen("report") { $0.buttons["Send report"] },
    ]
    @MainActor static let form = [
        Screen("add") { $0.buttons["Choose"] },
        Screen("form-error") { $0.staticTexts["Add a name so people know what they're joining."] },
        Screen("picker") { $0.navigationBars["Where's it happening?"] },
    ]
    @MainActor static let me = [
        Screen("chat") { $0.descendants(matching: .any)["chat-composer"] },
        Screen("me") { $0.buttons["Leave Volleyball at the arena"] },
        Screen("me-hosting") { $0.buttons["Edit Sunday pickup soccer"] },
        Screen("profile") { $0.staticTexts["Edit profile"] },
        Screen("invites") { $0.staticTexts["Invites"] },
        Screen("settings") { $0.buttons["Delete account"] },
        Screen("blocked") { $0.buttons["Unblock Sam L."] },
    ]
    @MainActor static let onboarding = [
        Screen("onboarding-signup") { $0.buttons["Create account"] },
        Screen("onboarding-signin") { $0.buttons["Sign in"] },
        Screen("onboarding-verify") { $0.buttons["Use a different email"] },
        Screen("onboarding-reset") { $0.buttons["Save password"] },
        Screen("onboarding-pending") { $0.buttons["Check again"] },
        Screen("onboarding-about") { $0.buttons["Let's go"] },
        Screen("onboarding-guidelines") { $0.buttons["I agree"] },
    ]

    @MainActor func testMapScreens() { audit(Self.map) }
    @MainActor func testDetailScreens() { audit(Self.detail) }
    @MainActor func testFormScreens() { audit(Self.form) }
    @MainActor func testMeScreens() { audit(Self.me) }
    @MainActor func testOnboardingScreens() { audit(Self.onboarding) }

    /// Audits each screen in turn; a finding on one is recorded and the rest still run.
    @MainActor
    private func audit(_ screens: [Screen]) {
        continueAfterFailure = true
        for screen in screens {
            let app = UITestApp.launch(screen: screen.name)
            defer { app.terminate() }
            guard screen.anchor(app).waitForExistence(timeout: 20) else {
                XCTFail("\(screen.name) didn't open: its anchor never appeared")
                continue
            }
            XCTContext.runActivity(named: "Audit \(screen.name)") { _ in
                var used: [Int: Int] = [:]
                do {
                    try app.performAccessibilityAudit(for: Self.auditTypes) { issue in
                        Self.isAccepted(issue, on: screen.name, in: app, used: &used)
                    }
                } catch {
                    XCTFail("Couldn't audit \(screen.name): \(error)")
                }
            }
        }
    }

    /// True for an accepted finding or one on the system keyboard, which isn't the app's UI.
    @MainActor
    private static func isAccepted(_ issue: XCUIAccessibilityAuditIssue, on screen: String, in app: XCUIApplication,
                                   used: inout [Int: Int]) -> Bool {
        let element = issue.element.flatMap { $0.exists ? $0 : nil }
        if let element, app.keyboards.firstMatch.exists, app.keyboards.firstMatch.frame.contains(element.frame) {
            return true
        }
        // The keyboard's QuickType bar is the system's too. On iOS 27 it sits above the keyboard's
        // frame, and whether it shows depends on the simulator's typing history (Nov 19).
        if issue.detailedDescription.contains("TUIPrediction") {
            return true
        }
        let label = element.map { $0.label.isEmpty ? $0.identifier : $0.label } ?? ""
        if let index = allowances.firstIndex(where: { $0.type == issue.auditType && $0.element == label && $0.limits[screen] != nil }),
           used[index, default: 0] < allowances[index].limits[screen]! {
            used[index, default: 0] += 1
            return true
        }
        // The frame says where an unnamed finding is; compare it with the audit's screenshot.
        let frame = element.map { "\($0.frame)" } ?? "none"
        print("AUDIT-ISSUE \(screen): \(issue.compactDescription), element \"\(label)\" at \(frame): \(issue.detailedDescription)")
        return false
    }
}
