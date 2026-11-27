import Foundation
import Testing
import UIKit
@testable import masUNO

@MainActor
struct AppearanceSettingsTests {
    private let defaults = UserDefaults(suiteName: "AppearanceTests.\(UUID().uuidString)")!

    @Test func followsThePhoneUntilSomethingIsPicked() {
        let settings = AppearanceSettings(defaults: defaults)
        #expect(settings.preference == .system)
        #expect(settings.preference.style == .unspecified)
    }

    @Test func choicePersistsAndSystemCanBeRestored() {
        let first = AppearanceSettings(defaults: defaults)
        first.preference = .dark
        let relaunched = AppearanceSettings(defaults: defaults)
        #expect(relaunched.preference == .dark)
        #expect(relaunched.preference.style == .dark)
        relaunched.preference = .light
        #expect(AppearanceSettings(defaults: defaults).preference.style == .light)
        relaunched.preference = .system
        #expect(AppearanceSettings(defaults: defaults).preference == .system)
    }

    @Test func unknownStoredChoiceFollowsThePhone() {
        defaults.set("sepia", forKey: AppearanceSettings.preferenceKey)
        #expect(AppearanceSettings(defaults: defaults).preference == .system)
    }

    @Test func applySetsEveryWindowOfTheScene() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        defer { window.windowScene = nil }
        let settings = AppearanceSettings(defaults: defaults)
        settings.preference = .dark
        #expect(window.overrideUserInterfaceStyle == .dark)
        settings.preference = .system
        #expect(window.overrideUserInterfaceStyle == .unspecified)
    }
}
