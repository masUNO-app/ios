import SwiftUI

/// A sport in its own color: "🏀 Basketball" (Me › Plays, Welcome).
struct SportChip: View {
    var sport: Activity

    var body: some View {
        HStack(spacing: 4) {
            Text(sport.emoji)
            Text(sport.name)
        }
        .font(.rounded(.footnote, .bold))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .glassEffect(.regular.tint(sport.color), in: .capsule)
    }
}

/// Selectable sport chip (Make it yours, Edit profile, Filter games): the sport's color when
/// it's on, plain white when it's off.
struct SportToggle: View {
    var sport: Activity
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(sport.emoji)
                Text(sport.name)
            }
            .font(.rounded(.footnote, .bold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .glassEffect(isOn ? .regular.tint(sport.color).interactive() : .regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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

/// "Verified student" on the Me card: a green seal on a light capsule.
struct VerifiedBadge: View {
    var body: some View {
        Label("Verified student", systemImage: "checkmark.seal.fill")
            .labelStyle(BadgeLabelStyle())
            .font(.rounded(.footnote, .bold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(.white.opacity(0.75), in: .capsule)
    }
}

/// "Beta tester" next to "Verified student" on the Me card, for people on TestFlight builds. Same
/// capsule as `VerifiedBadge`; it grants nothing, it's a thank-you.
struct BetaBadge: View {
    var body: some View {
        Label("Beta tester", systemImage: "testtube.2")
            .labelStyle(BadgeLabelStyle())
            .font(.rounded(.footnote, .bold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(.white.opacity(0.75), in: .capsule)
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
