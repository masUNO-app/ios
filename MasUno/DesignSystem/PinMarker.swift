import SwiftUI

/// The 1.0 map pin: a teardrop, traced from the Figma marker (42 × 53).
nonisolated struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 42, sy = rect.height / 53
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }

        var path = Path()
        path.move(to: point(21, 53))
        path.addCurve(to: point(0, 21), control1: point(17, 47), control2: point(0, 37))
        path.addCurve(to: point(21, 0), control1: point(0, 9.4), control2: point(9.4, 0))
        path.addCurve(to: point(42, 21), control1: point(32.6, 0), control2: point(42, 9.4))
        path.addCurve(to: point(21, 53), control1: point(42, 37), control2: point(25, 47))
        path.closeSubpath()
        return path
    }
}

/// The place glyph on cards and details: the same teardrop as the map pins, in outline.
/// (SF Symbols' map pins all stand on a stick or a base.)
struct PlaceIcon: View {
    var size: CGFloat = 18

    var body: some View {
        let line = max(size * 0.09, 1.3)
        PinShape()
            .stroke(style: StrokeStyle(lineWidth: line, lineJoin: .round))
            .overlay(alignment: .top) {
                Circle()
                    .stroke(lineWidth: line)
                    .frame(width: size * 0.26, height: size * 0.26)
                    .padding(.top, size * 0.21)
            }
            .frame(width: size * 0.7, height: size * 0.88)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A teardrop pin in a sport's color with content (its emoji) centered in the round head.
struct PinMarker<Content: View>: View {
    var color: Color
    /// Width of the round head. The point makes it about a quarter taller.
    var size: CGFloat = 42
    @ViewBuilder var content: Content

    var body: some View {
        PinShape()
            .fill(color)
            .frame(width: size, height: size * 53 / 42)
            .overlay(alignment: .top) {
                content.frame(width: size, height: size)
            }
            .shadow(color: Theme.shadow, radius: 3, y: 2)
    }
}
