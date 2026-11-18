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
        .pattern(["picker"], .standard, .dynamicType, #"."#, "A11Y-06 (PR 12): Apple Maps suggestion rows, one line"),
        .init(["map", "popup", "search"], .both, .dynamicType, "Add game", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["detail-open"], .both, .dynamicType, "After-work hoops", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["detail-hosting"], .standard, .dynamicType, "Edit game", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["who"], .both, .dynamicType, "HOST", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["detail-in"], .standard, .dynamicType, "Invite a friend", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        // The same chat rows, when the audit reports them before their labels load.
        .init(["chat"], .standard, .dynamicType, "", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["chat"], .standard, .dynamicType, "Maya took a spot", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["chat"], .standard, .dynamicType, "Net's up on the far court. Bring water, it's hot in there.", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["chat"], .standard, .dynamicType, "Nina took a spot", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["detail-in"], .standard, .dynamicType, "Open group chat", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["detail-full"], .both, .dynamicType, "Padel at Distrito Tec", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["chat"], .standard, .dynamicType, "Priya took a spot", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["chat"], .standard, .dynamicType, "Sam L.", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["chat"], .standard, .dynamicType, "Sam created the chat", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["detail-hosting"], .standard, .dynamicType, "Share game", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["detail-hosting"], .both, .dynamicType, "Sunday pickup soccer", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["chat"], .standard, .dynamicType, "Today", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["picker"], .standard, .dynamicType, "Use my current location", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["detail-in", "chat"], .both, .dynamicType, "Volleyball at the arena", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["chat"], .standard, .dynamicType, "You took a spot · room for 7 more", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .pattern(["chat"], .standard, .dynamicType, #"^· \d{1,2}:\d{2}\u202F[AP]M$"#, "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["chat"], .standard, .dynamicType, "· Host", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["chat"], .both, .dynamicType, "🏐 Volleyball · 5 going", "A11Y-06 (PR 12): one-line limit or minimumScaleFactor"),
        .init(["detail-in", "detail-hosting", "add", "form-error", "picker"], .largest, .textClipped, "", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["add", "form-error", "picker"], .standard, .textClipped, "", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .pattern(["picker"], .standard, .textClipped, #"."#, "A11Y-06 (PR 12): Apple Maps suggestion rows, one line"),
        .init(["add", "form-error"], .standard, .textClipped, "1 hour", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["who"], .largest, .textClipped, "2 going", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["who"], .standard, .textClipped, "2 going", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["map"], .largest, .textClipped, "5 games nearby", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["map"], .standard, .textClipped, "5 games nearby", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["search"], .largest, .textClipped, "After-work hoops", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["popup", "search"], .standard, .textClipped, "After-work hoops", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["detail-full"], .largest, .textClipped, "Alert me if a spot opens", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["detail-full"], .standard, .textClipped, "Alert me if a spot opens", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["who"], .largest, .textClipped, "Alex R.", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["who"], .standard, .textClipped, "Alex R.", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["filter"], .standard, .textClipped, "Any day this week", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["report"], .standard, .textClipped, "Anything else we should know?", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["who"], .standard, .textClipped, "Anything feel off? Tap ••• next to anyone to report or block them. Only the masUNO team sees reports.", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["me"], .standard, .textClipped, "Arena Borregos", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["form-error"], .standard, .textClipped, "Av. Eugenio Garza Sada 2501 Sur, Tecnológico, Monterrey, N.L.", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["detail-in"], .standard, .textClipped, "Av. Junco de la Vega, Tecnológico, Monterrey, N.L.", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["filter"], .largest, .textClipped, "Basketball", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["filter", "profile"], .standard, .textClipped, "Basketball", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["search"], .largest, .textClipped, "Basketball near you", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["search"], .standard, .textClipped, "Basketball near you", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["popup"], .standard, .textClipped, "Basketball · Hosted by Alex R.", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["settings"], .standard, .textClipped, "Blocked people", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["who"], .largest, .textClipped, "Class of 2027", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["who"], .standard, .textClipped, "Class of 2027", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["profile"], .standard, .textClipped, "Class year", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["settings"], .standard, .textClipped, "Community guidelines", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["settings"], .standard, .textClipped, "Contact us", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["add"], .largest, .textClipped, "Date", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["add", "form-error"], .standard, .textClipped, "Date", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["picker"], .largest, .textClipped, "Drag the map to adjust", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["picker"], .standard, .textClipped, "Drag the map to adjust", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["add"], .largest, .textClipped, "Duration", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["add", "form-error"], .standard, .textClipped, "Duration", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["profile"], .largest, .textClipped, "Edit profile", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["profile"], .standard, .textClipped, "Edit profile", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["me-hosting"], .standard, .textClipped, "Estadio Borregos", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["report"], .standard, .textClipped, "Fake profile or not a student", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["filter"], .largest, .textClipped, "Filter games", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["filter"], .standard, .textClipped, "Filter games", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["profile", "onboarding-about"], .largest, .textClipped, "First name", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["profile", "onboarding-about"], .standard, .textClipped, "First name", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["add", "form-error"], .largest, .textClipped, "Game name", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["add", "form-error"], .standard, .textClipped, "Game name", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["who"], .largest, .textClipped, "HOST", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["who"], .standard, .textClipped, "HOST", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["report"], .standard, .textClipped, "Harassment or hateful language", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["filter"], .standard, .textClipped, "How far", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["onboarding-signup"], .standard, .textClipped, "Invite code (optional)", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["invites"], .largest, .textClipped, "Invites", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["invites"], .standard, .textClipped, "Invites", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["invites"], .standard, .textClipped, "JUMP-3ZRS", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["profile", "onboarding-about"], .largest, .textClipped, "Last name", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["profile", "onboarding-about"], .standard, .textClipped, "Last name", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["report"], .largest, .textClipped, "Made me feel unsafe", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["report"], .standard, .textClipped, "Made me feel unsafe", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["add", "form-error"], .standard, .textClipped, "Meet-up spot (optional)", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["onboarding-signup"], .standard, .textClipped, "Password", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["invites"], .standard, .textClipped, "Not used yet", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["filter"], .standard, .textClipped, "Only games in the next hour", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["report"], .largest, .textClipped, "Only the masUNO team sees this.", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["report"], .standard, .textClipped, "Only the masUNO team sees this.", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["profile"], .standard, .textClipped, "Only you see what you play.", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["settings"], .standard, .textClipped, "Opens our website", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["report"], .standard, .textClipped, "Optional", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["profile"], .largest, .textClipped, "Others see Emilio G. and your class year.", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["profile"], .standard, .textClipped, "Others see Emilio G. and your class year.", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["invites"], .standard, .textClipped, "PLAY-4NWE", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["settings"], .standard, .textClipped, "Privacy & Terms", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["report"], .standard, .textClipped, "Pushed me to share personal info", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["report"], .largest, .textClipped, "Report Alex", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["report"], .standard, .textClipped, "Report Alex", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["filter"], .standard, .textClipped, "Reset", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["who"], .largest, .textClipped, "Ricardo T.", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["who"], .standard, .textClipped, "Ricardo T.", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["popup", "who"], .standard, .textClipped, "Room for 4 more", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["saved"], .standard, .textClipped, "Room for one more", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["saved"], .largest, .textClipped, "Saved games", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["saved"], .standard, .textClipped, "Saved games", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["picker"], .largest, .textClipped, "Search, or drag the map under the pin.", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["picker"], .standard, .textClipped, "Search, or drag the map under the pin.", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["filter"], .standard, .textClipped, "Show 5 games", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["filter"], .largest, .textClipped, "Show me games that fit.", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["filter"], .standard, .textClipped, "Show me games that fit.", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["filter"], .largest, .textClipped, "Soccer", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["filter", "profile"], .standard, .textClipped, "Soccer", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["me-hosting"], .standard, .textClipped, "Soccer · Hosted by you", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["report"], .standard, .textClipped, "Something else", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["add"], .largest, .textClipped, "Start time", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["add", "form-error"], .standard, .textClipped, "Start time", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["filter"], .standard, .textClipped, "Starting soon", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["popup", "form-error"], .standard, .textClipped, "Tec basketball courts", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["saved"], .standard, .textClipped, "Tec tennis courts", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["filter"], .largest, .textClipped, "Tennis", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["filter", "profile"], .standard, .textClipped, "Tennis", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["saved"], .standard, .textClipped, "Tennis · Hosted by Priya S.", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["add", "form-error"], .standard, .textClipped, "Today", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["saved"], .largest, .textClipped, "Turn on a spot alert and we'll tell you when a full game opens up.", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["saved"], .standard, .textClipped, "Turn on a spot alert and we'll tell you when a full game opens up.", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["picker"], .standard, .textClipped, "Use my current location", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["invites"], .standard, .textClipped, "Used by Priya S.", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["filter"], .largest, .textClipped, "Volleyball", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["filter", "profile"], .standard, .textClipped, "Volleyball", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["chat"], .largest, .textClipped, "Volleyball at the arena", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["chat"], .standard, .textClipped, "Volleyball at the arena", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["me"], .standard, .textClipped, "Volleyball · Hosted by Sam L.", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["settings"], .standard, .textClipped, "What everyone agrees to", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["filter"], .standard, .textClipped, "When", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["add"], .standard, .textClipped, "Where's the game?", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["settings"], .standard, .textClipped, "While using the app", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["who"], .largest, .textClipped, "Who's going", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["who"], .standard, .textClipped, "Who's going", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["me"], .standard, .textClipped, "You're in · room for 7 more", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .pattern(["search"], .largest, .textClipped, #"^(Today|Tomorrow), \d{1,2}:\d{2}\u202F[AP]M · 0\.2 mi · room for 4$"#, "A11Y-06 (PR 12): clipped at AX5"),
        .pattern(["search"], .standard, .textClipped, #"^(Today|Tomorrow), \d{1,2}:\d{2}\u202F[AP]M · 0\.2 mi · room for 4$"#, "A11Y-06 (PR 12): fixed height or one-line limit"),
        .pattern(["saved", "me"], .standard, .textClipped, #"^(Today|Tomorrow), \d{1,2}:\d{2}\u202F[AP]M · about 1 hour$"#, "A11Y-06 (PR 12): fixed height or one-line limit"),
        .pattern(["me-hosting"], .standard, .textClipped, #"^(Today|Tomorrow), \d{1,2}:\d{2}\u202F[AP]M · about 1\.5 hours$"#, "A11Y-06 (PR 12): fixed height or one-line limit"),
        .pattern(["popup"], .standard, .textClipped, #"^(Today|Tomorrow), \d{1,2}:\d{2}\u202F[AP]M · starts in 34 min$"#, "A11Y-06 (PR 12): fixed height or one-line limit"),
        .pattern(["add", "form-error"], .standard, .textClipped, #"^\d{1,2}:\d{2}\u202F[AP]M$"#, "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["invites"], .largest, .textClipped, "masUNO is invite-only for now. Each code lets one friend skip the waitlist.", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["invites"], .standard, .textClipped, "masUNO is invite-only for now. Each code lets one friend skip the waitlist.", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["settings"], .standard, .textClipped, "official.masuno.app@gmail.com", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["filter", "me", "me-hosting"], .largest, .textClipped, "⚽️", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["filter", "me", "me-hosting", "profile", "onboarding-about"], .standard, .textClipped, "⚽️", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["map", "popup", "filter", "me", "me-hosting"], .largest, .textClipped, "🎾", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["map", "popup", "filter", "saved", "me", "me-hosting", "profile", "onboarding-about"], .standard, .textClipped, "🎾", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["map", "popup", "search", "filter", "picker", "me", "me-hosting"], .largest, .textClipped, "🏀", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["map", "popup", "search", "filter", "picker", "me", "me-hosting", "profile", "onboarding-about"], .standard, .textClipped, "🏀", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["add", "form-error"], .largest, .textClipped, "🏀  Basketball", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["add", "form-error"], .standard, .textClipped, "🏀  Basketball", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["popup", "filter"], .largest, .textClipped, "🏐", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["popup", "filter", "me", "profile", "onboarding-about"], .standard, .textClipped, "🏐", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["chat"], .largest, .textClipped, "🏐 Volleyball · 5 going", "A11Y-06 (PR 12): clipped at AX5"),
        .init(["chat"], .standard, .textClipped, "🏐 Volleyball · 5 going", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["filter", "profile", "onboarding-about"], .standard, .textClipped, "🏓", "A11Y-06 (PR 12): fixed height or one-line limit"),
        .init(["filter", "me", "me-hosting", "profile", "onboarding-about"], .standard, .contrast, "⚽️", "A11Y-11 (PR 13): sport emoji (a color glyph, not text)"),
        .init(["map", "popup", "filter", "saved", "me", "me-hosting", "profile", "onboarding-about"], .standard, .contrast, "🎾", "A11Y-11 (PR 13): sport emoji (a color glyph, not text)"),
        .init(["map", "popup", "search", "filter", "me", "me-hosting", "profile", "onboarding-about"], .standard, .contrast, "🏀", "A11Y-11 (PR 13): sport emoji (a color glyph, not text)"),
        .init(["popup", "filter", "me", "profile", "onboarding-about"], .standard, .contrast, "🏐", "A11Y-11 (PR 13): sport emoji (a color glyph, not text)"),
        .init(["filter", "saved", "profile", "onboarding-about"], .standard, .contrast, "🏓", "A11Y-11 (PR 13): sport emoji (a color glyph, not text)"),
        .init(["filter", "saved", "detail-open", "detail-hosting", "chat", "me", "me-hosting", "profile", "invites", "blocked"], .standard, .elementDetection, "", "A11Y-13 (PR 13): text inside a combined element"),
        .init(["settings"], .standard, .contrast, "About", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["me-hosting"], .standard, .contrast, "Add game", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["detail-hosting"], .standard, .contrast, "Add to calendar", "A11Y-15 (PR 14): accent or error text on the background"),
        .init(["detail-in"], .standard, .contrast, "Add to calendar", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["detail-full"], .standard, .contrast, "Alert me if a spot opens", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["chat"], .standard, .contrast, "Arena Borregos", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["detail-in"], .standard, .contrast, "Av. Junco de la Vega, Tecnológico, Monterrey, N.L.", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["detail-full"], .standard, .contrast, "Calle Profr. Moisés Sáenz, Tecnológico, Monterrey, N.L.", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["form-error"], .standard, .contrast, "Change", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["add"], .standard, .contrast, "Choose", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["add"], .standard, .contrast, "Come for part of it", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["add"], .standard, .contrast, "Coming alone is fine", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["add"], .standard, .contrast, "I have an extra ball", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["detail-open"], .standard, .contrast, "Count me in", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["onboarding-signin"], .standard, .contrast, "Create an account", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["detail-hosting"], .standard, .contrast, "Edit game", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["onboarding-signup"], .standard, .contrast, "I already have an account", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["detail-in"], .standard, .contrast, "Invite a friend", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["me", "me-hosting"], .standard, .contrast, "Invite friends", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["chat"], .standard, .contrast, "Maya C.", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["detail-open"], .standard, .contrast, "Meet by the north court bleachers", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["settings"], .standard, .contrast, "Notifications", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["detail-in"], .standard, .contrast, "Open group chat", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["detail-open", "detail-full"], .standard, .contrast, "Open in Maps", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["saved"], .standard, .contrast, "Padel · Hosted by Nina C.", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["settings"], .standard, .contrast, "Privacy & safety", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["filter"], .standard, .contrast, "Reset", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["chat"], .standard, .contrast, "Sam L.", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["profile"], .standard, .contrast, "Save", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["picker"], .standard, .contrast, "Search, or drag the map under the pin.", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["picker"], .standard, .contrast, "Set location", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["detail-hosting"], .standard, .contrast, "Share game", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["filter"], .standard, .contrast, "Show 5 games", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["settings", "onboarding-pending"], .standard, .contrast, "Sign out", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["blocked"], .standard, .contrast, "Unblock", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["onboarding-pending"], .standard, .contrast, "Use invite code", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["picker"], .standard, .contrast, "Use my current location", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["onboarding-pending"], .standard, .contrast, "Want a heads-up when you're in?", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["settings"], .standard, .contrast, "What everyone agrees to", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["detail-open", "detail-in", "detail-full", "detail-hosting"], .standard, .contrast, "Who's going", "A11Y-15 (PR 14): accent or error text on the background"),
        .init(["detail-in"], .standard, .contrast, "You're in!", "A11Y-15 (PR 14): accent or error text on the background"),
        .init(["detail-hosting"], .standard, .contrast, "Your game is live!", "A11Y-15 (PR 14): accent or error text on the background"),
        .pattern(["chat"], .standard, .contrast, #"^(Today|Tomorrow) · \d{1,2}:\d{2}\u202F[AP]M$"#, "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .pattern(["settings"], .standard, .contrast, #"^\d+\.\d+ \(\d+\)$"#, "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .pattern(["form-error"], .standard, .contrast, #"^\d{1,2}:\d{2}\u202F[AP]M has already passed today\. Pick a later time\.$"#, "A11Y-15 (PR 14): accent or error text on the background"),
        .pattern(["chat"], .standard, .contrast, #"^· \d{1,2}:\d{2}\u202F[AP]M$"#, "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["chat"], .standard, .contrast, "· Host", "A11Y-15 (PR 14): accent, white-on-accent or muted text"),
        .init(["chat"], .standard, .contrast, "", "A11Y-16 (PR 14): unlabeled shape"),
        .init(["picker"], .standard, .contrast, "Drag the map to adjust", "A11Y-16 (PR 14): over map tiles, so it comes and goes"),
        .init(["picker"], .standard, .contrast, "🏀", "A11Y-16 (PR 14): pin over map tiles, so it comes and goes"),
        .init(["detail-open", "detail-in", "detail-hosting", "me"], .standard, .contrast, "+1", "A11Y-16 (PR 14): court token or pin, recheck with Arianna"),
        .init(["chat"], .standard, .contrast, "+2", "A11Y-16 (PR 14): court token or pin, recheck with Arianna"),
        .init(["popup"], .standard, .contrast, "2", "A11Y-16 (PR 14): court token or pin, recheck with Arianna"),
        .init(["map", "popup", "search"], .standard, .contrast, "AR", "A11Y-16 (PR 14): court token or pin, recheck with Arianna"),
        .init(["map", "popup", "saved"], .standard, .contrast, "DM", "A11Y-16 (PR 14): court token or pin, recheck with Arianna"),
        .init(["search"], .standard, .contrast, "EG", "A11Y-16 (PR 14): court token or pin, recheck with Arianna"),
        .init(["popup", "chat"], .standard, .contrast, "MC", "A11Y-16 (PR 14): court token or pin, recheck with Arianna"),
        .init(["popup", "chat", "me"], .standard, .contrast, "NC", "A11Y-16 (PR 14): court token or pin, recheck with Arianna"),
        .init(["map", "popup", "saved", "detail-in"], .standard, .contrast, "PS", "A11Y-16 (PR 14): court token or pin, recheck with Arianna"),
        .init(["map", "popup", "search"], .standard, .contrast, "RT", "A11Y-16 (PR 14): court token or pin, recheck with Arianna"),
        .init(["map", "popup", "saved", "chat"], .standard, .contrast, "SL", "A11Y-16 (PR 14): court token or pin, recheck with Arianna"),
        .init(["popup", "search"], .standard, .contrast, "Soon", "A11Y-16 (PR 14): court token or pin, recheck with Arianna"),
        .init(["map"], .standard, .hitRegion, "5 games nearby", "A11Y-19 (PR 15): nearby chip is 32 pt tall"),
        .init(["search", "picker"], .standard, .hitRegion, "Clear search", "A11Y-19 (PR 15): clear button is about 22 pt"),
        .init(["onboarding-signin"], .standard, .hitRegion, "Forgot your password? Contact us", "A11Y-19 (PR 15): small inline link"),
        .init(["detail-open", "detail-in", "detail-full", "detail-hosting"], .standard, .hitRegion, "Who's going", "A11Y-19 (PR 15): text link shorter than 44 pt"),
        .init(["filter", "profile", "onboarding-about"], .standard, .hitRegion, "⚽️, Soccer", "A11Y-19 (PR 15): sport toggles are 32 pt tall"),
        .init(["filter", "profile", "onboarding-about"], .standard, .hitRegion, "🎾, Tennis", "A11Y-19 (PR 15): sport toggles are 32 pt tall"),
        .init(["filter", "profile", "onboarding-about"], .standard, .hitRegion, "🏀, Basketball", "A11Y-19 (PR 15): sport toggles are 32 pt tall"),
        .init(["filter", "profile", "onboarding-about"], .standard, .hitRegion, "🏐, Volleyball", "A11Y-19 (PR 15): sport toggles are 32 pt tall"),
        .init(["filter", "profile", "onboarding-about"], .standard, .hitRegion, "🏓, Padel", "A11Y-19 (PR 15): sport toggles are 32 pt tall"),
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
    ]
}
