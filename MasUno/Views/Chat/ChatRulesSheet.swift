import SwiftUI

/// Figma: "Chat rules" (341:2420) — "Before you chat", shown the first time you open a chat.
struct ChatRulesSheet: View {
    var gameTitle: String
    /// true for **I agree**, false for **Not now** (leaves the chat).
    var onFinish: (Bool) -> Void

    private let rules: [LocalizedStringKey] = [
        "Be respectful. No harassment, hate or slurs.",
        "Keep it about the game: plans, timing, where to meet.",
        "Don't share anyone's personal info or photos without asking.",
        "Meet in public places and look out for each other.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark.shield")
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 52, height: 52)
                .background(Theme.accentSoft, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Before you chat")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                Text("This chat is for the people going to \(gameTitle). To keep it friendly and safe:")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(rules.indices, id: \.self) { index in
                    Label {
                        Text(rules[index]).foregroundStyle(Theme.ink)
                    } icon: {
                        Image(systemName: "checkmark").foregroundStyle(Theme.accent).fontWeight(.semibold)
                    }
                    .font(.subheadline)
                }
            }

            Text("You can report anyone from the Who's going list.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)

            VStack(spacing: 10) {
                Button("I agree") { onFinish(true) }
                    .buttonStyle(.glassProminent)
                Button("Not now") { onFinish(false) }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accentSoft)
                    .foregroundStyle(Theme.ink)
            }
            .controlSize(.large)
            .buttonSizing(.flexible)
            .fontWeight(.semibold)
        }
        .padding(Theme.gutter)
        .padding(.top, 8)
        .presentationDetents([.height(560), .large])
        .presentationBackground(Theme.card)
        .interactiveDismissDisabled()
    }
}
