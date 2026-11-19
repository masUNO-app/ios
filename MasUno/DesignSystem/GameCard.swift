import SwiftUI

/// The 1.0 game card (SPEC §7.7.3): a header in the sport's color with the sport line, title,
/// one status line and the people + "+1" tokens; then time and place; then up to two actions.
/// The map popup, Me (Going / Hosting / Earlier), Saved games and Invite a friend all use it.
struct GameCard<Accessory: View, Actions: View>: View {
    var event: Game
    var lineup: Lineup
    /// "Room for 4 more", "You're in · room for 3 more", "3 joined · room for 6 more"…
    var status: String
    /// "Today, 7:35 PM · starts in 35 min".
    var time: String
    /// Grey header instead of the sport's color: cancelled and past games.
    var isMuted = false
    /// Floating cards (the map popup, sheets) lift off what's behind them.
    var isFloating = false
    /// Opens the game: a tap anywhere outside the card's buttons, or the summary with VoiceOver.
    /// Nil on the popup, which has Details. The card itself is never a button, since it holds buttons.
    var onOpen: (() -> Void)? = nil
    /// The same as some of the buttons below, as VoiceOver actions on the summary.
    var shortcuts: [GameCardShortcut] = []
    /// Moves VoiceOver to the summary when set: the map popup takes focus as it opens.
    var summaryFocus: AccessibilityFocusState<Bool>.Binding? = nil
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var actions: Actions
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The sport emoji in the header: 18 pt at the default size, growing with the host line.
    @ScaledMetric(relativeTo: .footnote) private var emojiSize: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                header
                details
            }
            // One VoiceOver stop for everything above the buttons. It sits behind them so the
            // accessory (the popup's bookmark) stays its own button.
            .background { summary }
            if Actions.self != EmptyView.self {
                RowDivider()
                actionRow
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
            }
        }
        .background(Theme.card)
        .clipShape(.rect(cornerRadius: Theme.Radius.dialog))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.dialog).strokeBorder(Theme.separator))
        .shadow(color: Theme.shadowInk.opacity(isFloating ? 0.22 : 0.08), radius: isFloating ? 14 : 5, y: isFloating ? 8 : 2)
        .modifier(OpensOnTap(action: onOpen))
        .accessibilityElement(children: .contain)
    }

    /// At accessibility sizes, side by side only while both labels fit on one line; otherwise
    /// stacked, each the card's width, rather than wrapped or cut off (A11Y-06).
    @ViewBuilder
    private var actionRow: some View {
        if typeSize.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actions }
                VStack(spacing: 10) { actions }
                    .environment(\.pillsExpand, true)
            }
        } else {
            HStack(spacing: 10) { actions }
        }
    }

    @ViewBuilder
    private var summary: some View {
        let element = Color.clear
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: event.cardSummary(status: status, time: time, lineup: lineup)))
            .accessibilityActions {
                ForEach(shortcuts) { shortcut in
                    Button(shortcut.name, action: shortcut.perform)
                }
            }
            .accessibilitySortPriority(1)
            .modifier(FocusesSummary(focus: summaryFocus))
        // Without onOpen it's text: a default action alone would make it read as a button.
        if let onOpen {
            element
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("Opens the game"))
                .accessibilityInputLabels([Text(verbatim: event.title)])
                .accessibilityAction { onOpen() }
        } else {
            element
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(event.activity.emoji)
                    .font(.system(size: emojiSize))
                    .saturation(isMuted ? 0 : 1)
                Text(verbatim: event.hostLine)
                    .font(.rounded(.footnote))
                    .lineLimit(lineLimit(1))
            }
            .accessibilityHidden(true)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: event.title)
                        .font(.rounded(.title2, .bold))
                        .lineLimit(lineLimit(2))
                        // Shrinking would undo the text size someone chose.
                        .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.8)
                    Text(verbatim: status)
                        .font(.rounded(.subheadline))
                        .lineLimit(lineLimit(2))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
                accessory
            }

            TokenRow(lineup: lineup, size: 32, openFillOpacity: isMuted ? 0.9 : 0.7)
                .accessibilityHidden(true)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isMuted ? Theme.separator : event.activity.color)
        // The grey header follows dark mode; the sport color keeps its ink.
        .inkOnColor(!isMuted)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(verbatim: time)
            } icon: {
                Image(systemName: "clock").accessibilityHidden(true)
            }
            Label {
                Text(verbatim: event.place.name)
            } icon: {
                PlaceIcon(size: 17)
            }
        }
        .font(.rounded(.subheadline))
        .foregroundStyle(Theme.ink)
        .labelStyle(IconRowLabelStyle())
        .lineLimit(lineLimit(1))
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

extension GameCard {
    /// `lines` at most, until the text is too big to fit anything in so few (A11Y-06).
    fileprivate func lineLimit(_ lines: Int) -> Int? {
        typeSize.isAccessibilitySize ? nil : lines
    }
}

/// A tap anywhere on the card opens it. Buttons inside win over this tap, as they did over the link
/// or button that used to wrap the card. Without an action the card takes no tap at all, so the
/// popup's map annotation behaves as before.
private struct OpensOnTap: ViewModifier {
    var action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content
                .contentShape(.rect(cornerRadius: Theme.Radius.dialog))
                .onTapGesture(perform: action)
        } else {
            content
        }
    }
}

private struct FocusesSummary: ViewModifier {
    var focus: AccessibilityFocusState<Bool>.Binding?

    func body(content: Content) -> some View {
        if let focus {
            content.accessibilityFocused(focus)
        } else {
            content
        }
    }
}

/// A VoiceOver action on a card's summary, for a button on the card (A11Y-26).
struct GameCardShortcut: Identifiable {
    var name: String
    var perform: () -> Void
    var id: String { name }
}

extension Game {
    /// A card in one VoiceOver stop: "After-work hoops, Basketball, Hosted by Alex R., Room for 4 more,
    /// Today, 7:35 PM, starts in 35 min, Tec basketball courts, Alex R., Ricardo T., and 4 open spots".
    /// Commas instead of the card's "·", which VoiceOver reads without a pause.
    func cardSummary(status: String, time: String, lineup: Lineup) -> String {
        [title, hostLine, status, time, place.name, lineup.accessibilityLabel]
            .map { $0.replacingOccurrences(of: " · ", with: ", ").replacingOccurrences(of: "\n", with: ", ") }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

extension GameCard where Accessory == EmptyView {
    init(
        event: Game, lineup: Lineup, status: String, time: String, isMuted: Bool = false,
        isFloating: Bool = false, onOpen: (() -> Void)? = nil, shortcuts: [GameCardShortcut] = [],
        @ViewBuilder actions: () -> Actions
    ) {
        self.init(
            event: event, lineup: lineup, status: status, time: time, isMuted: isMuted,
            isFloating: isFloating, onOpen: onOpen, shortcuts: shortcuts, accessory: { EmptyView() }, actions: actions
        )
    }
}

extension GameCard where Accessory == EmptyView, Actions == EmptyView {
    init(event: Game, lineup: Lineup, status: String, time: String, isFloating: Bool = false) {
        self.init(
            event: event, lineup: lineup, status: status, time: time, isFloating: isFloating,
            accessory: { EmptyView() }, actions: { EmptyView() }
        )
    }
}

/// The popup's tail: a small rounded point from the card's bottom edge down to its pin.
nonisolated struct CalloutTail: Shape {
    func path(in rect: CGRect) -> Path {
        let tip = CGPoint(x: rect.midX, y: rect.maxY)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: tip.x + 2.6, y: tip.y - 2.2))
        path.addQuadCurve(to: CGPoint(x: tip.x - 2.6, y: tip.y - 2.2), control: tip)
        path.closeSubpath()
        return path
    }
}
