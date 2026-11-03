import SwiftUI

/// Small soft-green capsule for a game's status: "Open · 4 spots left", "3 going · 3 spots left", "Full".
struct StatusChip: View {
    var text: String
    var systemImage: String?

    init(_ text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(Theme.accent)
            }
            Text(text)
        }
        .font(.footnote.weight(.medium))
        // Ink, not accent: accent on accentSoft is only 4.1:1 at this size.
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Theme.accentSoft, in: .capsule)
    }
}

/// Interest on the Me card: "🏀 Basketball".
struct InterestChip: View {
    var sport: Sport

    var body: some View {
        HStack(spacing: 4) {
            Text(sport.emoji)
            Text(sport.name)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.chipSport, in: .capsule)
    }
}

/// Rounded-square tile with a game's sport emoji.
struct ActivityTile: View {
    var sport: Sport
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27)
            .fill(Theme.accentSoft)
            .frame(width: size, height: size)
            .overlay {
                Text(sport.emoji)
                    .font(.system(size: size * 0.55))
            }
            .accessibilityLabel(Text(sport.name))
    }
}

/// Selectable sport chip (onboarding "What do you play?", Edit profile & interests).
struct InterestToggle: View {
    var sport: Sport
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(sport.emoji)
                Text(sport.name)
                if isOn { Image(systemName: "checkmark").fontWeight(.semibold) }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(isOn ? Theme.chipSport : Theme.card, in: .capsule)
            .overlay(Capsule().strokeBorder(isOn ? Theme.pin.opacity(0.5) : Theme.hairline, lineWidth: isOn ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
