import SwiftUI

/// Blue sport pin with a "starts in" label (Figma "Sports event pin").
struct EventPin: View {
    var event: SportsEvent
    var now: Date
    var isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(EventFormat.countdown(to: event.start, from: now))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)

            VStack(spacing: -6) {
                ZStack {
                    Circle().fill(Theme.pin).frame(width: 46, height: 46)
                    Text(event.sport.emoji).font(.system(size: 30))
                }
                Triangle().fill(Theme.pin).frame(width: 18, height: 14)
            }
            .shadow(color: Theme.shadow, radius: 3, y: 3)
        }
        .scaleEffect(isSelected ? 1.15 : 1, anchor: .bottom)
        .animation(.snappy, value: isSelected)
        .contentShape(.rect)
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
