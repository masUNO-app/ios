import SwiftUI

/// The chevron or arrow at the end of a row. Hidden from VoiceOver (A11Y-12): the row's button
/// trait already says it goes somewhere, and a row that leaves the app says so in a hint.
struct RowAccessory: View {
    var systemImage = "chevron.right"
    var font: Font = .footnote.weight(.semibold)
    var color: Color = Theme.muted.opacity(0.6)

    var body: some View {
        Image(systemName: systemImage)
            .font(font)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// The 1 pt line between rows in a list card.
struct RowDivider: View {
    var body: some View {
        Theme.separator.frame(height: 1)
    }
}
