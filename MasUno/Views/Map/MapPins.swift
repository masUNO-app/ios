import SwiftUI

/// Blue sport pin (Figma "Sports event pin"). "Soon" when it starts within the hour;
/// grows with a halo when selected; dims while another game's popup is open.
struct EventPin: View {
    var event: SportsEvent
    var now: Date
    var isSelected: Bool
    var isDimmed: Bool

    var body: some View {
        VStack(spacing: 6) {
            if event.isSoon(now: now) {
                Text("Soon")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
            }

            VStack(spacing: -6) {
                ZStack {
                    Circle().fill(Theme.pin).frame(width: 46, height: 46)
                    Text(event.sport.emoji).font(.system(size: 30))
                }
                Triangle().fill(Theme.pin).frame(width: 18, height: 14)
            }
            .shadow(color: Theme.shadow, radius: 3, y: 3)
            .background(alignment: .bottom) {
                // Halo on the ground under the selected pin.
                Ellipse()
                    .fill(Theme.pin.opacity(0.25))
                    .overlay(Ellipse().strokeBorder(Theme.pin.opacity(0.4)))
                    .frame(width: 40, height: 14)
                    .offset(y: 6)
                    .opacity(isSelected ? 1 : 0)
            }
        }
        .scaleEffect(isSelected ? 1.15 : 1, anchor: .bottom)
        .opacity(isDimmed ? 0.45 : 1)
        .animation(.snappy, value: isSelected)
        .animation(.snappy, value: isDimmed)
        .contentShape(.rect)
        .accessibilityLabel(Text("\(event.sport.name): \(event.title)"))
    }
}

/// "You" marker: your avatar in a green ring (Figma "User location pin").
struct UserPin: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Avatar(name: Person.you, size: 40)
                .padding(3)
                .background(Theme.card, in: .circle)
                .padding(6)
                .background(Theme.accent.opacity(0.18), in: .circle)
            Circle()
                .fill(Theme.accent)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                .offset(x: -6, y: -6)
        }
        .shadow(color: Theme.shadow, radius: 3, y: 2)
        .allowsHitTesting(false)
        .accessibilityLabel("You")
    }
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
