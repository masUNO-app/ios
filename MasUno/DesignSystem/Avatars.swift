import SwiftUI

/// Initials in a soft-green circle. No profile photos during the program.
struct Avatar: View {
    var name: String
    var size: CGFloat = 32

    var body: some View {
        Circle()
            .fill(Theme.accentSoft)
            .frame(width: size, height: size)
            .overlay {
                if name == Person.you {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(Theme.accent)
                } else {
                    Text(Self.initials(of: name))
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .minimumScaleFactor(0.5)
                }
            }
            .accessibilityHidden(true)
    }

    /// "Leo Park" → "LP", "Maya" → "M".
    static func initials(of name: String) -> String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

/// Overlapping avatars with a "+N" overflow bubble.
struct AvatarStack: View {
    var names: [String]
    var maxVisible = 3
    var size: CGFloat = 28

    var body: some View {
        let visible = names.prefix(maxVisible)
        let overflow = names.count - visible.count

        HStack(spacing: -size * 0.3) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, name in
                Avatar(name: name, size: size)
                    .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
            }
            if overflow > 0 {
                Circle()
                    .fill(Theme.accentSoft)
                    .frame(width: size, height: size)
                    .overlay {
                        Text("+\(overflow)")
                            .font(.system(size: size * 0.38, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(names.formatted(.list(type: .and))))
    }
}
