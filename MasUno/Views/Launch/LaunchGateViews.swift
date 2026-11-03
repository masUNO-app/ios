import SwiftUI

/// Full-screen message used by the launch gate (SPEC §7.3).
private struct GateScreen<Actions: View>: View {
    var systemImage: String
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 88, height: 88)
                .background(Theme.accentSoft, in: .circle)
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer()
            actions
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 16)
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
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .buttonSizing(.flexible)
                .fontWeight(.semibold)
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
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accentSoft)
                    .foregroundStyle(Theme.ink)
                    .controlSize(.large)
                    .buttonSizing(.flexible)
                    .fontWeight(.semibold)
            }
        }
    }
}
