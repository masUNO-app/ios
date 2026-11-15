import SwiftUI

/// The four rules everyone agrees to: in onboarding, again before their first message, and
/// any time from Settings (SPEC §7.5).
struct CommunityRules: View {
    private let rules: [LocalizedStringKey] = [
        "Be respectful. No harassment, hate or slurs.",
        "Keep it about the game: plans, timing, where to meet.",
        "Don't share anyone's personal info or photos without asking.",
        "Meet in public places and look out for each other.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rules.indices, id: \.self) { index in
                Label {
                    Text(rules[index])
                        .font(.rounded(.subheadline))
                        .foregroundStyle(Theme.ink)
                } icon: {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
                .labelStyle(IconRowLabelStyle(iconWidth: 16, spacing: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Figma: "Chat rules" (341:2420) — "Before you chat", once per account, over the chat.
struct ChatRulesDialog: View {
    var gameTitle: String
    /// true for **I agree**, false for **Not now** (leaves the chat).
    var onFinish: (Bool) -> Void

    var body: some View {
        DialogCard(
            systemImage: "checkmark.shield",
            title: Text("Before you chat"),
            message: Text("This chat is for the people going to \(gameTitle). To keep it friendly and safe:"),
            footnote: Text("Touch and hold a message to report it, or report anyone from the Who's going list."),
            confirm: DialogAction("I agree") { onFinish(true) },
            cancel: DialogAction("Not now") { onFinish(false) }
        ) {
            CommunityRules()
                .padding(.vertical, 4)
        }
    }
}
