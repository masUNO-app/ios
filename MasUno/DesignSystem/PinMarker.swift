import SwiftUI

/// One-piece map pin: a circle that tapers to a point, so it reads as a single shape
/// (no seam under shadows or when dimmed).
nonisolated struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + radius)
        let tip = CGPoint(x: rect.midX, y: rect.maxY)
        // Where the straight sides meet the circle tangentially.
        let distance = max(tip.y - center.y, radius + 0.01)
        let alpha = acos(radius / distance)

        var path = Path()
        path.move(to: tip)
        path.addRelativeArc(
            center: center, radius: radius,
            startAngle: .radians(.pi / 2 + alpha),
            delta: .radians(2 * .pi - 2 * alpha)
        )
        path.closeSubpath()
        return path
    }
}

/// Blue pin with content (a sport emoji or symbol) centered in its round head.
struct PinMarker<Content: View>: View {
    /// Diameter of the round head; the point adds about a quarter of that below.
    var size: CGFloat = 46
    @ViewBuilder var content: Content

    var body: some View {
        PinShape()
            .fill(Theme.pin)
            .frame(width: size, height: size * 1.22)
            .overlay(alignment: .top) {
                content.frame(width: size, height: size)
            }
            .shadow(color: Theme.shadow, radius: 3, y: 3)
    }
}
