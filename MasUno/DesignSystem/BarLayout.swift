import SwiftUI

/// How the system draws the bars: horizontal (phones, the open iPhone Duo in portrait) or as one
/// vertical bar on a side (the Duo's cover display, and the open display in landscape).
///
/// Read once, at the root, by `readsBarLayout()` and handed down through the environment.
/// Screens read `barLayout`, never `toolbarVerticalEdge` themselves: a reader deeper in the view
/// tree can miss the update after a fold and leave its screen laid out for the wrong bar.
enum BarLayout: Equatable {
    case horizontal
    case vertical(HorizontalEdge)

    var isVertical: Bool {
        if case .vertical = self { true } else { false }
    }
}

extension EnvironmentValues {
    @Entry var barLayout: BarLayout = .horizontal
}

extension View {
    /// Publishes `barLayout` to everything inside, and brings the vertical bar back when iOS drops
    /// it after a fold. Apply once, around the root `NavigationStack`.
    func readsBarLayout() -> some View {
        modifier(BarLayoutReader())
    }
}

/// `toolbarVerticalEdge` and `toolbarVerticalBehavior` are in the iOS 27.1 SDK (Xcode 27).
/// GitHub's runners still have Xcode 26, so CI builds without them and `barLayout` stays
/// `.horizontal` there.
private struct BarLayoutReader: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            content.modifier(BarLayoutReader27())
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if compiler(>=6.4) // `toolbarVerticalEdge` needs Xcode 27; see BarLayoutReader.
@available(iOS 27.1, *)
private struct BarLayoutReader27: ViewModifier {
    /// A fold flips the edge a few times in a row (nil, then back); screens only hear about a
    /// value that has held this long.
    private static let settleTime: Duration = .milliseconds(250)
    /// How long a display change takes to finish resizing the window.
    private static let resizeTime: Duration = .milliseconds(600)
    /// Windows shorter than this get the vertical bar: the cover display (678 pt) and the open
    /// display in landscape (669). Open portrait (951) and phones never do.
    private static let verticalBarMaxHeight: CGFloat = 700

    @Environment(\.toolbarVerticalEdge) private var edge
    /// What screens see.
    @State private var layout: BarLayout = .horizontal
    /// The system's latest edge, kept in state so a running task reads the live value; an
    /// environment value read in a task is the one from when the task started.
    @State private var latestEdge: HorizontalEdge?
    /// The whole window: the content plus every inset. A bar coming or going moves space
    /// between the two, so it doesn't change this; a display change does.
    @State private var window: CGSize = .zero
    @State private var windowChanges = 0
    /// Until then, a new edge is published at once: it's the launch, with nothing on screen to
    /// jump.
    @State private var settlesFrom: Date = .distantFuture
    @State private var isNudging = false
    @State private var lastNudge: Date = .distantPast

    func body(content: Content) -> some View {
        content
            .environment(\.barLayout, layout)
            .toolbarVerticalBehavior(isNudging ? .disabled : .automatic)
            .onGeometryChange(for: CGSize.self) { proxy in
                let insets = proxy.safeAreaInsets
                return CGSize(
                    width: (proxy.size.width + insets.leading + insets.trailing).rounded(),
                    height: (proxy.size.height + insets.top + insets.bottom).rounded()
                )
            } action: { old, new in
                window = new
                if old != .zero, abs(old.width - new.width) > 4 || abs(old.height - new.height) > 4 {
                    windowChanges += 1
                }
            }
            .onAppear { settlesFrom = .now.addingTimeInterval(1) }
            .onChange(of: edge, initial: true) { _, new in latestEdge = new }
            .task(id: latestEdge) { await publish() }
            .task(id: windowChanges) { await recoverIfDropped() }
    }

    private func publish() async {
        let target: BarLayout = latestEdge.map { .vertical($0) } ?? .horizontal
        guard target != layout else { return }
        if Date.now < settlesFrom {
            layout = target
            log("launch: \(target)")
            return
        }
        try? await Task.sleep(for: Self.settleTime)
        // A newer edge restarts this task; a nudge's own flicker isn't news.
        guard !Task.isCancelled, !isNudging else { return }
        withAnimation(.snappy) { layout = target }
        log("now \(target)")
    }

    /// iOS sometimes settles a fold in horizontal bars where a launch in the same pose gets the
    /// vertical bar. Turning the vertical behavior off and on makes it decide again. Once per
    /// display change, and never more than every few seconds, so it can't loop.
    private func recoverIfDropped() async {
        guard windowChanges > 0 else { return }
        try? await Task.sleep(for: Self.resizeTime)
        guard !Task.isCancelled,
              latestEdge == nil,
              window.height < Self.verticalBarMaxHeight,
              Date.now.timeIntervalSince(lastNudge) > 3
        else { return }
        lastNudge = .now
        log("nudge: window \(window), no vertical bar")
        isNudging = true
        try? await Task.sleep(for: .milliseconds(250))
        isNudging = false
    }

    private func log(_ message: String) {
        #if DEBUG
        print("BarLayout", message)
        #endif
    }
}
#endif
