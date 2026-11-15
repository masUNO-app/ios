import SwiftUI

/// A form field as a card: caption label, the value in bold, an optional hint, and an error
/// state (red outline + message underneath; never an alert). Pass `isInvalid` instead of `error`
/// to mark a field red when its message is shown elsewhere (e.g. under a row of fields).
struct FieldBox<Content: View>: View {
    var label: LocalizedStringKey?
    var hint: LocalizedStringKey?
    /// Already-localized message (usually from a view model).
    var error: String?
    var isInvalid: Bool
    var showsChevron: Bool
    /// Green outline, as on a focused field.
    var isFocused: Bool
    /// Tighter padding and slightly smaller type, for three fields side by side.
    var isCompact: Bool
    @ViewBuilder var content: Content

    init(
        _ label: LocalizedStringKey?,
        hint: LocalizedStringKey? = nil,
        error: String? = nil,
        isInvalid: Bool = false,
        showsChevron: Bool = false,
        isFocused: Bool = false,
        isCompact: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.hint = hint
        self.error = error
        self.isInvalid = isInvalid || error != nil
        self.showsChevron = showsChevron
        self.isFocused = isFocused
        self.isCompact = isCompact
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                if let label {
                    Text(label)
                        .font(.rounded(.caption))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                content
                    .font(.rounded(isCompact ? .subheadline : .body, .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let error {
                    Text(verbatim: error)
                        .font(.rounded(.caption))
                        .foregroundStyle(Theme.error)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let hint {
                    Text(hint)
                        .font(.rounded(.caption))
                        .foregroundStyle(Theme.muted)
                }
            }
            if showsChevron {
                Spacer(minLength: isCompact ? 2 : 4)
                Image(systemName: "chevron.down")
                    .font((isCompact ? Font.caption2 : .footnote).weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, isCompact ? 11 : 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.field))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.field)
                .strokeBorder(outline, lineWidth: isInvalid || isFocused ? 1.5 : 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var outline: Color {
        if isInvalid { return Theme.error }
        return isFocused ? Theme.accent : Theme.hairline
    }
}
