import SwiftUI

/// The four Liquid Glass pills (SPEC §7.7.3). They're the native glass button styles with the
/// theme's tints, so they get the system's shape, press and disabled states.
enum PillStyle {
    /// Green: the one primary action on a screen.
    case primary
    /// Mint: the action next to it ("Details", "Not now", "Leave").
    case secondary
    /// Red fill: confirming something that can't be undone.
    case destructive
    /// Plain glass with an ink label: quiet actions ("Reset", "Show QR code").
    case quiet
    /// Plain glass with a red label: "Sign out", "Cancel game" before the confirmation.
    case quietDestructive
}

extension View {
    /// Styles a button as one of the app's pills. `expands` stretches it to the width it's given.
    func pill(_ style: PillStyle, expands: Bool = true, size: ControlSize = .large) -> some View {
        modifier(PillModifier(style: style, expands: expands, size: size))
    }

    /// Round glass button for an icon: close, bookmark, more.
    func glassCircle(size: ControlSize = .large) -> some View {
        labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(size)
            .tint(Theme.ink)
    }
}

private struct PillModifier: ViewModifier {
    var style: PillStyle
    var expands: Bool
    var size: ControlSize

    func body(content: Content) -> some View {
        let sized = content
            .controlSize(size)
            .buttonSizing(expands ? .flexible : .automatic)
            .font(.rounded(size == .large ? .headline : .subheadline, .bold))

        switch style {
        case .primary:
            sized.buttonStyle(.glassProminent).tint(Theme.accent)
        case .secondary:
            sized.buttonStyle(.glassProminent).tint(Theme.accentSoft).foregroundStyle(Theme.ink)
        case .destructive:
            sized.buttonStyle(.glassProminent).tint(Theme.destructive)
        case .quiet:
            sized.buttonStyle(.glass).tint(Theme.ink)
        case .quietDestructive:
            sized.buttonStyle(.glass).tint(Theme.destructive)
        }
    }
}

/// Radio row in its own card: report reasons, the location setting.
struct OptionRow: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(verbatim: title)
                    .font(.rounded(.callout, .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.muted.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .cardSurface(radius: 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Small grey "Optional" tag next to a field's question.
struct OptionalTag: View {
    var body: some View {
        Text("Optional")
            .font(.rounded(.caption))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.separator, in: .capsule)
    }
}
