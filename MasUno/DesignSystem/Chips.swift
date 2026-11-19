import SwiftUI

/// A sport in its own color: "🏀 Basketball" (Me › Plays, Welcome).
struct SportChip: View {
    var sport: Activity

    var body: some View {
        SportLabel(sport: sport)
            .inkOnColor()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minHeight: 28)
            .appGlass(in: .capsule, tint: sport.color)
    }
}

/// Selectable sport chip (Make it yours, Edit profile, Filter games): the sport's color when
/// it's on, plain white when it's off. With Differentiate Without Color, a checkmark too: some
/// sport colors are hard to tell from white (A11Y-22).
struct SportToggle: View {
    var sport: Activity
    var isOn: Bool
    var action: () -> Void
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Button(action: action) {
            SportLabel(sport: sport, showsCheckmark: isOn && differentiateWithoutColor)
                // Off, it's plain glass that follows dark mode.
                .inkOnColor(isOn)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: 32)
                .appGlass(in: .capsule, tint: isOn ? sport.color : nil, interactive: true)
                // 44 pt tall to tap; the rows don't move apart (A11Y-19).
                .tapTarget(.vertical, 6)
        }
        .buttonStyle(.plain)
        .padding(.vertical, -6)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// "🏀 Basketball", the inside of `SportChip` and `SportToggle`. Read as the name alone: next to
/// it the emoji would be read too ("basketball, Basketball", A11Y-11).
private struct SportLabel: View {
    var sport: Activity
    /// The toggle's "on" mark; its Selected trait already says so to VoiceOver.
    var showsCheckmark = false

    var body: some View {
        HStack(spacing: 4) {
            if showsCheckmark {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
            }
            Text(sport.emoji)
                .accessibilityHidden(true)
            Text(sport.name)
        }
        .font(.rounded(.footnote, .bold))
        .foregroundStyle(Theme.ink)
        // Left alone, the name would take the whole chip's frame, emoji and all, and the
        // accessibility audit would measure the emoji's colors as its contrast.
        .accessibilityElement(children: .contain)
    }
}

/// Rounded-square tile in the sport's color with its emoji (search results).
struct ActivityTile: View {
    var sport: Activity
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3)
            .fill(sport.color)
            .frame(width: size, height: size)
            .overlay {
                Text(sport.emoji)
                    .font(.system(size: size * 0.5))
            }
            .accessibilityLabel(Text(sport.name))
    }
}

/// 36 pt colored tile with a symbol, leading a settings row.
struct IconTile: View {
    var systemImage: String
    var color: Color
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.tile)
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityHidden(true)
    }
}

/// A green symbol and a title on a light capsule, on the Me card: "Verified student", and "Beta
/// tester" for people on TestFlight builds (it grants nothing, it's a thank-you).
struct ProfileBadge: View {
    var title: LocalizedStringKey
    var systemImage: String
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(BadgeLabelStyle())
            .font(.rounded(.footnote, .bold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, typeSize.isAccessibilitySize ? 2 : 0)
            .frame(minHeight: 24)
            .background { Capsule().fill(.white).contrastOpacity(0.75) }
    }
}

/// Small uppercase tag after a name: "HOST", "BETA" (Who's going).
struct TagText: View {
    var title: LocalizedStringKey
    var color: Color

    init(_ title: LocalizedStringKey, color: Color) {
        self.title = title
        self.color = color
    }

    var body: some View {
        Text(title)
            .textCase(.uppercase)
            .font(.rounded(.caption2, .heavy))
            .tracking(0.4)
            .foregroundStyle(color)
    }
}

private struct BadgeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.foregroundStyle(Theme.accent)
            configuration.title
        }
    }
}

/// Icon + text row on cards: the icon keeps a fixed width so rows line up.
struct IconRowLabelStyle: LabelStyle {
    var iconWidth: CGFloat = 18
    var spacing: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            configuration.icon.frame(width: iconWidth)
            configuration.title
        }
    }
}
