import SwiftUI

/// Cards side by side when there's room for two at `Theme.cardMinWidth`, one per row otherwise:
/// one column on a phone, folded or in portrait on iPhone Duo, two in landscape.
/// It goes by the width it's given, not the size class, which doesn't follow the Duo's pose.
/// Cards in a row can differ in height; they line up at the top.
struct CardGrid<Content: View>: View {
    /// Between rows: a screen can match the gaps it had as a stack.
    var spacing: CGFloat = 16
    /// Between columns side by side.
    var columnSpacing: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: Theme.cardMinWidth), spacing: columnSpacing, alignment: .top)],
            alignment: .leading, spacing: spacing
        ) {
            content
        }
    }
}
