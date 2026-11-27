import SwiftUI

/// Figma "Reimagined · W · Welcome" (513:7021, and the carousel's 526:6389…7080): "Room for one
/// more." under a court that cycles through the sports every 4.2 s, as on the website's hero, with
/// the active dot filling as its timer. The court is a picture: nothing on it takes a tap, so the
/// only things to do here are the buttons under it.
struct WelcomeScreen: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(GameStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    var viewModel: OnboardingViewModel

    @State private var sportIndex = 0
    /// The active dot's timer, 0…1.
    @State private var fill: CGFloat = 0
    /// The sheet scrolled up over the court (accessibility sizes): the court's labels step aside.
    @State private var sheetCoversCourt = false
    /// The open spot's halo and tag together, so its circle lands on the court's "+1".
    @State private var spotTagHeight: CGFloat = 0
    /// Where the sheet and the shown part of the screen end, for `MoreBelowHint`.
    @State private var contentBottom: CGFloat = 0
    @State private var scrollBottom: CGFloat = .infinity
    @State private var footerTop: CGFloat = .infinity
    @State private var scroll = ScrollPosition(edge: .top)

    /// How long each sport stays up, as on the website.
    static let interval: Duration = .milliseconds(4200)
    /// The catalog's activities: esports too from 1.0.
    private var sports: [Activity] { PracticeRound.welcomeSports(from: store.activities) }

    private var sport: Activity { sports[sportIndex % sports.count] }
    private var court: (people: [PersonSummary], capacity: Int) { PracticeRound.welcomeCourt(for: sport) }

    private var lineup: Lineup {
        Lineup(people: court.people, open: court.capacity - court.people.count)
    }

    /// The cycle runs only while nothing on screen is being read out, motion is welcome and the
    /// court can be seen. Nothing here can stop it, so it doesn't start for VoiceOver or Reduce
    /// Motion (WCAG 2.2.2).
    private var isCycling: Bool {
        !reduceMotion && !voiceOver && scenePhase == .active && !sheetCoversCourt
    }

    private var hasMore: Bool {
        MoreBelowHint.isNeeded(
            contentBottom: contentBottom,
            shownBottom: typeSize.isAccessibilitySize ? scrollBottom : min(scrollBottom, footerTop)
        )
    }

    var body: some View {
        CourtScaffold(activity: sport, lineup: lineup, capacity: court.capacity) {
            VStack(alignment: .leading, spacing: 0) {
                sheet
                // After the text at accessibility sizes, as on `OnboardingPage` (A11Y-06).
                if typeSize.isAccessibilitySize { footer.padding(.top, 24) }
            }
            .reportsBottom($contentBottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollPosition($scroll)
        .reportsBottom($scrollBottom)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 12 } action: { _, covers in
            sheetCoversCourt = covers
        }
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                // The same court size as `CourtScaffold` works out, so these land on its spots.
                let size = CGSize(width: proxy.size.width, height: proxy.size.height + proxy.safeAreaInsets.bottom)
                courtLabels(scale: CourtHeader.scale(for: size), sheetTop: CourtHeader.sheetTop(for: size), width: proxy.size.width)
            }
            .ignoresSafeArea(edges: .top)
            .opacity(sheetCoversCourt ? 0 : 1)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.2), value: sheetCoversCourt)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !typeSize.isAccessibilitySize {
                footer
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .readableColumn()
                    .background(Theme.background)
                    .reportsTop($footerTop)
                    .moreBelowHint(isShown: hasMore) { scrollToEnd() }
            }
        }
        .overlay(alignment: .bottom) {
            if typeSize.isAccessibilitySize, hasMore { MoreBelowHint { scrollToEnd() } }
        }
        .animation(.easeOut(duration: 0.2), value: hasMore)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: CycleKey(index: sportIndex, isCycling: isCycling)) { await runTimer() }
        .task { await store.loadCatalogIfNeeded() }
    }

    private func scrollToEnd() {
        withAnimation(.snappy) { scroll.scrollTo(edge: .bottom) }
    }

    // MARK: Sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Room for one more.")
                .font(.rounded(.largeTitle, .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(viewModel.welcomeMessage)
                .font(.rounded(.callout, .bold))
                .foregroundStyle(Theme.mutedLarge)
            HowItWorks()
                .padding(.top, 14)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button("Show me how it works") { viewModel.showHowItWorks() }
                .pill(.primary)
            Button("I already have an account") { viewModel.haveAnAccount() }
                .pill(.secondary)
            Link(destination: appViewModel.config.privacyURL) {
                Text("Privacy & Terms")
                    .buttonShapeUnderline()
                    // 44 pt tall to tap (A11Y-19).
                    .tapTarget(.vertical, 14)
            }
            .font(.rounded(.footnote))
            .foregroundStyle(Theme.mutedLarge)
        }
    }

    // MARK: Court

    /// The bubble, the open spot's tag and the sport dots, placed in the court's 402 pt design
    /// space like `CourtHeader`'s people. All of it is picture: no taps, hidden from VoiceOver.
    private func courtLabels(scale: CGFloat, sheetTop: CGFloat, width: CGFloat) -> some View {
        let inset = (width - CourtArt.designWidth * scale) / 2
        let slots = CourtLayout.slots(for: sport.court, count: court.capacity)
        // The first open spot: the people stand in the spots before it.
        let spot = slots.points[min(court.people.count, slots.points.count - 1)]
        let token = slots.tokenSize * scale
        // Under the "+1", unless that would run into the sport dots (tennis and padel's low spot).
        let tagIsAbove = spot.y * scale + token / 2 + 40 > sheetTop - 52
        let shift = max(spotTagHeight - token, 0) / 2

        return ZStack(alignment: .topLeading) {
            callout
                .position(x: inset + CourtArt.designWidth / 2 * scale, y: 118 * scale)

            SpotTag(tokenSize: token, tagIsAbove: tagIsAbove)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { spotTagHeight = $0 }
                .position(x: inset + spot.x * scale, y: spot.y * scale + (tagIsAbove ? -shift : shift))
                .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.25), value: sportIndex)

            SportDots(sports: sports, selection: sportIndex % sports.count, fill: fill)
                .position(x: width / 2, y: sheetTop - 30)
        }
        .frame(width: width, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// "Need 1 more for 3v3".
    private var callout: some View {
        Text(verbatim: PracticeRound.welcomeCall(for: sport))
            .font(.rounded(.subheadline, .bold))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white, in: .rect(cornerRadius: 16))
            .shadow(color: Theme.shadowInk.opacity(0.14), radius: 8, y: 3)
            .inkOnColor()
            .id(sport.slug)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
    }

    /// Fills the active dot, then moves on to the next sport. Stopped, the dot shows full.
    private func runTimer() async {
        guard isCycling else {
            fill = 1
            return
        }
        fill = 0
        withAnimation(.linear(duration: 4.2)) { fill = 1 }
        do { try await Task.sleep(for: Self.interval) } catch { return }
        withAnimation(.easeInOut(duration: 0.6)) { sportIndex = (sportIndex + 1) % sports.count }
    }

    private struct CycleKey: Hashable {
        var index: Int
        var isCycling: Bool
    }
}

/// The open spot on Welcome's court: a soft halo around the dashed "+1" (drawn by the court) and a
/// green "Be the +1" tag.
private struct SpotTag: View {
    var tokenSize: CGFloat
    /// The tag goes over the "+1" instead of under it.
    var tagIsAbove = false

    var body: some View {
        VStack(spacing: 6) {
            if tagIsAbove { tag }
            Circle()
                .fill(.white.opacity(0.22))
                .overlay { Circle().strokeBorder(.white.opacity(0.75), lineWidth: 3) }
                .frame(width: tokenSize * 1.38, height: tokenSize * 1.38)
                .frame(width: tokenSize, height: tokenSize)
            if !tagIsAbove { tag }
        }
        .inkOnColor()
    }

    private var tag: some View {
        Text("Be the +1")
            .font(.rounded(.footnote, .bold))
            .foregroundStyle(Theme.onAccent)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background(Theme.accent, in: .capsule)
            .overlay { Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1) }
            .shadow(color: Theme.shadowInk.opacity(0.18), radius: 6, y: 2)
    }
}

/// Which sport is up: a dot per sport on a Liquid Glass pill; the active one widens to show its
/// emoji and fills left to right as its timer.
private struct SportDots: View {
    var sports: [Activity]
    var selection: Int
    var fill: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            ForEach(sports.indices, id: \.self) { dot($0) }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        // Liquid Glass over the court (a light material on iOS 18).
        .appGlass(in: .capsule)
        .inkOnColor()
        .animation(.spring(duration: 0.5, bounce: 0.2), value: selection)
    }

    @ViewBuilder
    private func dot(_ index: Int) -> some View {
        let isActive = index == selection
        let sport = sports[index]
        ZStack {
            Capsule().fill(isActive ? Color.white.opacity(0.55) : Theme.ink.opacity(0.4))
            if isActive {
                Capsule()
                    .fill(sport.color.mix(with: .white, by: 0.3))
                    .scaleEffect(x: fill, anchor: .leading)
                Text(sport.emoji)
                    .font(.system(size: 17))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .clipShape(.capsule)
        .frame(width: isActive ? 60 : 8, height: isActive ? 32 : 8)
    }
}

/// "1. Spot a plan · 2. Take a spot · 3. Show up": side by side, or a list at accessibility sizes.
private struct HowItWorks: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        layout {
            step(Text("1. Spot a plan")) {
                Circle().fill(Color(.sportBasketball))
                    .overlay { PlaceIcon(size: 24).foregroundStyle(.white) }
            }
            step(Text("2. Take a spot")) {
                Circle().fill(Theme.accentSoft)
                    .overlay { OpenSpotToken(size: 34, fill: .clear) }
            }
            step(Text("3. Show up")) {
                Circle().fill(Theme.accent)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func step(_ title: Text, @ViewBuilder icon: () -> some View) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(spacing: 12))
            : AnyLayout(VStackLayout(spacing: 8))
        return layout {
            icon()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            title
                .font(.rounded(.footnote, .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .center)
        }
        .frame(maxWidth: typeSize.isAccessibilitySize ? nil : .infinity, alignment: typeSize.isAccessibilitySize ? .leading : .center)
        .accessibilityElement(children: .combine)
    }
}
