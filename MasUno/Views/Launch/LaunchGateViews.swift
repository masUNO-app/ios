import SwiftUI

/// Full-screen message used by the launch gate (SPEC §7.3).
private struct GateScreen<Actions: View>: View {
    var systemImage: String
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Image(systemName: systemImage)
                .font(.title.weight(.medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 64, height: 64)
                .background(Theme.accentSoft, in: .circle)
                .accessibilityHidden(true)
            Text(title)
                .font(.rounded(.largeTitle, .bold))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.rounded(.body))
                .foregroundStyle(Theme.muted)
            Spacer()
            Spacer()
            actions
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 16)
        .frame(maxWidth: Theme.columnWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

/// `app_config.min_supported_version` is newer than this build.
struct UpdateRequiredView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        GateScreen(
            systemImage: "arrow.down.app",
            title: "Update masUNO",
            message: "This version is no longer supported. Update to keep finding games."
        ) {
            Button("Update") { openURL(AppConfig.appStoreURL) }
                .pill(.primary)
        }
    }
}

/// A moderator banned this account (`profile_private.banned_at`).
struct SuspendedView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        GateScreen(
            systemImage: "hand.raised",
            title: "Your account is suspended",
            message: "If you think this is a mistake, email us at \(appViewModel.config.supportEmail)."
        ) {
            if let mail = appViewModel.config.supportMailURL {
                Button("Contact support") { openURL(mail) }
                    .pill(.secondary)
            }
        }
    }
}
