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

            Button(role: .close, action: onClose)
                .glassCircle()
        }
    }
}

extension View {
    /// The look every 1.0 sheet shares: page background, a grabber, rounded top corners.
    func sheetChrome(detents: Set<PresentationDetent> = [.large], background: Color = Theme.background) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationBackground(background)
            .presentationCornerRadius(34)
    }
}
