import SwiftUI

extension View {
    /// Liquid Glass where available, with a readable material surface on iOS 18.
    func appGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(AppGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }

    /// A prominent circular action, such as Send in chat. `solid` draws the tint as a plain fill, the
    /// glass button's size: tinted glass in dark mode comes out darker and bluer than the color.
    @ViewBuilder
    func appProminentCircle(tint: Color, solid: Bool = false) -> some View {
        if #available(iOS 26, *), !solid {
            buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(tint)
        } else if solid {
            buttonStyle(AdaptiveCircleButtonStyle(fill: tint, size: 48, showsEdge: false))
        } else {
            buttonStyle(AdaptiveCircleButtonStyle(fill: tint))
        }
    }

    @ViewBuilder
    func appScrollEdgeEffectHidden(_ hidden: Bool, for edges: Edge.Set) -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectHidden(hidden, for: edges)
        } else {
            self
        }
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder
    func appSharedBackgroundVisibility(_ visibility: Visibility) -> some ToolbarContent {
        if #available(iOS 26, *) {
            sharedBackgroundVisibility(visibility)
        } else {
            self
        }
    }
}

private struct AppGlassModifier<S: Shape>: ViewModifier {
    var shape: S
    var tint: Color?
    var interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if let tint, colorScheme == .dark {
            // Tinted glass and material come out darker in dark mode; a sport color is drawn as it
            // is, as on its pins and court, so the ink on it still reads.
            content
                .background(tint, in: shape)
                .contentShape(shape)
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .background {
                    if reduceTransparency {
                        shape.fill(Theme.card)
                            .overlay(shape.fill(tint?.opacity(0.45) ?? .clear))
                    } else {
                        shape.fill(.regularMaterial)
                            .overlay(shape.fill(tint?.opacity(0.45) ?? .clear))
                    }
                }
                .overlay(shape.stroke(Theme.hairline, lineWidth: 0.5).allowsHitTesting(false))
        }
    }
}

/// Used on iOS 18; newer systems use the native glass button styles.
struct AdaptiveCircleButtonStyle: ButtonStyle {
    var fill: Color? = nil
    var size: CGFloat = 44
    var showsEdge = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: size, minHeight: size)
            .background {
                if let fill {
                    Circle().fill(fill)
                } else {
                    Circle().fill(Theme.card)
                }
            }
            .overlay { if showsEdge { Circle().strokeBorder(Theme.hairline, lineWidth: 0.5) } }
            .contentShape(.circle)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
