import XCTest

/// An accessibility audit finding accepted for now (A11Y-29): the screens it's on, the text size, the
/// audit, the element, and why. Each later PR deletes the lines it fixes; the ID in the reason says
/// which item should. A finding that isn't listed fails `AccessibilityAuditUITests`.
struct AuditKnownIssue {
    enum Size { case standard, largest, both }

    let screens: [String]
    let size: Size
    let type: XCUIAccessibilityAuditType
    /// The element's label (its identifier when it has none), exactly. "" is an element with neither.
    let element: String
    /// `element` is a regular expression, for labels with times or Apple Maps results in them.
    let isPattern: Bool
    let reason: String

    init(_ screens: [String], _ size: Size, _ type: XCUIAccessibilityAuditType, _ element: String, _ reason: String) {
        self.init(screens: screens, size: size, type: type, element: element, isPattern: false, reason: reason)
    }

    private init(screens: [String], size: Size, type: XCUIAccessibilityAuditType, element: String, isPattern: Bool, reason: String) {
        self.screens = screens
        self.size = size
        self.type = type
        self.element = element
        self.isPattern = isPattern
        self.reason = reason
    }

    static func pattern(_ screens: [String], _ size: Size, _ type: XCUIAccessibilityAuditType, _ element: String, _ reason: String) -> Self {
        .init(screens: screens, size: size, type: type, element: element, isPattern: true, reason: reason)
    }

    func applies(to size: Size) -> Bool { self.size == .both || self.size == size }

    /// The index in `all` of the entry that accepts `issue`, if any.
    @MainActor
    static func match(_ issue: XCUIAccessibilityAuditIssue, on screen: String, size: Size) -> Int? {
        let label = label(of: issue)
        return all.firstIndex { entry in
            entry.screens.contains(screen) && entry.applies(to: size) && entry.type == issue.auditType
                && (entry.isPattern ? label.range(of: entry.element, options: .regularExpression) != nil : label == entry.element)
        }
    }

    /// The element's label, or its identifier when it has none; "" when it's gone or has neither.
    @MainActor
    static func label(of issue: XCUIAccessibilityAuditIssue) -> String {
        guard let element = issue.element, element.exists else { return "" }
        return element.label.isEmpty ? element.identifier : element.label
    }

    static func name(of type: XCUIAccessibilityAuditType) -> String {
        switch type {
        case .contrast: "contrast"
        case .elementDetection: "elementDetection"
        case .hitRegion: "hitRegion"
        case .sufficientElementDescription: "sufficientElementDescription"
        case .dynamicType: "dynamicType"
        case .textClipped: "textClipped"
        case .trait: "trait"
        default: "init(rawValue: \(type.rawValue))"
        }
    }

    static let all: [AuditKnownIssue] = [
        // Found on iOS 26.5 (CI) and 27.2 with the Monterrey fixtures. Sorted by the item that fixes them;
        // the last group stays unless a decision changes.
        .pattern(["picker"], .standard, .dynamicType, #"."#, "A11Y-06: Apple Maps suggestion rows; they wrap at accessibility sizes since PR 12, still reported"),
        .init(["map", "popup", "search"], .both, .dynamicType, "Add game", "A11Y-06: bar text keeps the system's size; a long press shows it big (A11Y-24, PR 12)"),
        .init(["detail-open"], .both, .dynamicType, "After-work hoops", "A11Y-06: bar text keeps the system's size; a long press shows it big (A11Y-24, PR 12)"),
        .init(["detail-hosting"], .standard, .dynamicType, "Edit game", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["who"], .both, .dynamicType, "HOST", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["detail-in"], .standard, .dynamicType, "Invite a friend", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        // The same chat rows, when the audit reports them before their labels load.
        .init(["chat"], .standard, .dynamicType, "", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["chat"], .standard, .dynamicType, "Net's up on the far court. Bring water, it's hot in there.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["detail-in"], .standard, .dynamicType, "Open group chat", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["detail-full"], .both, .dynamicType, "Padel at Distrito Tec", "A11Y-06: bar text keeps the system's size; a long press shows it big (A11Y-24, PR 12)"),
        .init(["chat"], .standard, .dynamicType, "Sam L.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["detail-hosting"], .standard, .dynamicType, "Share game", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["detail-hosting"], .both, .dynamicType, "Sunday pickup soccer", "A11Y-06: bar text keeps the system's size; a long press shows it big (A11Y-24, PR 12)"),
        .init(["detail-in", "chat"], .both, .dynamicType, "Volleyball at the arena", "A11Y-06: bar text keeps the system's size; a long press shows it big (A11Y-24, PR 12)"),
        .pattern(["chat"], .standard, .dynamicType, #"^· \d{1,2}:\d{2}\u202F[AP]M$"#, "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["chat"], .standard, .dynamicType, "· Host", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["chat"], .both, .dynamicType, "🏐 Volleyball · 5 going", "A11Y-06: bar text keeps the system's size; a long press shows it big (A11Y-24, PR 12)"),
        .init(["detail-in", "detail-hosting", "add", "form-error", "picker"], .largest, .textClipped, "", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["add", "form-error", "picker"], .standard, .textClipped, "", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .pattern(["picker"], .standard, .textClipped, #"."#, "A11Y-06: Apple Maps suggestion rows; they wrap at accessibility sizes since PR 12, still reported"),
        .init(["who"], .largest, .textClipped, "2 going", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["who"], .standard, .textClipped, "2 going", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["map", "all-games"], .largest, .textClipped, "5 games nearby", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["map", "all-games"], .standard, .textClipped, "5 games nearby", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["map"], .standard, .contrast, "5 games nearby", "A11Y-19 (PR 15): the 44 pt target's frame takes in 6 pt of map above and below the glass chip; text and glass colors unchanged"),
        .init(["search", "all-games"], .largest, .textClipped, "After-work hoops", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["popup", "search", "all-games"], .standard, .textClipped, "After-work hoops", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["detail-full"], .largest, .textClipped, "Alert me if a spot opens", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["detail-full"], .standard, .textClipped, "Alert me if a spot opens", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["who"], .largest, .textClipped, "Alex R.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["who"], .standard, .textClipped, "Alex R.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["report"], .standard, .textClipped, "Anything else we should know?", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["who"], .standard, .textClipped, "Anything feel off? Tap ••• next to anyone to report or block them. Only the masUNO team sees reports.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["form-error"], .standard, .textClipped, "Av. Eugenio Garza Sada 2501 Sur, Tecnológico, Monterrey, N.L.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["detail-in"], .standard, .textClipped, "Av. Junco de la Vega, Tecnológico, Monterrey, N.L.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter"], .largest, .textClipped, "Basketball", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter", "profile"], .standard, .textClipped, "Basketball", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["popup"], .standard, .textClipped, "Basketball · Hosted by Alex R.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["who"], .largest, .textClipped, "Class of 2027", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["who"], .standard, .textClipped, "Class of 2027", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["profile"], .standard, .textClipped, "Class year", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["add", "form-error"], .standard, .textClipped, "Duration", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["profile"], .largest, .textClipped, "Edit profile", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["profile"], .standard, .textClipped, "Edit profile", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["report"], .standard, .textClipped, "Fake profile or not a student", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter"], .largest, .textClipped, "Filter games", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter"], .standard, .textClipped, "Filter games", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["profile"], .largest, .textClipped, "First name", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["profile"], .standard, .textClipped, "First name", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["add", "form-error"], .largest, .textClipped, "Game name", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["add", "form-error"], .standard, .textClipped, "Game name", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["report"], .standard, .textClipped, "Harassment or hateful language", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter"], .standard, .textClipped, "How far", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["invites"], .largest, .textClipped, "Invites", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["invites"], .standard, .textClipped, "Invites", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["profile"], .largest, .textClipped, "Last name", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["profile"], .standard, .textClipped, "Last name", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["report"], .largest, .textClipped, "Made me feel unsafe", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["report"], .standard, .textClipped, "Made me feel unsafe", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["add", "form-error"], .standard, .textClipped, "Meet-up spot (optional)", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["onboarding-signup"], .standard, .textClipped, "Password", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["invites"], .standard, .textClipped, "Not used yet", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter"], .standard, .textClipped, "Only games in the next hour", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["report"], .largest, .textClipped, "Only the masUNO team sees this.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["report"], .standard, .textClipped, "Only the masUNO team sees this.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["profile"], .standard, .textClipped, "Only you see what you play.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["report"], .standard, .textClipped, "Optional", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["profile"], .largest, .textClipped, "Others see Emilio G. and your class year.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["profile"], .standard, .textClipped, "Others see Emilio G. and your class year.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["all-games"], .largest, .textClipped, "Pickup soccer", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["all-games"], .standard, .textClipped, "Pickup soccer", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["report"], .standard, .textClipped, "Pushed me to share personal info", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["report"], .largest, .textClipped, "Report Alex", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["report"], .standard, .textClipped, "Report Alex", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter"], .standard, .textClipped, "Reset", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["who"], .largest, .textClipped, "Ricardo T.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["who"], .standard, .textClipped, "Ricardo T.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["who"], .standard, .textClipped, "Room for 4 more", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["saved"], .standard, .textClipped, "Room for one more", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["saved"], .largest, .textClipped, "Saved games", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["saved"], .standard, .textClipped, "Saved games", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter"], .standard, .textClipped, "Show 5 games", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter"], .largest, .textClipped, "Show me games that fit.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter"], .standard, .textClipped, "Show me games that fit.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter"], .largest, .textClipped, "Soccer", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter", "profile"], .standard, .textClipped, "Soccer", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["all-games"], .standard, .textClipped, "Sunday pickup soccer", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["report"], .standard, .textClipped, "Something else", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter"], .standard, .textClipped, "Starting soon", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["saved"], .standard, .textClipped, "Tec tennis courts", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter"], .largest, .textClipped, "Tennis", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter", "profile"], .standard, .textClipped, "Tennis", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["all-games"], .standard, .textClipped, "Tennis doubles", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["saved"], .standard, .textClipped, "Tennis · Hosted by Priya S.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["saved"], .largest, .textClipped, "Turn on a spot alert and we'll tell you when a full game opens up.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["saved"], .standard, .textClipped, "Turn on a spot alert and we'll tell you when a full game opens up.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["invites"], .standard, .textClipped, "Used by Priya S.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter"], .largest, .textClipped, "Volleyball", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter", "profile"], .standard, .textClipped, "Volleyball", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["chat"], .largest, .textClipped, "Volleyball at the arena", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["chat", "all-games"], .standard, .textClipped, "Volleyball at the arena", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["me"], .standard, .textClipped, "Volleyball · Hosted by Sam L.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter"], .standard, .textClipped, "When", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["who"], .largest, .textClipped, "Who's going", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["who"], .standard, .textClipped, "Who's going", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .pattern(["search"], .standard, .textClipped, #"^(Today|Tomorrow), \d{1,2}:\d{2}\u202F[AP]M · 0\.2 mi · room for 4$"#, "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        // The List games sheet: the same rows as search results, for every game on the map.
        .pattern(["all-games"], .largest, .textClipped, #"^(Today|Tomorrow), \d{1,2}:\d{2}\u202F[AP]M · \d+\.\d mi · room for \d+$"#, "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .pattern(["all-games"], .standard, .textClipped, #"^(Today|Tomorrow), \d{1,2}:\d{2}\u202F[AP]M · \d+\.\d mi · room for \d+$"#, "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .pattern(["saved", "me"], .standard, .textClipped, #"^(Today|Tomorrow), \d{1,2}:\d{2}\u202F[AP]M · about 1 hour$"#, "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .pattern(["me-hosting"], .standard, .textClipped, #"^(Today|Tomorrow), \d{1,2}:\d{2}\u202F[AP]M · about 1\.5 hours$"#, "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .pattern(["popup"], .standard, .textClipped, #"^(Today|Tomorrow), \d{1,2}:\d{2}\u202F[AP]M · starts in 34 min$"#, "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["invites"], .largest, .textClipped, "masUNO is invite-only for now. Each code lets one friend skip the waitlist.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["invites"], .standard, .textClipped, "masUNO is invite-only for now. Each code lets one friend skip the waitlist.", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["settings"], .standard, .textClipped, "official.masuno.app@gmail.com", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter", "me", "me-hosting"], .largest, .textClipped, "⚽️", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter", "me", "me-hosting", "profile", "onboarding-about"], .standard, .textClipped, "⚽️", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["map", "popup", "filter"], .largest, .textClipped, "🎾", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["map", "popup", "filter", "saved", "me", "me-hosting", "profile", "onboarding-about"], .standard, .textClipped, "🎾", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["map", "popup", "search", "filter", "picker", "me", "me-hosting"], .largest, .textClipped, "🏀", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["map", "popup", "search", "filter", "me", "me-hosting", "profile", "onboarding-about"], .standard, .textClipped, "🏀", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        // The Sport field: read as "Basketball" since PR 13 (A11Y-11).
        .init(["add", "form-error"], .largest, .textClipped, "Basketball", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["add", "form-error"], .standard, .textClipped, "Basketball", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["popup", "filter"], .largest, .textClipped, "🏐", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["popup", "filter", "me", "profile", "onboarding-about"], .standard, .textClipped, "🏐", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["chat"], .largest, .textClipped, "🏐 Volleyball · 5 going", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["chat"], .standard, .textClipped, "🏐 Volleyball · 5 going", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter", "profile", "onboarding-about"], .standard, .textClipped, "🏓", "A11Y-06: still reported after PR 12, though it reads in full in the Large and AX5 screenshots; recheck in Accessibility Inspector"),
        .init(["filter", "me", "me-hosting", "profile", "onboarding-about"], .standard, .contrast, "⚽️", "Sport emoji (a color glyph, not text): hidden from VoiceOver since PR 13, but the audit still checks it"),
        .init(["map", "popup", "filter", "saved", "me", "me-hosting", "profile", "onboarding-about"], .standard, .contrast, "🎾", "Sport emoji (a color glyph, not text): hidden from VoiceOver since PR 13, but the audit still checks it"),
        .init(["map", "popup", "search", "filter", "me", "me-hosting", "profile", "onboarding-about"], .standard, .contrast, "🏀", "Sport emoji (a color glyph, not text): hidden from VoiceOver since PR 13, but the audit still checks it"),
        .init(["popup", "filter", "me", "profile", "onboarding-about"], .standard, .contrast, "🏐", "Sport emoji (a color glyph, not text): hidden from VoiceOver since PR 13, but the audit still checks it"),
        .init(["filter", "saved", "profile", "onboarding-about"], .standard, .contrast, "🏓", "Sport emoji (a color glyph, not text): hidden from VoiceOver since PR 13, but the audit still checks it"),
        .init(["detail-open", "detail-hosting", "me", "me-hosting", "profile", "invites", "blocked"], .standard, .elementDetection, "", "Text with no element: hidden token initials (combined in, their fixed size gets reported instead) and Me behind a half sheet"),
        .init(["settings"], .standard, .contrast, "About", "A11Y-15 (PR 14): ink text, unchanged (13.5:1 on the background, 14.7 on a card computed); the audit's measurement, comes and goes"),
        .init(["me-hosting"], .standard, .contrast, "Add game", "A11Y-15 (PR 14): ink on the mint pill, unchanged (12.8:1 computed); the audit measures the glass edge"),
        .init(["detail-hosting"], .standard, .contrast, "Add to calendar", "A11Y-15 (PR 14): ink on the mint pill, unchanged (12.8:1 computed); the audit measures the glass edge"),
        .init(["detail-in"], .standard, .contrast, "Add to calendar", "A11Y-15 (PR 14): ink on the mint pill, unchanged (12.8:1 computed); the audit measures the glass edge"),
        .init(["detail-full"], .standard, .contrast, "Alert me if a spot opens", "A11Y-15 (PR 14): white on the accent fill, kept by the text-only decision (4.81:1 computed, 5.78 under Increase Contrast); the audit measures the glass highlight"),
        .init(["chat"], .standard, .contrast, "Arena Borregos", "A11Y-15 (PR 14): ink on the glass header card, unchanged (14.7:1 on the card color computed); the audit measures the sport color showing through"),
        .init(["detail-in"], .standard, .contrast, "Av. Junco de la Vega, Tecnológico, Monterrey, N.L.", "A11Y-15 (PR 14): mutedLarge text, kept at default by the plan (4.92:1 on the background, 5.37 on a card computed; 7.1 under Increase Contrast); near the threshold, comes and goes"),
        .init(["detail-full"], .standard, .contrast, "Calle Profr. Moisés Sáenz, Tecnológico, Monterrey, N.L.", "A11Y-15 (PR 14): mutedLarge text, kept at default by the plan (4.92:1 on the background, 5.37 on a card computed; 7.1 under Increase Contrast); near the threshold, comes and goes"),
        .init(["add"], .standard, .contrast, "Come for part of it", "A11Y-15 (PR 14): ink on the mint chip, unchanged (12.8:1 computed); below the fold, so it comes and goes"),
        .init(["add"], .standard, .contrast, "Coming alone is fine", "A11Y-15 (PR 14): ink on the mint chip, unchanged (12.8:1 computed); below the fold, so it comes and goes"),
        .init(["add"], .standard, .contrast, "I have an extra ball", "A11Y-15 (PR 14): ink on the mint chip, unchanged (12.8:1 computed); below the fold, so it comes and goes"),
        .init(["detail-open"], .standard, .contrast, "Count me in", "A11Y-15 (PR 14): white on the accent fill, kept by the text-only decision (4.81:1 computed, 5.78 under Increase Contrast); the audit measures the glass highlight"),
        .init(["onboarding-signin"], .standard, .contrast, "Create an account", "A11Y-15 (PR 14): ink on clear glass, unchanged (13.5:1 on the background computed); the audit measures what shows through"),
        .init(["detail-hosting"], .standard, .contrast, "Edit game", "A11Y-15 (PR 14): ink on the mint pill, unchanged (12.8:1 computed); the audit measures the glass edge"),
        .init(["onboarding-signup"], .standard, .contrast, "I already have an account", "A11Y-15 (PR 14): ink on clear glass, unchanged (13.5:1 on the background computed); the audit measures what shows through"),
        .init(["detail-in"], .standard, .contrast, "Invite a friend", "A11Y-15 (PR 14): ink on the mint pill, unchanged (12.8:1 computed); the audit measures the glass edge"),
        .init(["me", "me-hosting"], .standard, .contrast, "Invite friends", "A11Y-15 (PR 14): ink on clear glass, unchanged (13.5:1 on the background computed); the audit measures what shows through"),
        .init(["chat"], .standard, .contrast, "Maya C.", "A11Y-15 (PR 14): muted text, kept at default by the plan (5.85:1 on the background, 6.38 on a card computed; 8.0 under Increase Contrast); the audit's measurement, comes and goes"),
        .init(["detail-open"], .standard, .contrast, "Meet by the north court bleachers", "A11Y-15 (PR 14): mutedLarge text, kept at default by the plan (4.92:1 on the background, 5.37 on a card computed; 7.1 under Increase Contrast); near the threshold, comes and goes"),
        .init(["settings"], .standard, .contrast, "Notifications", "A11Y-15 (PR 14): ink text, unchanged (13.5:1 on the background, 14.7 on a card computed); the audit's measurement, comes and goes"),
        .init(["detail-in"], .standard, .contrast, "Open group chat", "A11Y-15 (PR 14): white on the accent fill, kept by the text-only decision (4.81:1 computed, 5.78 under Increase Contrast); the audit measures the glass highlight"),
        .init(["detail-open", "detail-full"], .standard, .contrast, "Open in Maps", "A11Y-15 (PR 14): ink on the mint pill, unchanged (12.8:1 computed); the audit measures the glass edge"),
        .init(["saved"], .standard, .contrast, "Padel · Hosted by Nina C.", "A11Y-15 (PR 14): ink on the sport color, unchanged (5.60–9.64:1 computed); the audit measures the card's glass"),
        .init(["settings"], .standard, .contrast, "Privacy & safety", "A11Y-15 (PR 14): ink text, unchanged (13.5:1 on the background, 14.7 on a card computed); the audit's measurement, comes and goes"),
        .init(["filter"], .standard, .contrast, "Reset", "A11Y-15 (PR 14): ink on clear glass, unchanged (13.5:1 on the background computed); the audit measures what shows through"),
        .init(["chat"], .standard, .contrast, "Sam L.", "A11Y-15 (PR 14): muted text, kept at default by the plan (5.85:1 on the background, 6.38 on a card computed; 8.0 under Increase Contrast); the audit's measurement, comes and goes"),
        .init(["chat"], .standard, .contrast, "Today", "A11Y-15 (PR 14): muted day pill, kept at default by the plan (5.24:1 on the separator computed; 7.2 under Increase Contrast); near the threshold, so it comes and goes"),
        .init(["profile"], .standard, .contrast, "Save", "A11Y-15 (PR 14): white on the accent fill, kept by the text-only decision (4.81:1 computed, 5.78 under Increase Contrast); the audit measures the glass highlight"),
        .init(["picker"], .standard, .contrast, "Search, or drag the map under the pin.", "A11Y-15 (PR 14): muted text, kept at default by the plan (5.85:1 on the background, 6.38 on a card computed; 8.0 under Increase Contrast); the audit's measurement, comes and goes"),
        .init(["picker"], .standard, .contrast, "Set location", "A11Y-15 (PR 14): white on the accent fill, kept by the text-only decision (4.81:1 computed, 5.78 under Increase Contrast); the audit measures the glass highlight"),
        .init(["detail-hosting"], .standard, .contrast, "Share game", "A11Y-15 (PR 14): white on the accent fill, kept by the text-only decision (4.81:1 computed, 5.78 under Increase Contrast); the audit measures the glass highlight"),
        .init(["filter"], .standard, .contrast, "Show 5 games", "A11Y-15 (PR 14): white on the accent fill, kept by the text-only decision (4.81:1 computed, 5.78 under Increase Contrast); the audit measures the glass highlight"),
        .init(["settings", "onboarding-pending"], .standard, .contrast, "Sign out", "A11Y-15 (PR 14): red (Settings) or ink (pending) on clear glass, unchanged (5.05 and 13.5:1 on the background computed); the audit measures what shows through"),
        .init(["onboarding-pending"], .standard, .contrast, "Use invite code", "A11Y-15 (PR 14): ink on the mint pill, unchanged (12.8:1 computed); the audit measures the glass edge"),
        .init(["picker"], .standard, .contrast, "Use my current location", "A11Y-15 (PR 14): ink text, unchanged (13.5:1 on the background, 14.7 on a card computed); the audit's measurement, comes and goes"),
        .init(["onboarding-pending"], .standard, .contrast, "Want a heads-up when you're in?", "A11Y-15 (PR 14): white on the accent fill, kept by the text-only decision (4.81:1 computed, 5.78 under Increase Contrast); the audit measures the glass highlight"),
        .init(["settings"], .standard, .contrast, "What everyone agrees to", "A11Y-15 (PR 14): muted text, kept at default by the plan (5.85:1 on the background, 6.38 on a card computed; 8.0 under Increase Contrast); the audit's measurement, comes and goes"),
        .pattern(["chat"], .standard, .contrast, #"^(Today|Tomorrow) · \d{1,2}:\d{2}\u202F[AP]M$"#, "A11Y-15 (PR 14): ink on the glass header card, unchanged (14.7:1 on the card color computed); the audit measures the sport color showing through"),
        .pattern(["settings"], .standard, .contrast, #"^\d+\.\d+ \(\d+\)$"#, "A11Y-15 (PR 14): muted text, kept at default by the plan (5.85:1 on the background, 6.38 on a card computed; 8.0 under Increase Contrast); the audit's measurement, comes and goes"),
        .pattern(["chat"], .standard, .contrast, #"^· \d{1,2}:\d{2}\u202F[AP]M$"#, "A11Y-15 (PR 14): muted text, kept at default by the plan (5.85:1 on the background, 6.38 on a card computed; 8.0 under Increase Contrast); the audit's measurement, comes and goes"),
        .init(["chat"], .standard, .contrast, "· Host", "A11Y-15 (PR 14): muted text, kept at default by the plan (5.85:1 on the background, 6.38 on a card computed; 8.0 under Increase Contrast); the audit's measurement, comes and goes"),
        .init(["chat"], .standard, .contrast, "", "A11Y-16 (PR 14): unlabeled shape, not a color PR 14 changes; unseen before and after PR 14 on the Nov 19 runs, likely time-of-day dependent"),
        .init(["picker"], .standard, .contrast, "Drag the map to adjust", "A11Y-16 (PR 14): over map tiles, so it comes and goes; not a color PR 14 changes"),
        .init(["picker"], .standard, .contrast, "🏀", "A11Y-16 (PR 14): over map tiles, so it comes and goes; not a color PR 14 changes"),
        .init(["detail-open", "detail-in", "detail-hosting", "me"], .standard, .contrast, "+1", "A11Y-16 (PR 14): ink on the \"+1\" token's white over the court or a card's sport color, kept at 70% by default (solid under Increase Contrast since PR 14); the audit measures the dashed ring"),
        .init(["chat"], .standard, .contrast, "+2", "A11Y-16 (PR 14): ink on the \"+N\" bubble, unchanged (12.1:1 on the separator computed); the audit measures the white ring around it"),
        .init(["popup"], .standard, .contrast, "2", "A11Y-16 (PR 14): white count on the group pin, unchanged (8.89:1 computed); the audit measures the map behind the pin"),
        .init(["map", "popup", "search"], .standard, .contrast, "AR", "A11Y-16 (PR 14): ink initials on a person color, unchanged (6.51–10.43:1 computed); the audit measures the white ring and what's behind the token"),
        .init(["map", "popup", "saved"], .standard, .contrast, "DM", "A11Y-16 (PR 14): ink initials on a person color, unchanged (6.51–10.43:1 computed); the audit measures the white ring and what's behind the token"),
        .init(["search"], .standard, .contrast, "EG", "A11Y-16 (PR 14): ink initials on a person color, unchanged (6.51–10.43:1 computed); the audit measures the white ring and what's behind the token"),
        .init(["popup", "chat"], .standard, .contrast, "MC", "A11Y-16 (PR 14): ink initials on a person color, unchanged (6.51–10.43:1 computed); the audit measures the white ring and what's behind the token"),
        .init(["popup", "chat", "me"], .standard, .contrast, "NC", "A11Y-16 (PR 14): ink initials on a person color, unchanged (6.51–10.43:1 computed); the audit measures the white ring and what's behind the token"),
        .init(["map", "popup", "saved", "detail-in"], .standard, .contrast, "PS", "A11Y-16 (PR 14): ink initials on a person color, unchanged (6.51–10.43:1 computed); the audit measures the white ring and what's behind the token"),
        .init(["map", "popup", "search"], .standard, .contrast, "RT", "A11Y-16 (PR 14): ink initials on a person color, unchanged (6.51–10.43:1 computed); the audit measures the white ring and what's behind the token"),
        .init(["map", "popup", "saved", "chat"], .standard, .contrast, "SL", "A11Y-16 (PR 14): ink initials on a person color, unchanged (6.51–10.43:1 computed); the audit measures the white ring and what's behind the token"),
        .init(["popup", "search"], .standard, .contrast, "Soon", "A11Y-16 (PR 14): ink on the card-white tag, unchanged (14.7:1 computed); the audit measures the pin and map behind it"),
        .init(["map", "popup", "search", "picker"], .both, .hitRegion, "Legal", "Apple Maps' own Legal link"),
        .init(["map"], .standard, .elementDetection, "", "MapKit's street and place labels (no element); comes and goes with tile loading"),
        .init(["onboarding-about"], .standard, .elementDetection, "", "A11Y-04: First/Last name captions are hidden because they name the fields below them"),
        .init(["detail-open", "detail-in", "detail-hosting"], .both, .dynamicType, "+1", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["popup", "saved", "chat", "me", "me-hosting"], .standard, .dynamicType, "+1", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["chat"], .both, .dynamicType, "+2", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["map", "popup"], .both, .dynamicType, "2", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["map", "popup", "search", "detail-open", "detail-hosting", "who"], .both, .dynamicType, "AR", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["me-hosting"], .standard, .dynamicType, "AR", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["detail-open", "detail-hosting"], .both, .dynamicType, "Alex", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["map", "popup", "detail-hosting"], .both, .dynamicType, "DM", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["saved", "me-hosting"], .standard, .dynamicType, "DM", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["detail-hosting"], .both, .dynamicType, "Diego", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["map", "popup", "search"], .both, .dynamicType, "EG", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["me-hosting"], .standard, .dynamicType, "EG", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["popup", "detail-in", "detail-full", "chat"], .both, .dynamicType, "MC", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["me"], .standard, .dynamicType, "MC", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["detail-in", "detail-full"], .both, .dynamicType, "Maya", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["popup", "detail-in", "detail-full", "chat"], .both, .dynamicType, "NC", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["me"], .standard, .dynamicType, "NC", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["detail-in", "detail-full"], .both, .dynamicType, "Nina", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["map", "popup", "detail-in"], .both, .dynamicType, "PS", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["saved", "me"], .standard, .dynamicType, "PS", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["detail-in"], .both, .dynamicType, "Priya", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["map", "popup", "search", "detail-open", "detail-full", "who"], .both, .dynamicType, "RT", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["detail-open", "detail-full"], .both, .dynamicType, "Ricardo", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["map", "popup", "detail-in", "detail-full", "chat"], .both, .dynamicType, "SL", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["saved", "me"], .standard, .dynamicType, "SL", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["detail-in", "detail-full"], .both, .dynamicType, "Sam", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["map", "popup", "search"], .both, .dynamicType, "Soon", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["detail-in", "detail-hosting"], .both, .dynamicType, "You", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["me"], .standard, .dynamicType, "You", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["me-hosting"], .standard, .dynamicType, "⚽️", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["map", "popup"], .both, .dynamicType, "🎾", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["saved"], .standard, .dynamicType, "🎾", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["map", "popup", "search", "picker"], .both, .dynamicType, "🏀", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["popup"], .both, .dynamicType, "🏐", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        .init(["me"], .standard, .dynamicType, "🏐", "Court tokens, pins and pin tags keep fixed type by design (A11Y-06)"),
        // PR 12 follow-ups: what the caps, full-height sheets and the audit's own scrolling leave.
        .init(["filter"], .largest, .textClipped, "🏓", "A11Y-06: at the bottom edge of a full-height sheet at AX5; the sheet scrolls it into view"),
        .init(["invites"], .largest, .textClipped, "Not used yet", "A11Y-06: at the bottom edge of a full-height sheet at AX5; the sheet scrolls it into view"),
        .init(["invites"], .largest, .textClipped, "Used by Priya S.", "A11Y-06: at the bottom edge of a full-height sheet at AX5; the sheet scrolls it into view"),
        .init(["map"], .largest, .dynamicType, "5 games nearby", "A11Y-06: capped on purpose (map overlays at accessibility2, popup at accessibility1); Arianna picks the cap"),
        .init(["map"], .standard, .dynamicType, "5 games nearby", "A11Y-06: capped on purpose (map overlays at accessibility2, popup at accessibility1); Arianna picks the cap"),
        .pattern(["chat"], .standard, .dynamicType, #"^(Today|Yesterday)$"#, "Day pills near the top edge; which ones depends on the time of day. Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .pattern(["chat"], .standard, .dynamicType, #"^.+ took a spot( · .+)?$"#, "Older activity rows near the top edge; which ones depends on the time of day. Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .init(["me"], .standard, .dynamicType, "Arena Borregos", "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .pattern(["me"], .standard, .dynamicType, #"^(Today|Tomorrow), \d{1,2}:\d{2}\s[AP]M · .+$"#, "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .init(["me"], .standard, .dynamicType, "Volleyball at the arena", "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .init(["me"], .standard, .dynamicType, "Volleyball · Hosted by Sam L.", "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .init(["me"], .standard, .dynamicType, "You're in · room for 7 more", "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .init(["me-hosting"], .standard, .dynamicType, "2 joined · room for 7 more", "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .init(["me-hosting"], .standard, .dynamicType, "Estadio Borregos", "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .init(["me-hosting"], .standard, .dynamicType, "Soccer · Hosted by you", "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .init(["me-hosting"], .standard, .dynamicType, "Sunday pickup soccer", "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .pattern(["me-hosting"], .standard, .dynamicType, #"^(Today|Tomorrow), \d{1,2}:\d{2}\s[AP]M · .+$"#, "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .init(["popup"], .largest, .dynamicType, "+1", "A11Y-06: capped on purpose (map overlays at accessibility2, popup at accessibility1); Arianna picks the cap"),
        .init(["popup"], .largest, .dynamicType, "After-work hoops", "A11Y-06: capped on purpose (map overlays at accessibility2, popup at accessibility1); Arianna picks the cap"),
        .init(["popup"], .largest, .dynamicType, "Basketball · Hosted by Alex R.", "A11Y-06: capped on purpose (map overlays at accessibility2, popup at accessibility1); Arianna picks the cap"),
        .init(["popup"], .largest, .dynamicType, "Room for 4 more", "A11Y-06: capped on purpose (map overlays at accessibility2, popup at accessibility1); Arianna picks the cap"),
        .init(["popup"], .largest, .dynamicType, "Tec basketball courts", "A11Y-06: capped on purpose (map overlays at accessibility2, popup at accessibility1); Arianna picks the cap"),
        .pattern(["popup"], .largest, .dynamicType, #"^(Today|Tomorrow), \d{1,2}:\d{2}\s[AP]M · .+$"#, "A11Y-06: capped on purpose (map overlays at accessibility2, popup at accessibility1); Arianna picks the cap"),
        .init(["popup"], .largest, .textClipped, "Basketball · Hosted by Alex R.", "A11Y-06: capped on purpose (map overlays at accessibility2, popup at accessibility1); Arianna picks the cap"),
        .pattern(["popup"], .largest, .textClipped, #"^(Today|Tomorrow), \d{1,2}:\d{2}\s[AP]M · .+$"#, "A11Y-06: capped on purpose (map overlays at accessibility2, popup at accessibility1); Arianna picks the cap"),
        .init(["popup"], .standard, .contrast, "Room for 4 more", "A11Y-15 (PR 14): ink on the sport color, unchanged (5.60–9.64:1 computed); the audit measures the card's glass"),
        .pattern(["popup"], .standard, .contrast, #"^(Today|Tomorrow), \d{1,2}:\d{2}\s[AP]M · .+$"#, "A11Y-15 (PR 14): ink on the sport color, unchanged (5.60–9.64:1 computed); the audit measures the card's glass"),
        .init(["popup"], .standard, .dynamicType, "After-work hoops", "A11Y-06: capped on purpose (map overlays at accessibility2, popup at accessibility1); Arianna picks the cap"),
        .init(["popup"], .standard, .dynamicType, "Basketball · Hosted by Alex R.", "A11Y-06: capped on purpose (map overlays at accessibility2, popup at accessibility1); Arianna picks the cap"),
        .init(["popup"], .standard, .dynamicType, "Room for 4 more", "A11Y-06: capped on purpose (map overlays at accessibility2, popup at accessibility1); Arianna picks the cap"),
        .init(["popup"], .standard, .dynamicType, "Tec basketball courts", "A11Y-06: capped on purpose (map overlays at accessibility2, popup at accessibility1); Arianna picks the cap"),
        .pattern(["popup"], .standard, .dynamicType, #"^(Today|Tomorrow), \d{1,2}:\d{2}\s[AP]M · .+$"#, "A11Y-06: capped on purpose (map overlays at accessibility2, popup at accessibility1); Arianna picks the cap"),
        .init(["profile"], .largest, .textClipped, "Class year", "A11Y-06: at the bottom edge of a full-height sheet at AX5; the sheet scrolls it into view"),
        .init(["report"], .largest, .textClipped, "Harassment or hateful language", "A11Y-06: at the bottom edge of a full-height sheet at AX5; the sheet scrolls it into view"),
        .init(["saved"], .largest, .dynamicType, "🎾", "A11Y-06: at the bottom edge of a full-height sheet at AX5; the sheet scrolls it into view"),
        .init(["saved"], .largest, .textClipped, "Tennis · Hosted by Priya S.", "A11Y-06: at the bottom edge of a full-height sheet at AX5; the sheet scrolls it into view"),
        .init(["saved"], .largest, .textClipped, "🎾", "A11Y-06: at the bottom edge of a full-height sheet at AX5; the sheet scrolls it into view"),
        .pattern(["settings"], .standard, .dynamicType, #"^\d+(\.\d+)+ \(\d+\)$"#, "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .init(["settings"], .standard, .dynamicType, "About", "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .init(["settings"], .standard, .dynamicType, "Contact us", "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .init(["settings"], .standard, .dynamicType, "Opens our website", "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .init(["settings"], .standard, .dynamicType, "Privacy & Terms", "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .init(["settings"], .standard, .dynamicType, "Version", "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .init(["settings"], .standard, .dynamicType, "official.masuno.app@gmail.com", "Below the fold at default size: the audit loses it as the text grows (scrolled into view it passes)"),
        .init(["who"], .largest, .textClipped, "Room for 4 more", "A11Y-06: at the bottom edge of a full-height sheet at AX5; the sheet scrolls it into view"),

        // Dark mode (build 9), `testScreensInDarkMode`: contrast only, at the default size. Same categories as the light list.
        .init(["dark-filter", "dark-me", "dark-me-hosting", "dark-profile", "dark-onboarding-about"], .standard, .contrast, "⚽️", "Sport emoji (a color glyph, not text): hidden from VoiceOver since PR 13, but the audit still checks it"),
        .init(["dark-map", "dark-popup", "dark-filter", "dark-saved", "dark-me", "dark-me-hosting", "dark-profile", "dark-onboarding-about"], .standard, .contrast, "🎾", "Sport emoji (a color glyph, not text): hidden from VoiceOver since PR 13, but the audit still checks it"),
        .init(["dark-map", "dark-popup", "dark-search", "dark-filter", "dark-me", "dark-me-hosting", "dark-profile", "dark-onboarding-about"], .standard, .contrast, "🏀", "Sport emoji (a color glyph, not text): hidden from VoiceOver since PR 13, but the audit still checks it"),
        .init(["dark-popup", "dark-filter", "dark-me", "dark-profile", "dark-onboarding-about"], .standard, .contrast, "🏐", "Sport emoji (a color glyph, not text): hidden from VoiceOver since PR 13, but the audit still checks it"),
        .init(["dark-filter", "dark-profile", "dark-onboarding-about"], .standard, .contrast, "🏓", "Sport emoji (a color glyph, not text): hidden from VoiceOver since PR 13, but the audit still checks it"),
        .init(["dark-map", "dark-popup", "dark-search"], .standard, .contrast, "AR", "Dark mode (build 9): ink initials kept dark on the unchanged person colors (6.51–10.43:1 computed); the audit measures the white ring and what's behind the token"),
        .init(["dark-map", "dark-popup", "dark-saved"], .standard, .contrast, "DM", "Dark mode (build 9): ink initials kept dark on the unchanged person colors (6.51–10.43:1 computed); the audit measures the white ring and what's behind the token"),
        .init(["dark-popup"], .standard, .contrast, "EG", "Dark mode (build 9): ink initials kept dark on the unchanged person colors (6.51–10.43:1 computed); the audit measures the white ring and what's behind the token"),
        .init(["dark-popup", "dark-chat"], .standard, .contrast, "MC", "Dark mode (build 9): ink initials kept dark on the unchanged person colors (6.51–10.43:1 computed); the audit measures the white ring and what's behind the token"),
        .init(["dark-popup", "dark-chat", "dark-me"], .standard, .contrast, "NC", "Dark mode (build 9): ink initials kept dark on the unchanged person colors (6.51–10.43:1 computed); the audit measures the white ring and what's behind the token"),
        .init(["dark-map", "dark-popup", "dark-saved"], .standard, .contrast, "PS", "Dark mode (build 9): ink initials kept dark on the unchanged person colors (6.51–10.43:1 computed); the audit measures the white ring and what's behind the token"),
        .init(["dark-map", "dark-popup", "dark-search"], .standard, .contrast, "RT", "Dark mode (build 9): ink initials kept dark on the unchanged person colors (6.51–10.43:1 computed); the audit measures the white ring and what's behind the token"),
        .init(["dark-map", "dark-popup", "dark-saved", "dark-chat"], .standard, .contrast, "SL", "Dark mode (build 9): ink initials kept dark on the unchanged person colors (6.51–10.43:1 computed); the audit measures the white ring and what's behind the token"),
        .init(["dark-detail-open", "dark-detail-in", "dark-detail-hosting", "dark-me"], .standard, .contrast, "+1", "Dark mode (build 9): ink on the \"+1\" token's white over the court or a card's sport color, as in light; the audit measures the dashed ring"),
        .init(["dark-chat"], .standard, .contrast, "+2", "Dark mode (build 9): near-white ink on the \"+N\" bubble (10.48:1 on the separator computed); the audit measures the white ring around it"),
        .init(["dark-map", "dark-popup"], .standard, .contrast, "2", "Dark mode (build 9): white count on the group pin, unchanged (8.89:1 computed); the audit measures the map behind the pin"),
        .init(["dark-map"], .standard, .contrast, "5 games nearby", "Dark mode (build 9): muted on the chip's glass; the 44 pt target's frame takes in map above and below it, as in light (A11Y-19)"),
        .init(["dark-search"], .standard, .contrast, "Soon", "Dark mode (build 9): near-white ink on the tag's glass; the audit measures the pin and map behind it"),
        .init(["dark-search"], .standard, .contrast, "Basketball near you", "Dark mode (build 9): muted over the search scrim (about 7.6:1 on black at 78% over the map computed); over map tiles, so it comes and goes"),
        .init(["dark-detail-in", "dark-detail-hosting"], .standard, .contrast, "Add to calendar", "Dark mode (build 9): near-white ink on the dark mint pill (11.1:1 computed); the audit measures the glass edge"),
        .init(["dark-detail-full"], .standard, .contrast, "Open in Maps", "Dark mode (build 9): near-white ink on the dark mint pill (11.1:1 computed); the audit measures the glass edge"),
        .init(["dark-onboarding-pending"], .standard, .contrast, "Use invite code", "Dark mode (build 9): near-white ink on the dark mint pill (11.1:1 computed); the audit measures the glass edge"),
        .init(["dark-onboarding-signin"], .standard, .contrast, "Create an account", "Dark mode (build 9): near-white ink on clear glass (18.8:1 on the background computed); the audit measures what shows through"),
        .init(["dark-onboarding-signup"], .standard, .contrast, "I already have an account", "Dark mode (build 9): near-white ink on clear glass (18.8:1 on the background computed); the audit measures what shows through"),
        .init(["dark-me", "dark-me-hosting"], .standard, .contrast, "Invite friends", "Dark mode (build 9): near-white ink on clear glass (15.3:1 on a card computed); the audit measures what shows through"),
        .init(["dark-filter"], .standard, .contrast, "Reset", "Dark mode (build 9): near-white ink on clear glass (18.8:1 on the background computed); the audit measures what shows through"),
        .init(["dark-filter"], .standard, .contrast, "Soccer", "Dark mode (build 9): an off sport toggle, near-white ink on clear glass (18.8:1 on the background computed); the audit measures the emoji and what shows through"),
        .init(["dark-filter"], .standard, .contrast, "Tennis", "Dark mode (build 9): an off sport toggle, near-white ink on clear glass (18.8:1 on the background computed); the audit measures the emoji and what shows through"),
        .init(["dark-onboarding-pending"], .standard, .contrast, "Sign out", "Dark mode (build 9): near-white ink on clear glass (18.8:1 on the background computed); the audit measures what shows through"),
        .init(["dark-picker"], .standard, .contrast, "Set location", "Dark mode (build 9): white on the accent fill, unchanged (4.81:1 computed); the audit measures the glass highlight"),
        .init(["dark-chat"], .standard, .contrast, "Maya C.", "Dark mode (build 9): muted on the page (8.38:1 on black, 6.79 on a card computed); the audit's measurement, comes and goes"),
        .init(["dark-chat"], .standard, .contrast, "Sam L.", "Dark mode (build 9): muted on the page (8.38:1 on black, 6.79 on a card computed); the audit's measurement, comes and goes"),
        .init(["dark-chat"], .standard, .contrast, "· Host", "Dark mode (build 9): muted on the page (8.38:1 on black, 6.79 on a card computed); the audit's measurement, comes and goes"),
        .pattern(["dark-chat"], .standard, .contrast, #"^· \d{1,2}:\d{2}\s[AP]M$"#, "Dark mode (build 9): muted on the page (8.38:1 on black, 6.79 on a card computed); the audit's measurement, comes and goes"),
        .pattern(["dark-chat"], .standard, .contrast, #"^(Today|Yesterday)$"#, "Dark mode (build 9): muted day pill (4.67:1 on the separator computed; 5.94 under Increase Contrast); near the threshold, so it comes and goes"),
    ]
}
