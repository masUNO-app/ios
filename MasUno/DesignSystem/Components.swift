import SwiftUI

/// Initial-in-a-circle avatar (no profile photos until there's a backend).
struct Avatar: View {
    var name: String
    var size: CGFloat = 32

    var body: some View {
        Circle()
            .fill(Theme.orangeSoft)
            .frame(width: size, height: size)
            .overlay {
                if name == Person.you {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(Theme.orange)
                } else {
                    Text(name.prefix(1))
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(Theme.orange)
                }
            }
    }
}

/// Rounded-square icon tile used on plan cards.
struct EventIconTile: View {
    var sport: Sport
    var size: CGFloat = 52

    var body: some View {
        if let symbol = sport.symbol {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.orangeSoft)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(Theme.orange)
                }
        } else {
            Text(sport.emoji)
                .font(.system(size: size * 0.9))
                .frame(width: size, height: size)
        }
    }
}

/// Orange capsule CTA ("Open group chat ›", "RSVP Now").
struct OrangeCapsuleStyle: ButtonStyle {
    var foreground: Color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [Color(hex: 0xF08A2C), Theme.orange], startPoint: .top, endPoint: .bottom)
                )
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension ButtonStyle where Self == OrangeCapsuleStyle {
    static var orangeCapsule: OrangeCapsuleStyle { .init() }
}

nonisolated struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
