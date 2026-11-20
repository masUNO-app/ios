import Foundation
import Testing
@testable import masUNO

/// Settings opens with the account's last known notification settings instead of a spinner, and
/// never shows one account's settings to another.
@Suite(.serialized)
struct SettingsLoadingTests {
    private let backend = MockBackend()
    private let defaults = UserDefaults(suiteName: "SettingsLoadingTests.\(UUID().uuidString)")!
    private let service: PushNotificationService

    init() {
        AppGroupStore.clearAccount()
        service = PushNotificationService(repository: backend, games: backend, chat: backend, defaults: defaults,
                                          system: MockNotificationSystemClient())
    }

    @Test func nothingIsKnownBeforeTheFirstRead() {
        #expect(service.lastKnownPrefs == nil)
    }

    @Test func aReadIsKeptForTheNextSettingsScreen() async throws {
        let read = try await service.fetchPrefs()
        #expect(service.lastKnownPrefs == read)
    }

    @Test func aSaveIsKeptToo() async throws {
        var prefs = try await service.fetchPrefs()
        prefs.reminders = false
        try await service.setPrefs(prefs)
        #expect(service.lastKnownPrefs?.reminders == false)
    }

    @Test func thePrimersTipsSwitchUpdatesTheKnownSettings() async throws {
        _ = try await service.fetchPrefs()
        try await service.setWinback(true)
        #expect(service.lastKnownPrefs?.winback == true)
    }

    @Test func anotherAccountNeverSeesThem() async throws {
        _ = try await service.fetchPrefs()
        service.noteAccount(UUID())
        #expect(service.lastKnownPrefs == nil)
    }

    @Test func signingOutOrDeletingDropsThem() async throws {
        _ = try await service.fetchPrefs()
        service.discardLocalDevice()
        #expect(service.lastKnownPrefs == nil)
    }

    @Test @MainActor func aSwitchFlipCountsAsAnEdit() {
        let queue = NotificationPrefQueue()
        #expect(queue.edits == 0)
        queue.set(\.reminders, to: false, send: { _ in }, onFailure: { _ in })
        #expect(queue.edits == 1)
        // A later read replaces the values without counting as an edit.
        queue.replace(.standard)
        #expect(queue.edits == 1)
    }
}
