import SwiftUI

/// A form field as a card: caption label, the value in bold, an optional hint, and an error
/// state (red outline + message underneath; never an alert). Pass `isInvalid` instead of `error`
/// to mark a field red when its message is shown elsewhere (e.g. under a row of fields).
///
/// Two kinds: a picker-style box (`content`, read as one element with its label) and an input box
/// (`text:prompt:`), which builds the text field so VoiceOver gets a real text field named by the
/// caption, with the error or hint as its hint.
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
    /// An input box: the text field carries the caption, error and hint, so they're hidden here.
    private(set) var isInput = false
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

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
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .accessibilityHidden(isInput)
                }
                content
                    .font(.rounded(isCompact ? .subheadline : .body, .bold))
                    .foregroundStyle(Theme.ink)
                    // One line, shrinking a little to fit, until the text is too big for that:
                    // then it wraps, since shrinking would undo the size someone chose (A11Y-06).
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.75)
                    // A menu's label centers wrapped lines.
                    .multilineTextAlignment(.leading)
                if let error {
                    Text(verbatim: error)
                        .font(.rounded(.caption))
                        .foregroundStyle(Theme.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(isInput)
                } else if let hint {
                    Text(hint)
                        .font(.rounded(.caption))
                        .foregroundStyle(Theme.muted)
                        .accessibilityHidden(isInput)
                }
            }
            if showsChevron {
                Spacer(minLength: isCompact ? 2 : 4)
                RowAccessory(systemImage: "chevron.down", font: (isCompact ? Font.caption2 : .footnote).weight(.semibold), color: Theme.muted)
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
        // Input boxes aren't merged: merged with its label, a text field can read as static text
        // and fail to edit (A11Y-04).
        .accessibilityElement(children: isInput ? .contain : .combine)
    }

    private var outline: Color {
        if isInvalid { return Theme.error }
        return isFocused ? Theme.accent : Theme.hairline
    }
}

extension FieldBox {
    /// An input box: the caption names the text field and the error (or hint) is its hint, so it
    /// reads "Game name, text field, Add a name…" and still has a name once the prompt is gone.
    /// `field` adds the call site's modifiers (focus, keyboard, submit) to the text field itself.
    init(
        _ label: LocalizedStringKey,
        text: Binding<String>,
        prompt: Text,
        error: String? = nil,
        hint: LocalizedStringKey? = nil,
        isFocused: Bool = false,
        secure: Bool = false,
        field: (FieldInput) -> Content
    ) {
        let input = FieldInput(label: label, text: text, prompt: prompt, error: error, hint: hint, secure: secure)
        self.init(label, hint: hint, error: error, isFocused: isFocused) { field(input) }
        isInput = true
    }
}

extension FieldBox where Content == FieldInput {
    /// An input box with nothing to add to the text field.
    init(
        _ label: LocalizedStringKey,
        text: Binding<String>,
        prompt: Text,
        error: String? = nil,
        hint: LocalizedStringKey? = nil,
        isFocused: Bool = false,
        secure: Bool = false
    ) {
        self.init(label, text: text, prompt: prompt, error: error, hint: hint, isFocused: isFocused, secure: secure) { $0 }
    }
}

/// The text field an input `FieldBox` builds: named by the box's caption, with its error or hint.
struct FieldInput: View {
    let label: LocalizedStringKey
    @Binding var text: String
    let prompt: Text
    let error: String?
    let hint: LocalizedStringKey?
    let secure: Bool

    var body: some View {
        Group {
            if secure {
                SecureField(text: $text, prompt: prompt) { Text(label) }
            } else {
                TextField(text: $text, prompt: prompt) { Text(label) }
            }
        }
        .accessibilityLabel(Text(label))
        .accessibilityHint(spokenHint)
    }

    private var spokenHint: Text {
        if let error { return Text(verbatim: error) }
        if let hint { return Text(hint) }
        return Text(verbatim: "")
    }
}
