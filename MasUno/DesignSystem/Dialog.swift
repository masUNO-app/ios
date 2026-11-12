import SwiftUI

/// The 1.0 dialog: a card in the middle of the screen with an icon, a title, a sentence or two
/// and stacked pills (Figma "Leave game", "Before you chat", "Block", "Sign out"…). Present it
/// with `.dialog(isPresented:)` or `.dialog(item:)`.
struct DialogCard<Content: View>: View {
    enum Tone {
        /// Mint circle, green icon.
        case friendly
        /// Soft red circle, red icon, red confirm button.
        case destructive
        /// A circle in a soft version of this color with an ink icon (the location primer's lavender).
        case tinted(Color)

        var isDestructive: Bool {
            if case .destructive = self { return true }
            return false
        }

        var icon: Color {
            switch self {
            case .friendly: Theme.accent
            case .destructive: Theme.destructive
            case .tinted: Theme.ink
            }
        }

        var iconBackground: Color {
            switch self {
            case .friendly: Theme.accentSoft
            case .destructive: Theme.destructiveSoft
            case .tinted(let color): color.opacity(0.4)
            }
        }
    }

    @Environment(\.closeDialog) private var closeDialog

    var systemImage: String
    var tone: Tone = .friendly
    var title: Text
    var message: Text?
    /// Fine print under the message: "This can't be undone."
    var footnote: Text?
    var confirm: DialogAction
    var cancel: DialogAction?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.medium))
                .foregroundStyle(tone.icon)
                .frame(width: 48, height: 48)
                .background(tone.iconBackground, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                title
                    .font(.rounded(.title2, .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                message?
                    .font(.rounded(.subheadline))
                    .foregroundStyle(Theme.muted)
            }

            content

            footnote?
                .font(.rounded(.caption))
                .foregroundStyle(Theme.muted)

            VStack(spacing: 10) {
                Button(confirm.title) { closeDialog(confirm.perform) }
                    .pill(tone.isDestructive ? .destructive : .primary)
                if let cancel {
                    Button(cancel.title) { closeDialog(cancel.perform) }
                        .pill(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .multilineTextAlignment(.leading)
        .padding(22)
        .frame(maxWidth: 354, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.dialog))
        .shadow(color: Theme.shadow, radius: 24, y: 8)
    }
}

/// A button on a `DialogCard`. The dialog closes first, then `perform` runs.
struct DialogAction {
    var title: LocalizedStringKey
    var perform: () -> Void

    init(_ title: LocalizedStringKey, perform: @escaping () -> Void = {}) {
        self.title = title
        self.perform = perform
    }
}

extension DialogCard where Content == EmptyView {
    init(
        systemImage: String, tone: Tone = .friendly, title: Text, message: Text? = nil,
        footnote: Text? = nil, confirm: DialogAction, cancel: DialogAction? = nil
    ) {
        self.init(
            systemImage: systemImage, tone: tone, title: title, message: message,
            footnote: footnote, confirm: confirm, cancel: cancel
        ) { EmptyView() }
    }
}

extension EnvironmentValues {
    /// Fades the dialog out, then runs the action (so an action that presents something else
    /// doesn't fight the dismissal).
    @Entry var closeDialog: (@escaping () -> Void) -> Void = { $0() }
}

extension View {
    /// Presents a `DialogCard` over everything, sheets included, on a scrim.
    /// - Parameter isDismissable: tapping the scrim closes it. Off for choices that need an answer.
    func dialog(
        isPresented: Binding<Bool>, isDismissable: Bool = true,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        modifier(DialogPresenter(
            item: Binding<DialogFlag?>(
                get: { isPresented.wrappedValue ? DialogFlag() : nil },
                set: { if $0 == nil { isPresented.wrappedValue = false } }
            ),
            isDismissable: isDismissable
        ) { _ in content() })
    }

    func dialog<Item: Identifiable>(
        item: Binding<Item?>, isDismissable: Bool = true,
        @ViewBuilder content: @escaping (Item) -> some View
    ) -> some View {
        modifier(DialogPresenter(item: item, isDismissable: isDismissable, card: content))
    }
}

private struct DialogFlag: Identifiable {
    let id = 0
}

/// A full-screen cover with a clear background and no slide, so the card can fade and scale in
/// by itself. A cover (rather than an overlay) is what lets it sit above sheets and trap focus.
private struct DialogPresenter<Item: Identifiable, Card: View>: ViewModifier {
    @Binding var item: Item?
    var isDismissable: Bool
    @ViewBuilder var card: (Item) -> Card

    /// What the cover shows. Trails `item` so the card can animate out before the cover goes.
    @State private var presented: Item?
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $presented) { item in
                ZStack {
                    Theme.scrim
                        .ignoresSafeArea()
                        .opacity(isShown ? 1 : 0)
                        .onTapGesture { if isDismissable { close {} } }
                        .accessibilityHidden(true)

                    card(item)
                        .environment(\.closeDialog) { close($0) }
                        .padding(.horizontal, 24)
                        .scaleEffect(isShown ? 1 : 0.92)
                        .opacity(isShown ? 1 : 0)
                        .accessibilityAddTraits(.isModal)
                }
                .presentationBackground(.clear)
                .onAppear { withAnimation(.spring(duration: 0.3, bounce: 0.2)) { isShown = true } }
            }
            .onChange(of: item?.id, initial: true) {
                if let item {
                    withoutCoverAnimation { presented = item }
                } else if presented != nil {
                    close {}
                }
            }
    }

    private func close(_ then: @escaping () -> Void) {
        withAnimation(.easeOut(duration: 0.16)) { isShown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(170))
            withoutCoverAnimation { presented = nil }
            item = nil
            then()
        }
    }

    private func withoutCoverAnimation(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }
}
