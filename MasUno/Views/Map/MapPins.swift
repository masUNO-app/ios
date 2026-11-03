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

            PinMarker(size: 46) {
                Text(event.sport.emoji).font(.system(size: 30))
            }
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

/// "You" marker: your initials in a green halo with a green dot (Figma "User location pin").
struct UserPin: View {
    var name: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Avatar(name: name, size: 40)
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
