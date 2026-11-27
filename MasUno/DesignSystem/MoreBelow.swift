import SwiftUI

/// Shown while a screen's content runs on under its pinned buttons: a fade over the cut-off edge
/// and a chevron that scrolls to the end. The chevron nudges twice as it appears, then rests: a
/// repeating animation would keep the hint from ever being removed. VoiceOver scrolls by itself,
/// so it's hidden there.
struct MoreBelowHint: View {
    static let height: CGFloat = 56

    /// The content ends more than a few points past what's shown.
    static func isNeeded(contentBottom: CGFloat, shownBottom: CGFloat) -> Bool {
        contentBottom - shownBottom > 12
    }

    /// What the content fades into: the surface behind it.
    var fade = Theme.background
    var scrollToEnd: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nudges = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [fade.opacity(0), fade], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.height)
                .allowsHitTesting(false)
            Button(action: scrollToEnd) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34)
                    .appGlass(in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: nudges) { view, drop in
                view.offset(y: drop)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(5, duration: 0.25)
                    CubicKeyframe(0, duration: 0.3)
                    CubicKeyframe(5, duration: 0.25)
                    CubicKeyframe(0, duration: 0.3)
                }
            }
            .task {
                // After the fade, so the first look lands on it settling, not appearing.
                try? await Task.sleep(for: .milliseconds(400))
                if !reduceMotion { nudges += 1 }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height, alignment: .bottom)
        .accessibilityHidden(true)
        .transition(.opacity)
    }
}

extension View {
    /// Where this view ends on screen: put it on the content inside a scroll view, so the screen can
    /// tell whether that content runs on past what's shown (`MoreBelowHint.isNeeded`). Measured on
    /// screen rather than from the scroll view's insets, which a navigation bar or a scroll view
    /// that stops at its pinned buttons report differently.
    func reportsBottom(_ bottom: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { bottom.wrappedValue = $0 }
    }

    /// Where this view starts on screen: put it on pinned buttons.
    func reportsTop(_ top: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top.wrappedValue = $0 }
    }

    /// Hangs `MoreBelowHint` off the top edge of pinned buttons, over the content they cover.
    func moreBelowHint(isShown: Bool, fade: Color = Theme.background, scrollToEnd: @escaping () -> Void) -> some View {
        overlay(alignment: .top) {
            if isShown {
                MoreBelowHint(fade: fade, scrollToEnd: scrollToEnd)
                    .offset(y: -MoreBelowHint.height)
            }
        }
    }
}
