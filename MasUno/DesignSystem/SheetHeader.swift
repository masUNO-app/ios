import SwiftUI

/// Top of a 1.0 sheet: title and one line under it on the left, a glass close button on the right.
struct SheetHeader: View {
    var title: Text
    var subtitle: Text?
    /// Bigger title, for sheets that are mostly a list ("Who's going").
    var isProminent = false
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.rounded(isProminent ? .title : .title2, .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                subtitle?
                    .font(.rounded(.subheadline))
                    .foregroundStyle(Theme.muted)
            }
            // Never squeezed into "…" by a list under it in a short sheet (A11Y-06).
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Esc on a hardware keyboard closes the sheet (A11Y-20).
            if #available(iOS 26, *) {
                Button(role: .close, action: onClose)
                    .glassCircle()
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close")
            } else {
                Button("Close", systemImage: "xmark", action: onClose)
                    .glassCircle()
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}

extension View {
    /// The look every 1.0 sheet shares: page background and a grabber. The corners are the
    /// system's, which follow the screen's own curve; a fixed radius clips against it.
    func sheetChrome(detents: Set<PresentationDetent> = [.large], background: Color = Theme.background) -> some View {
        modifier(SheetChrome(detents: detents))
            .presentationDragIndicator(.visible)
            .presentationBackground(background)
    }
}

/// At accessibility sizes every sheet opens full height: a part-height one shows a few lines
/// of text (A11Y-06).
private struct SheetChrome: ViewModifier {
    var detents: Set<PresentationDetent>
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.presentationDetents(typeSize.isAccessibilitySize ? [.large] : detents)
    }
}

extension PresentationDetent {
    /// Half height, but never shorter than one whole game card with its buttons: on short
    /// windows (iPhone Duo folded, or open in landscape) `.medium` cuts the buttons off.
    static let oneCard = Self.custom(OneCardDetent.self)
}

private struct OneCardDetent: CustomPresentationDetent {
    /// Sheet header plus one `GameCard`, with room for a two-line title.
    private static let cardHeight: CGFloat = 440

    static func height(in context: Context) -> CGFloat? {
        min(max(context.maxDetentValue / 2, cardHeight), context.maxDetentValue)
    }
}
