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
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)

            VStack(spacing: -6) {
                ZStack {
                    Circle().fill(Theme.pinBlue).frame(width: 46, height: 46)
                    Text(event.sport.emoji).font(.system(size: 30))
                }
                Triangle().fill(Theme.pinBlue).frame(width: 18, height: 14)
            }
            .shadow(color: .black.opacity(0.2), radius: 3, y: 3)
        }
        .scaleEffect(isSelected ? 1.15 : 1, anchor: .bottom)
        .animation(.snappy, value: isSelected)
        .contentShape(.rect)
    }
}

/// Red "You" pin (Figma "User location pin").
struct UserPin: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("You")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)

            VStack(spacing: -6) {
                ZStack {
                    Circle().fill(Theme.youRed).frame(width: 46, height: 46)
                    Circle().fill(Color(.systemGray5)).frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color(.systemGray))
                        }
                }
                Triangle().fill(Theme.youRed).frame(width: 18, height: 14)
            }
            .shadow(color: .black.opacity(0.2), radius: 3, y: 3)
        }
        .allowsHitTesting(false)
    }
}
