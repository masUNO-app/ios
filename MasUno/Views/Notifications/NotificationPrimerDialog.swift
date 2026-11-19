import SwiftUI

/// After the first game you join or host. iOS is asked only from Turn on, and only once the primer
/// has explained what the alerts are. "Not now" comes back one more time. The same dialog card as
/// the location primer, with the tips choice inside it.
struct NotificationPrimerDialog: View {
    @Environment(GameStore.self) private var store
    @Environment(PushNotificationService.self) private var push
    @State private var wantsTips = false

    var body: some View {
        DialogCard(
            systemImage: "bell.badge", tone: .tinted(Color(.sportPadel)),
            title: Text("Know when your game changes or a spot opens"),
            message: Text("We'll tell you about cancellations, time changes, reminders and spots. You can change this in Settings."),
            confirm: DialogAction("Turn on notifications") {
                // The dialog has closed; the account is read before anything can sign out.
                let accountID = store.profile?.id
                let tips = wantsTips
                Task { await turnOn(accountID: accountID, tips: tips) }
            },
            cancel: DialogAction("Not now") { decline() }
        ) {
            Toggle("Tips when games match your sports", isOn: $wantsTips)
                .font(.rounded(.subheadline))
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .padding(.top, 2)
        }
    }

    /// Asks iOS, then saves the tips choice. Passing twice, or answering iOS, ends the primer.
    private func turnOn(accountID: UUID?, tips: Bool) async {
        guard let accountID else { return }
        push.recordPrimerAccepted(accountID: accountID)
        _ = await push.requestPermission()
        do {
            if let fetched = try? await push.fetchPrefs() {
                var prefs = fetched
                prefs.winback = tips
                try await push.setPrefs(prefs)
            } else if tips {
                try await push.setWinback(true)
            }
        } catch {
            store.notice = (error as? DomainError)?.message ?? DomainError.offline.message
        }
    }

    /// One decline; the primer comes back once more.
    private func decline() {
        guard let accountID = store.profile?.id else { return }
        push.recordPrimerDecline(accountID: accountID)
    }
}
