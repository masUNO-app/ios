import SwiftUI

// Reduce Motion (A11Y-18): what grows, shrinks, bounces or glides only fades instead, or jumps.
// A size that means something (the selected pin) stays; only its animation goes.

extension Animation {
    /// `animation`, or a short ease-out (a plain fade's length) under Reduce Motion.
    static func motionAware(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.2) : animation
    }

    /// A map camera move: `.smooth`, or a quick ease without the long glide under Reduce Motion.
    /// Reads the setting itself, for view models.
    static var cameraMove: Animation {
        UIAccessibility.isReduceMotionEnabled ? .easeInOut(duration: 0.25) : .smooth
    }
}

extension View {
    /// Scales from `scale` and fades as it's inserted and removed; only fades under Reduce Motion.
    func motionAwareTransition(scale: CGFloat) -> some View {
        modifier(MotionAwareTransition(scale: scale))
    }

    /// Full size and opaque when shown, `scale` and clear when not; under Reduce Motion it keeps
    /// its size and only fades.
    func motionAwareScale(isShown: Bool, from scale: CGFloat, anchor: UnitPoint = .center) -> some View {
        modifier(MotionAwareScale(isShown: isShown, scale: scale, anchor: anchor))
    }

    /// `.animation(_:value:)`, with `Animation.motionAware` in place of `animation`.
    func motionAwareAnimation(_ animation: Animation, value: some Equatable) -> some View {
        modifier(MotionAwareAnimation(animation: animation, value: value))
    }
}

private struct MotionAwareTransition: ViewModifier {
    var scale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : .scale(scale: scale).combined(with: .opacity))
    }
}

private struct MotionAwareScale: ViewModifier {
    var isShown: Bool
    var scale: CGFloat
    var anchor: UnitPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isShown || reduceMotion ? 1 : scale, anchor: anchor)
            .opacity(isShown ? 1 : 0)
    }
}

private struct MotionAwareAnimation<Value: Equatable>: ViewModifier {
    var animation: Animation
    var value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(.motionAware(animation, reduceMotion: reduceMotion), value: value)
    }
}
