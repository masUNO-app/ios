import SwiftUI

/// Boxed form field with a caption label, optional hint, and an error state
/// (red border + message underneath), as in the Add/Edit event sheet.
struct FieldBox<Content: View>: View {
    var label: LocalizedStringKey?
    var hint: LocalizedStringKey?
    var error: LocalizedStringKey?
    var showsChevron: Bool
    @ViewBuilder var content: Content

    init(
        _ label: LocalizedStringKey?,
        hint: LocalizedStringKey? = nil,
        error: LocalizedStringKey? = nil,
        showsChevron: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.hint = hint
        self.error = error
        self.showsChevron = showsChevron
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                if let label {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                content
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.error)
                } else if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            if showsChevron {
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.field))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.field)
                .strokeBorder(error == nil ? Theme.hairline : Theme.error, lineWidth: error == nil ? 1 : 1.5)
        }
        .accessibilityElement(children: .combine)
    }
}
