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
            .frame(maxWidth: .infinity, alignment: .leading)

            if #available(iOS 26, *) {
                Button(role: .close, action: onClose)
                    .glassCircle()
                    .accessibilityLabel("Close")
            } else {
                Button("Close", systemImage: "xmark", action: onClose)
                    .glassCircle()
            }
        }
    }
}

extension View {
    /// The look every 1.0 sheet shares: page background and a grabber. The corners are the
    /// system's, which follow the screen's own curve; a fixed radius clips against it.
    func sheetChrome(detents: Set<PresentationDetent> = [.large], background: Color = Theme.background) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationBackground(background)
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
