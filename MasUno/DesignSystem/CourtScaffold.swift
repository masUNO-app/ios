import SwiftUI

/// A court fixed at the top of the screen with a rounded content sheet that scrolls up over it:
/// game details, Welcome and You're verified. The screen's own logic (taps, refresh, the bar's
/// title, the bottom action) goes on the outside: scroll modifiers reach the scroll view inside.
struct CourtScaffold<Sheet: View>: View {
    var activity: Activity
    var lineup: Lineup
    /// Total spots to draw: the game's capacity.
    var capacity: Int
    var holdsYou: Bool
    var showsOpenSpots: Bool
    /// Tapping the court. Without one the court is only a picture: no taps, read as an image of who's on it.
    var onTap: (() -> Void)?
    /// What the tap does, for VoiceOver.
    var tapHint: LocalizedStringKey
    /// Told when the top of the sheet, where its title sits, scrolls up under the navigation bar,
    /// and back down. Measured here, against the same court as the one on screen.
    var onSheetUnderBar: ((Bool) -> Void)?
    var sheet: Sheet
    @State private var courtIsVisible = true

    init(
        activity: Activity, lineup: Lineup, capacity: Int, holdsYou: Bool = false, showsOpenSpots: Bool = true,
        onTap: (() -> Void)? = nil, tapHint: LocalizedStringKey = "Shows who's going",
        onSheetUnderBar: ((Bool) -> Void)? = nil, @ViewBuilder sheet: () -> Sheet
    ) {
        self.activity = activity
        self.lineup = lineup
        self.capacity = capacity
        self.holdsYou = holdsYou
        self.showsOpenSpots = showsOpenSpots
        self.onTap = onTap
        self.tapHint = tapHint
        self.onSheetUnderBar = onSheetUnderBar
        self.sheet = sheet()
    }

    var body: some View {
        // Read in the same layout pass as the court is drawn, so the first frame already has the
        // real scale. Nothing seeded with a guess for a later update to correct.
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            // The court sizes to the content column (a side bar's inset left out) and the whole
            // screen height: the bottom bar's inset is added back and the keyboard is ignored, so
            // neither one resizes the court.
            let courtSize = CGSize(width: proxy.size.width, height: proxy.size.height + insets.bottom)
            let scale = CourtHeader.scale(for: courtSize)
            let sheetTop = CourtHeader.sheetTop(for: courtSize)

            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: sheetTop)
                        .contentShape(.rect)
                        .onTapGesture { onTap?() }
                        .accessibilityHidden(true)

                    sheet
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                        .readableColumn()
                        // The scroll view runs under a side bar (iPhone Duo); the content stays
                        // clear of it, centered under the court.
                        .padding(.leading, insets.leading)
                        .padding(.trailing, insets.trailing)
                        // Always reaches the bottom, so the court only ever shows above it.
                        .frame(minHeight: proxy.size.height - sheetTop, alignment: .top)
                        .background {
                            // Carries on under the sheet when it bounces past the bottom.
                            UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.sheet, topTrailingRadius: Theme.Radius.sheet)
                                .fill(Theme.background)
                                .padding(.bottom, -proxy.size.height)
                        }
                }
            }
            // Edge to edge, so the sheet's background fills the width under a side bar too.
            .ignoresSafeArea(edges: [.top, .horizontal])
            // The indicator would run down the court.
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // Past this, the sheet's title is under the bar.
                geometry.contentOffset.y > sheetTop - 70
            } action: { _, isUnder in
                onSheetUnderBar?(isUnder)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y < sheetTop
            } action: { _, visible in
                courtIsVisible = visible
            }
            .background(alignment: .top) {
                // Over the content column, not under a side bar.
                CourtHeader(
                    activity: activity, lineup: lineup, capacity: capacity, scale: scale,
                    holdsYou: holdsYou, showsOpenSpots: showsOpenSpots, tapHint: tapHint, onTap: onTap ?? {},
                    isPicture: onTap == nil
                )
                .environment(\.courtDecorationVisible, courtIsVisible)
                .allowsHitTesting(onTap != nil)
                .frame(maxHeight: .infinity, alignment: .top)
                // Sport color behind the court for the pull-down bounce. A color background
                // also fills the safe areas: the side bar's, the bottom bar's.
                .background(activity.color)
            }
        }
        .ignoresSafeArea(edges: .top)
        .ignoresSafeArea(.keyboard)
    }
}

extension CourtHeader {
    /// The court stops growing here, so the header doesn't swallow a big screen.
    static let maxWidth: CGFloat = 480

    /// On a short screen (folded, or landscape on iPhone Duo) the court gives up height so the
    /// sheet still shows more than its title: it leaves the sheet `sheetRoom`, but never shrinks
    /// below `minHeightShare` of the screen. A phone in portrait hits the width limit first, so
    /// it keeps its court.
    static let sheetRoom: CGFloat = 420
    static let minHeightShare: CGFloat = 0.45

    /// Full width up to `maxWidth`, and short enough to leave the sheet room. Pass the whole
    /// screen height: the keyboard, a bottom bar or a push changes the visible height, and none
    /// of them should resize the court.
    static func scale(for size: CGSize) -> CGFloat {
        let maxHeight = max(size.height * minHeightShare, size.height - sheetRoom)
        return min(size.width, maxWidth, maxHeight * CourtArt.designWidth / designHeight) / CourtArt.designWidth
    }

    /// Where a `CourtScaffold` sheet starts: its rounded top rides up over the court.
    static func sheetTop(for size: CGSize) -> CGFloat {
        designHeight * scale(for: size) - Theme.Radius.sheet
    }
}
