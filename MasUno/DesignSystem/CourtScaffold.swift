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
    /// Tapping the court. Without one the court is only a picture: no taps, hidden from VoiceOver.
    var onTap: (() -> Void)?
    var sheet: Sheet

    init(
        activity: Activity, lineup: Lineup, capacity: Int, holdsYou: Bool = false, showsOpenSpots: Bool = true,
        onTap: (() -> Void)? = nil, @ViewBuilder sheet: () -> Sheet
    ) {
        self.activity = activity
        self.lineup = lineup
        self.capacity = capacity
        self.holdsYou = holdsYou
        self.showsOpenSpots = showsOpenSpots
        self.onTap = onTap
        self.sheet = sheet()
    }

    var body: some View {
        // Read in the same layout pass as the court is drawn, so the first frame already has the
        // real scale. Nothing seeded with a guess for a later update to correct.
        GeometryReader { proxy in
            let scale = CourtHeader.scale(forWidth: proxy.size.width)
            let sheetTop = CourtHeader.sheetTop(forWidth: proxy.size.width)

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
            .ignoresSafeArea(edges: .top)
            // The indicator would run down the court.
            .scrollIndicators(.hidden)
            .background(alignment: .top) {
                CourtHeader(
                    activity: activity, lineup: lineup, capacity: capacity, scale: scale,
                    holdsYou: holdsYou, showsOpenSpots: showsOpenSpots, onTap: onTap ?? {}
                )
                .allowsHitTesting(onTap != nil)
                .accessibilityHidden(onTap == nil)
                .frame(maxHeight: .infinity, alignment: .top)
                // Sport color behind the court for the pull-down bounce.
                .background(activity.color)
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

extension CourtHeader {
    /// The court stops growing here, so the header doesn't swallow a big screen.
    static let maxWidth: CGFloat = 480

    /// Full width up to `maxWidth`. Width only: the keyboard, a bottom bar or a push changes the
    /// height, and none of them should resize the court.
    static func scale(forWidth width: CGFloat) -> CGFloat {
        min(width, maxWidth) / CourtArt.designWidth
    }

    /// Where a `CourtScaffold` sheet starts: its rounded top rides up over the court.
    static func sheetTop(forWidth width: CGFloat) -> CGFloat {
        designHeight * scale(forWidth: width) - Theme.Radius.sheet
    }
}
