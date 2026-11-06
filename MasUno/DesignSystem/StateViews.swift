import SwiftUI

/// A load failed and there's nothing to show yet: say so and offer a retry (SPEC §7.6.8).
struct RetryCard: View {
    var message: LocalizedStringKey = "Couldn't load games."
    var onRetry: () async -> Void
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Button {
                Task {
                    isRetrying = true
                    await onRetry()
                    isRetrying = false
                }
            } label: {
                if isRetrying { ProgressView() } else { Text("Try again") }
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accentSoft)
            .foregroundStyle(Theme.ink)
            .fontWeight(.semibold)
            .disabled(isRetrying)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}

/// Shown over old data when the last load couldn't reach the server.
struct OfflineBanner: View {
    var body: some View {
        Label("You're offline — showing the last games we loaded.", systemImage: "wifi.slash")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
    }
}
