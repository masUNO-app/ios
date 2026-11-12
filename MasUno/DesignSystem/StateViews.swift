import SwiftUI

/// A load failed and there's nothing to show yet: say so and offer a retry (SPEC §7.6.8).
struct RetryCard: View {
    var message: LocalizedStringKey = "Couldn't load games."
    var onRetry: () async -> Void
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.rounded(.subheadline, .bold))
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
            .pill(.secondary, expands: false, size: .regular)
            .disabled(isRetrying)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}

/// Shown over old data when the last load couldn't reach the server.
struct OfflineBanner: View {
    var body: some View {
        Label("You're offline — showing the last games we loaded.", systemImage: "wifi.slash")
            .font(.rounded(.footnote, .bold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
    }
}

/// An empty list as an invitation (Figma "No games yet", "No games nearby yet"): the dashed
/// "+1", a title, one line, and what to do about it.
struct EmptyCard<Actions: View>: View {
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OpenSpotToken(size: 50, fill: .clear)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.rounded(.title2, .bold))
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(.rounded(.subheadline))
                    .foregroundStyle(Theme.muted)
            }
            VStack(spacing: 10) { actions }
                .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.dialog))
    }
}

/// Grey note with a shield, under lists of people.
struct SafetyNote: View {
    var text: LocalizedStringKey

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "checkmark.shield")
        }
        .labelStyle(IconRowLabelStyle(iconWidth: 18, spacing: 8))
        .font(.rounded(.footnote))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.separator.opacity(0.6), in: .rect(cornerRadius: 14))
    }
}
