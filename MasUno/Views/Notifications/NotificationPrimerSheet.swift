import SwiftUI

/// After the first game you join or host. iOS is asked only from Turn on, and only once the primer
/// has explained what the alerts are. "Not now" comes back one more time.
struct NotificationPrimerSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(PushNotificationService.self) private var push
    @Environment(\.dismiss) private var dismiss
    @State private var wantsTips = false
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Know when your game changes or a spot opens")
                .font(.rounded(.title2, .bold))
                .foregroundStyle(Theme.ink)
            Text("We'll tell you about cancellations, time changes, reminders and spots. You can change this in Settings.")
                .font(.rounded(.body))
                .foregroundStyle(Theme.muted)
            Toggle("Tips when games match your sports", isOn: $wantsTips)
                .font(.rounded(.body))
                .tint(Theme.accent)
            VStack(spacing: 10) {
                Button(isWorking ? "Turning on" : "Turn on notifications") {
                    Task { await turnOn() }
                }
                .pill(.primary)
                .disabled(isWorking)
                Button("Not now") { decline() }
                    .pill(.quiet)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    /// Asks iOS, then saves the tips choice. Passing twice, or answering iOS, ends the primer.
    private func turnOn() async {
        guard let accountID = store.profile?.id else { return dismiss() }
        isWorking = true
        defer { isWorking = false }
        _ = await push.requestPermission()
        do {
            if let fetched = try? await push.fetchPrefs() {
                var prefs = fetched
                prefs.winback = wantsTips
                try await push.setPrefs(prefs)
            } else if wantsTips {
                try await push.setWinback(true)
            }
        } catch {
            store.notice = (error as? DomainError)?.message ?? DomainError.offline.message
        }
        push.recordPrimerAccepted(accountID: accountID)
        store.notificationPrimerAccepted = true
        store.asksForNotificationPrimer = false
        dismiss()
    }

    private func decline() {
        store.asksForNotificationPrimer = false
        dismiss()
    }
}
