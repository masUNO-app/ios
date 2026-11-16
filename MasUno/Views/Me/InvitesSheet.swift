import SwiftUI

/// Your invite codes (N37): masUNO is invite-only for now, and each code lets one friend skip the
/// waitlist. An unused code can be copied or shared; a used one stays on the list, muted, with who
/// used it.
struct InvitesSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(
                    title: Text("Invites"),
                    subtitle: Text("masUNO is invite-only for now. Each code lets one friend skip the waitlist.")
                ) { dismiss() }

                if store.invites.isEmpty {
                    EmptyCard(title: "No invites yet", message: "Pull down on Me to try again.") {}
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.invites) { invite in
                            InviteCodeRow(invite: invite)
                            if invite.id != store.invites.last?.id { Theme.separator.frame(height: 1) }
                        }
                    }
                    .padding(.vertical, 4)
                    .cardSurface()
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 22)
            .padding(.bottom, 24)
            .readableColumn()
        }
        .scrollBounceBehavior(.basedOnSize)
        .task { await store.loadInvites() }
        .sheetChrome(detents: [.medium, .large])
    }
}

/// One code, with "Not used yet" or who used it under it. Copy and share only while it's unused.
private struct InviteCodeRow: View {
    var invite: Invite
    @State private var hasCopied = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: invite.displayCode)
                    .font(.system(.title3, design: .rounded, weight: .bold).monospaced())
                    .foregroundStyle(invite.isUsed ? Theme.muted : Theme.ink)
                Text(verbatim: status)
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !invite.isUsed {
                Button(hasCopied ? "Copied" : "Copy code", systemImage: hasCopied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = invite.code
                    hasCopied = true
                }
                .glassCircle()
                .sensoryFeedback(.success, trigger: hasCopied)
                .task(id: hasCopied) {
                    guard hasCopied else { return }
                    try? await Task.sleep(for: .seconds(2))
                    hasCopied = false
                }

                ShareLink(item: shareMessage) {
                    Label("Share code", systemImage: "square.and.arrow.up")
                }
                .glassCircle()
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 66)
        .accessibilityElement(children: invite.isUsed ? .combine : .contain)
    }

    private var status: String {
        guard invite.isUsed else { return String(localized: "Not used yet") }
        guard let name = invite.redeemedBy else { return String(localized: "Used") }
        return String(localized: "Used by \(name)")
    }

    /// "Skip the masUNO waitlist with my invite code ABCD-EFGH: <App Store link>", without the link
    /// when the app doesn't have one.
    private var shareMessage: String {
        let message = String(localized: "Skip the masUNO waitlist with my invite code \(invite.displayCode)")
        guard let url = AppConfig.inviteURL else { return message + "." }
        return message + ": " + url.absoluteString
    }
}
