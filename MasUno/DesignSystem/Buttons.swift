import SwiftUI

/// The app's pill actions (SPEC §7.7.3), using native Liquid Glass on iOS 26+ and themed
/// capsule buttons on iOS 18.
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
    @ViewBuilder
    func glassCircle(size: ControlSize = .large) -> some View {
        if #available(iOS 26, *) {
            labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(size)
                .tint(Theme.ink)
        } else {
            labelStyle(.iconOnly)
                .buttonStyle(AdaptiveCircleButtonStyle())
                .foregroundStyle(Theme.ink)
                .controlSize(size)
        }
    }
}

extension EnvironmentValues {
    /// Every pill fills the width it's given, whatever its call site asked for: set where pills
    /// stack, so a narrow "Leave" doesn't sit alone above a full-width "Group chat" (A11Y-06).
    @Entry var pillsExpand = false
}

private struct PillModifier: ViewModifier {
    var style: PillStyle
    var expands: Bool
    var size: ControlSize
    @Environment(\.pillsExpand) private var pillsExpand
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let expands = expands || pillsExpand
        if #available(iOS 26, *) {
            modern(content: content, expands: expands)
        } else {
            content
                .font(.rounded(size == .large ? .headline : .subheadline, .bold))
                .buttonStyle(CapsuleActionStyle(style: style, expands: expands, size: size))
        }
    }

    @available(iOS 26, *)
    @ViewBuilder
    private func modern(content: Content, expands: Bool) -> some View {
        let sized = content
            .controlSize(size)
            .buttonSizing(expands ? .flexible : .automatic)
            .font(.rounded(size == .large ? .headline : .subheadline, .bold))

        switch style {
        case .primary:
            sized.buttonStyle(.glassProminent).tint(Theme.accent)
        case .secondary:
            // Mint is 1.06:1 on the background; the ink label says it's a button, and under
            // Increase Contrast an edge does too (A11Y-16). iOS 18's capsule has the hairline.
            sized.buttonStyle(.glassProminent).tint(Theme.accentSoft).foregroundStyle(Theme.ink)
                .overlay {
                    if contrast == .increased {
                        Capsule().strokeBorder(Theme.hairline).allowsHitTesting(false)
                    }
                }
        case .destructive:
            sized.buttonStyle(.glassProminent).tint(Theme.destructive)
        case .quiet:
            sized.buttonStyle(.glass).tint(Theme.ink)
        case .quietDestructive:
            sized.buttonStyle(.glass).tint(Theme.destructive)
        }
    }
}

private struct CapsuleActionStyle: ButtonStyle {
    var style: PillStyle
    var expands: Bool
    var size: ControlSize
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, size == .large ? 20 : 14)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: size == .large ? Theme.buttonHeight : 38)
            .foregroundStyle(foreground)
            .background(background, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
            .contentShape(.capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch style {
        case .primary, .destructive: Theme.onAccent
        case .secondary, .quiet: Theme.ink
        case .quietDestructive: Theme.destructive
        }
    }

    private var background: Color {
        switch style {
        case .primary: Theme.accent
        case .secondary: Theme.accentSoft
        case .destructive: Theme.destructive
        case .quiet, .quietDestructive: Theme.card
        }
    }
}

/// The green pill, with a spinner while a request is out. VoiceOver keeps the title while it spins
/// and says "Working" (A11Y-10); a bare `ProgressView` reads as "In progress" with no name.
struct WorkingButton: View {
    var title: Text
    var isWorking = false
    var action: () -> Void

    init(_ title: LocalizedStringKey, isWorking: Bool = false, action: @escaping () -> Void) {
        self.init(title: Text(title), isWorking: isWorking, action: action)
    }

    /// For a title that's already localized.
    init(verbatim title: String, isWorking: Bool = false, action: @escaping () -> Void) {
        self.init(title: Text(verbatim: title), isWorking: isWorking, action: action)
    }

    private init(title: Text, isWorking: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isWorking = isWorking
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if isWorking { ProgressView().tint(Theme.onAccent) } else { title }
        }
        // The onboarding steps are tinted ink for the back button; this stays green.
        .pill(.primary)
        .disabled(isWorking)
        .accessibilityLabel(title)
        .accessibilityValue(isWorking ? Text("Working") : Text(verbatim: ""))
    }
}

/// Two pills side by side in equal widths, or stacked when a label would wrap (the folded iPhone
/// Duo, large text).
struct PillPair<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            EqualWidthRow(spacing: spacing) { content }
            VStack(spacing: spacing) { content }
        }
    }
}

/// Buttons side by side in equal widths, like an `HStack` of flexible pills. Its ideal width is
/// the widest label's times the count, so `ViewThatFits` only picks it when no label would wrap:
/// an `HStack` fits on the sum of its labels, then splits the space evenly and wraps the longer one.
private struct EqualWidthRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let gaps = spacing * CGFloat(subviews.count - 1)
        let width: CGFloat
        if let proposed = proposal.width, proposed.isFinite {
            width = proposed
        } else {
            let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
            width = widest * CGFloat(subviews.count) + gaps
        }
        let column = ProposedViewSize(width: (width - gaps) / CGFloat(subviews.count), height: proposal.height)
        let height = subviews.map { $0.sizeThatFits(column).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let gaps = spacing * CGFloat(subviews.count - 1)
        let column = (bounds.width - gaps) / CGFloat(subviews.count)
        var x = bounds.minX
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: column, height: bounds.height))
            x += column + spacing
        }
    }
}

/// The grey ⓧ at the end of a search field: `muted` at 80%, 4:1 on a card (A11Y-16).
struct ClearFieldButton: View {
    var action: () -> Void

    var body: some View {
        Button("Clear search", systemImage: "xmark.circle.fill", action: action)
            .labelStyle(.iconOnly)
            .foregroundStyle(Theme.muted)
            .contrastOpacity(0.8)
            .buttonStyle(.plain)
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
                    .foregroundStyle(isSelected ? Theme.accent : Theme.muted)
                    // The empty ring at 80% is 4:1 on the card; at 50% it was 2.2 (A11Y-16).
                    .contrastOpacity(isSelected ? 1 : 0.8)
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

/// A field's question with the Optional tag at the end of the line, or under it at accessibility
/// sizes, where both wouldn't fit on one (A11Y-06).
struct OptionalQuestion: View {
    var title: LocalizedStringKey
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout())
        layout {
            Text(title)
                .font(.rounded(.footnote, .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            if !typeSize.isAccessibilitySize { Spacer() }
            OptionalTag()
        }
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
