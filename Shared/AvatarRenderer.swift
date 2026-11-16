import UIKit

/// Draws the initials avatar and the sport badge for a communication notification.
/// Both are circles, the same shapes `PersonToken` and the map pin already use.
nonisolated enum AvatarRenderer {
    /// An initials avatar in that person's palette color.
    /// - Parameters:
    ///   - id: The person's ID. Picks the color.
    ///   - initials: One or two letters, already uppercased.
    /// - Returns: PNG bytes for `INImage`.
    static func person(id: UUID, initials: String) -> Data {
        image { context, size in
            let rect = CGRect(origin: .zero, size: size)
            AvatarPalette.person(id).color.setFill()
            context.cgContext.fillEllipse(in: rect.insetBy(dx: 2, dy: 2))
            strokeRing(in: context, rect: rect)
            draw(initials, in: rect, size: size.width * 0.34, context: context)
        }
    }

    /// The sport pin as a circle: sport color, emoji in the middle.
    /// - Parameter slug: An `activities.slug`, such as `soccer`.
    /// - Returns: PNG bytes for the group image.
    static func sport(slug: String) -> Data {
        image { context, size in
            let rect = CGRect(origin: .zero, size: size)
            AvatarPalette.sport(slug).color.setFill()
            context.cgContext.fillEllipse(in: rect.insetBy(dx: 2, dy: 2))
            strokeRing(in: context, rect: rect)
            let emoji = AvatarPalette.emoji(for: slug)
            draw(emoji, in: rect, size: size.width * 0.46, context: context)
        }
    }

    private static func image(_ draw: (UIGraphicsImageRendererContext, CGSize) -> Void) -> Data {
        let size = CGSize(width: 120, height: 120)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            draw(context, size)
        }
    }

    private static func strokeRing(in context: UIGraphicsImageRendererContext, rect: CGRect) {
        UIColor.white.setStroke()
        let ring = UIBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
        ring.lineWidth = 4
        ring.stroke()
    }

    private static func draw(_ text: String, in rect: CGRect, size: CGFloat, context: UIGraphicsImageRendererContext) {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        let font = UIFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: AvatarPalette.ink.color,
            .paragraphStyle: style,
        ]
        let bounds = (text as NSString).boundingRect(
            with: rect.size, options: [.usesLineFragmentOrigin], attributes: attributes, context: nil
        )
        let origin = CGRect(
            x: rect.minX,
            y: rect.midY - bounds.height / 2,
            width: rect.width,
            height: bounds.height
        )
        (text as NSString).draw(in: origin, withAttributes: attributes)
    }
}
