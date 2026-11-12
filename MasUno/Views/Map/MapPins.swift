import SwiftUI

/// Figma "Sports event pin": a teardrop in the sport's color with its emoji, the people going
/// underneath, and a tag above ("Spot open" for two hours after an auto-repost, SPEC §7.6.11;
/// otherwise "Soon" within the hour). Selected, it grows over a halo and drops the tag and
/// people, which the popup shows instead; other pins dim while a popup is open.
struct EventPin: View {
    var event: Game
    /// Up to three people going, host first.
    var people: [PersonSummary]
    var now: Date
    var isSelected: Bool
    var isDimmed: Bool

    private static let tagHeight: CGFloat = 26
    private static let markerSize = CGSize(width: 48, height: 60)
    /// From the marker's top to the pin's point.
    private static let tipY: CGFloat = 54
    private static let peopleSize: CGFloat = 24
    private static let spacing: CGFloat = 4
    private static let selectedScale: CGFloat = 1.24
    /// How far the selected pin's head rises above its point.
    static let selectedHeight: CGFloat = 53 * selectedScale

    var body: some View {
        VStack(spacing: Self.spacing) {
            if let tag {
                Text(tag)
                    .font(.rounded(size: 13))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10)
                    .frame(height: Self.tagHeight)
                    .glassEffect(.regular, in: .capsule)
                    .opacity(isSelected ? 0 : 1)
            }

            PinMarker(color: event.activity.color) {
                Text(event.activity.emoji).font(.system(size: 24))
            }
            .frame(width: Self.markerSize.width, height: Self.markerSize.height, alignment: .top)
            .padding(.top, 1)
            .background(alignment: .top) {
                // Halo on the ground under the selected pin.
                Ellipse()
                    .fill(event.activity.color.opacity(0.22))
                    .overlay(Ellipse().strokeBorder(event.activity.color.opacity(0.55), lineWidth: 1.5))
                    .frame(width: 56, height: 20)
                    .offset(y: Self.tipY - 10)
                    .opacity(isSelected ? 1 : 0)
            }
            .scaleEffect(isSelected ? Self.selectedScale : 1, anchor: UnitPoint(x: 0.5, y: Self.tipY / Self.markerSize.height))

            TokenStack(people: people, maxVisible: 3, size: Self.peopleSize)
                .frame(height: Self.peopleSize)
                .opacity(isSelected ? 0 : 1)
        }
        .opacity(isDimmed ? 0.45 : 1)
        .animation(.snappy, value: isSelected)
        .animation(.snappy, value: isDimmed)
        .contentShape(.rect)
        .accessibilityElement()
        .accessibilityLabel(Text("\(event.activity.name): \(event.title)"))
    }

    private var tag: LocalizedStringKey? {
        Self.tag(for: event, now: now)
    }

    private static func tag(for event: Game, now: Date) -> LocalizedStringKey? {
        if event.isBumped(now: now) { return "Spot open" }
        return event.isSoon(now: now) ? "Soon" : nil
    }

    /// Where the pin's point is within the annotation, so MapKit puts it on the coordinate
    /// rather than the bottom of the people row.
    static func anchor(for event: Game, now: Date) -> UnitPoint {
        let above = tag(for: event, now: now) == nil ? 0 : tagHeight + spacing
        let total = above + markerSize.height + 1 + spacing + peopleSize
        return UnitPoint(x: 0.5, y: (above + 1 + tipY) / total)
    }
}

/// "You" marker: your token in a soft halo with a green dot (Figma "User location pin").
struct UserPin: View {
    var name: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MeToken(name: name, size: 42, ring: 3)
                .padding(14)
                .background(Theme.you.opacity(0.28), in: .circle)
            Circle()
                .fill(Theme.accent)
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .offset(x: -11, y: -11)
        }
        .shadow(color: Theme.shadow.opacity(0.5), radius: 3, y: 2)
        .allowsHitTesting(false)
        .accessibilityLabel("You")
    }
}
