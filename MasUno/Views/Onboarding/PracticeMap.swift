import MapKit
import SwiftUI

/// The practice round's map (Figma "Reimagined" J1, J2, H1, H2, H3: 513:5912, 6058, 6260, 6404,
/// 6822). It looks like the real map with pretend plans on it, dimmed, with a spotlight on the one
/// thing to tap next and a coach card that says why. Nothing here touches the server.
///
/// Join: every pin is a plan → tap it → its card → Count me in (then `PracticeJoinedStep`).
/// Host: Make a plan → the form, filled in → Create plan → your plan on the map.
struct PracticeMapStep: View {
    @Bindable var viewModel: OnboardingViewModel
    var mode: PracticeMode

    @State private var stage: Stage
    /// The form's fields, from the suggestion for the practice sport.
    @State private var plan: PracticePlan
    /// Spotlit things that aren't pins, measured in `space`.
    @State private var frames: [Target: CGRect] = [:]
    @State private var now = Date.now
    /// A partially open iPhone Duo's fold; nil on a flat screen.
    @State private var fold: CGRect?
    /// The popup's height, so its pin stands low enough for it (a default text size's, until measured).
    @State private var popupHeight: CGFloat = 330
    /// The coach card's height, to keep it on screen.
    @State private var coachHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.barLayout) private var barLayout
    @AccessibilityFocusState private var isCoachFocused: Bool

    enum Stage: Hashable {
        /// J1: find the pin.
        case findPin
        /// J2: its card.
        case popup
        /// H1: Make a plan, at the bottom of the map.
        case addButton
        /// H2: the form, with the people count spotlit.
        case form
        /// H3: your plan on the map.
        case ready
    }

    private enum Target: Hashable {
        case card, addButton, people, create
    }

    nonisolated static let space = "practice"

    init(viewModel: OnboardingViewModel, mode: PracticeMode) {
        self.viewModel = viewModel
        self.mode = mode
        var stage: Stage = mode == .join ? .findPin : .addButton
        #if DEBUG
        if let debug = viewModel.debugPracticeStage { stage = debug }
        #endif
        _stage = State(initialValue: stage)
        _plan = State(initialValue: viewModel.currentPracticePlan)
    }

    private var sport: Activity { viewModel.practiceSport }
    private var joinPlan: Game { PracticeRound.joinPlan(for: sport, campus: viewModel.mapCampus, now: now) }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let full = CGRect(origin: .zero, size: size)
            // What's tapped and read stays on one side of a partially open Duo's fold, as the
            // map's popup and system sheets do; on a flat screen that's the whole screen.
            let pane = fold.map { full.pane(avoiding: $0) } ?? full
            // The popup and its pin keep clear of the vertical bar, as on the map, where the
            // system's bar takes that room from the safe area.
            let popupPane = pane.avoidingSideBar(barLayout)
            ZStack {
                PracticeMapBackdrop(campus: viewModel.mapCampus)
                pins(in: size, pane: pane)
                MapChrome(
                    addButtonIsLive: stage == .addButton,
                    // A sheet covers the bottom bar; its edge would peek out under it on wide screens.
                    showsBottomBar: stage != .form && stage != .ready,
                    onAdd: { advance(to: .form) },
                    onAddFrame: { frames[.addButton] = $0 }
                )
                if stage == .popup { popupCard(pane: popupPane) }
                if stage == .form { formSheet.inPane(pane) }

                SpotlightScrim(hole: spotlight(in: pane), cornerRadius: spotlightRadius, alsoLit: alsoLit)

                if let coach = coach { coachCard(coach, size: size, pane: pane) }
                if stage == .ready { readySheet(in: size, pane: pane).inPane(pane) }

                practiceBar
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 6)
            }
            .coordinateSpace(.named(Self.space))
            .onGeometryChange(for: CGRect?.self) { $0.activeFold } action: { fold = $0 }
        }
        .environment(\.currentUserID, PracticeRound.you.id)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.loadMapCampus() }
        .onChange(of: stage) { isCoachFocused = true }
    }

    private func advance(to next: Stage) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.15)) { stage = next }
    }

    // MARK: Pins

    /// Where each pin's point is, as a share of the screen: the Figma's map, roughly.
    private static let otherSpots: [UnitPoint] = [
        UnitPoint(x: 0.24, y: 0.3), UnitPoint(x: 0.72, y: 0.4), UnitPoint(x: 0.76, y: 0.66), UnitPoint(x: 0.2, y: 0.8),
    ]
    /// Centered across, like a pin the real map has panned to so its popup opens above it.
    private static let joinSpot = UnitPoint(x: 0.5, y: 0.47)
    private static let mySpot = UnitPoint(x: 0.52, y: 0.29)
    private static let youSpot = UnitPoint(x: 0.86, y: 0.32)

    private func point(_ spot: UnitPoint, in size: CGSize) -> CGPoint {
        point(spot, in: CGRect(origin: .zero, size: size))
    }

    private func point(_ spot: UnitPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + spot.x * rect.width, y: rect.minY + spot.y * rect.height)
    }

    /// Where the pin to join stands: low enough that its popup fits above it, under the practice
    /// bar, as the real map pans a selected pin down to make room.
    private func joinTip(in pane: CGRect) -> CGPoint {
        let spot = point(Self.joinSpot, in: pane)
        let room = Self.barRoom + popupHeight + PlanPopupCard<EmptyView, EmptyView>.lift
        var x = spot.x
        // Wide enough for the popup and its coach side by side (the open iPhone Duo in
        // landscape): the pin moves left so the coach fits on its right.
        let card = PlanPopupCard<EmptyView, EmptyView>.width(in: pane.width)
        if stage == .popup, pane.width >= card + Self.coachWidth + 64 {
            x = pane.minX + 20 + card / 2
        }
        return CGPoint(x: x, y: min(max(spot.y, pane.minY + room), pane.maxY - 60))
    }

    /// The coach card's widest.
    private static let coachWidth: CGFloat = 328

    /// The practice bar and a little air, which the popup stays below.
    private static let barRoom: CGFloat = 62

    /// The other pins spread over the whole map; the ones to tap sit in `pane`.
    private func pins(in size: CGSize, pane: CGRect) -> some View {
        let others = PracticeRound.otherPins(besides: sport, now: now)
        let hosted = PracticeRound.hostedPlan(plan, campus: viewModel.mapCampus, now: now)

        return ZStack {
            ForEach(Array(others.enumerated()), id: \.element.id) { index, pin in
                PlacedPin(plan: pin.plan, people: pin.people, now: now, tip: point(Self.otherSpots[index % Self.otherSpots.count], in: size))
            }
            UserPin(name: "")
                .position(point(Self.youSpot, in: size))
            if mode == .join {
                // The pin to tap, while it's spotlit: the whole circle of light takes the tap.
                PlacedPin(
                    plan: joinPlan, people: PracticeRound.joinPeople, now: now,
                    tip: joinTip(in: stage == .popup ? pane.avoidingSideBar(barLayout) : pane), isSelected: stage == .popup,
                    action: stage == .findPin ? { advance(to: .popup) } : nil
                )
            } else if stage == .ready {
                PlacedPin(plan: hosted, people: [PracticeRound.you], now: now, tip: point(Self.mySpot, in: pane))
                    .transition(.scale(scale: 0.4, anchor: .bottom).combined(with: .opacity))
            }
        }
    }

    /// The circle of light around a pin, its "Soon" tag and the faces under it.
    private func pinHole(at tip: CGPoint) -> CGRect {
        CGRect(x: tip.x - 66, y: tip.y - 88, width: 132, height: 132)
    }

    private func spotlight(in pane: CGRect) -> CGRect? {
        switch stage {
        case .findPin:
            return pinHole(at: joinTip(in: pane))
        case .popup:
            // The popup and the selected pin under it, as one.
            guard let card = frames[.card] else { return nil }
            let tip = joinTip(in: pane.avoidingSideBar(barLayout))
            return card.union(CGRect(x: tip.x - 32, y: tip.y - 72, width: 64, height: 78)).insetBy(dx: -6, dy: -6)
        case .addButton:
            return frames[.addButton]?.insetBy(dx: -6, dy: -6)
        case .form:
            return frames[.people]?.insetBy(dx: -4, dy: -4)
        case .ready:
            // The pin and the face under it.
            let tip = point(Self.mySpot, in: pane)
            return CGRect(x: tip.x - 40, y: tip.y - 74, width: 80, height: 112)
        }
    }

    /// Left undimmed beside the spotlight, without its ring: Create plan, the step after People,
    /// so it doesn't look switched off.
    private var alsoLit: CGRect? {
        stage == .form ? frames[.create] : nil
    }

    private var spotlightRadius: CGFloat {
        switch stage {
        case .findPin: 66
        case .popup: Theme.Radius.dialog + 4
        case .addButton: 32
        case .form: Theme.Radius.field + 4
        case .ready: 40
        }
    }

    // MARK: Popup (J2)

    /// The real map's popup (`PlanPopupCard`), opened above the pin with its tail on it.
    private func popupCard(pane: CGRect) -> some View {
        let plan = joinPlan
        let tip = joinTip(in: pane)
        return PlanPopupCard(
            event: plan, lineup: Lineup(people: PracticeRound.joinPeople, open: plan.spotsLeft), now: now
        ) {
            BookmarkGlyph()
                .padding(-4)
                .accessibilityHidden(true)
        } actions: {
            // As on the map. Only Count me in moves the practice on, so Details is only a picture.
            Button("Details") {}
                .pill(.secondary, expands: false)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Button("Count me in") { viewModel.takePracticeSpot() }
                .pill(.primary)
                .accessibilityLabel(String.app("Count me in, \(plan.title)"))
        }
        .frame(width: PlanPopupCard<EmptyView, EmptyView>.width(in: pane.width))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frame in
            frames[.card] = frame
            if abs(frame.height - popupHeight) > 1 { popupHeight = frame.height }
        }
        .position(x: tip.x, y: tip.y - PlanPopupCard<EmptyView, EmptyView>.lift - popupHeight / 2)
        // Grows out of the pin, as on the map.
        .transition(.scale(scale: 0.1, anchor: .bottom).combined(with: .opacity))
    }

    // MARK: Make a plan (H2)

    private var formSheet: some View {
        PracticeFormSheet(
            plan: $plan, campus: viewModel.mapCampus, now: now,
            onPeopleFrame: { frames[.people] = $0 },
            onCreateFrame: { frames[.create] = $0 },
            onClose: { advance(to: .addButton) },
            onCreate: {
                viewModel.makePracticePlan(plan)
                advance(to: .ready)
            }
        )
        .transition(.move(edge: .bottom))
    }

    // MARK: Your plan is ready (H3)

    /// Kept under your new pin's spotlight; what doesn't fit scrolls, with a hint.
    private func readySheet(in size: CGSize, pane: CGRect) -> some View {
        let tip = point(Self.mySpot, in: pane)
        // Clear of the spotlight's outer ring (`spotlight(in:)`), with a little air.
        let maxHeight = size.height - (tip.y + 38 + 8 + 14)
        return ReadySheet(
            plan: PracticeRound.hostedPlan(plan, campus: viewModel.mapCampus, now: now), now: now,
            titleFocus: $isCoachFocused,
            onKeep: { viewModel.keepPracticePlan() },
            onTryJoining: { viewModel.tryOtherPractice(.join) }
        )
        .frame(maxHeight: maxHeight)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .transition(.move(edge: .bottom))
    }

    // MARK: Coach

    private struct Coach {
        var step: Int
        var title: String
        var message: String
        var instruction: String
    }

    private var coach: Coach? {
        switch stage {
        case .findPin:
            Coach(
                step: 1, title: String.app("Every pin is a plan"),
                message: String.app("The faces under a pin are people who are already going. Tap this \(sport.name) plan to see if there's room for you."),
                instruction: String.app("Tap the pin")
            )
        case .popup:
            Coach(
                step: 2, title: String.app("Room for \(joinPlan.spotsLeft) more means \(joinPlan.spotsLeft) open spots"),
                message: String.app("Each dashed +1 is a spot nobody's taken yet. Count me in takes one, and \(PracticeRound.alex.firstName) sees you joined right away."),
                instruction: String.app("Tap Count me in")
            )
        case .addButton:
            Coach(
                step: 1, title: String.app("Short on people? Post it."),
                message: String.app("Tap Make a plan. It takes under a minute, and people nearby who picked \(sport.name) get a heads-up."),
                instruction: String.app("Tap Make a plan")
            )
        case .form:
            Coach(
                step: 2, title: String.app("Count yourself in"),
                message: String.app("\(plan.capacity) people means you plus \(plan.capacity - 1) open spots. We filled in the rest from your activity and the time of day. Change anything you like."),
                instruction: String.app("Then tap Create plan")
            )
        case .ready:
            nil
        }
    }

    /// Above the spotlight when it's in the bottom half, under it otherwise, with the tail
    /// pointing at it. The popup fills the space above its pin, so its coach goes beside it when
    /// there's room (a wide screen), else under the pin. Short of room, it sits at the bottom
    /// edge, without a tail.
    private func coachCard(_ coach: Coach, size: CGSize, pane: CGRect) -> some View {
        let hole = spotlight(in: pane) ?? CGRect(x: pane.midX, y: size.height / 2, width: 0, height: 0)
        let gap: CGFloat = 12
        // 46 pt in from the edges on a phone, as in the Figma; less on a narrow side of a fold.
        let width = min(pane.width - (pane.width >= 360 ? 92 : 32), Self.coachWidth)
        let height = coachHeight

        var center = CGPoint(x: pane.midX, y: 0)
        var tail: Bool? = nil // pointing up, down, or none
        // The popup with no room for the whole coach under its pin (the folded iPhone Duo): the
        // coach drops its explanation and sits right under the popup, over the pin. Decided from
        // the room alone, not the coach's height, so it can't flip back and forth.
        let isCompact = stage == .popup && size.height - 8 - (hole.maxY + gap) < 190
        if stage == .popup, let card = frames[.card],
           pane.maxX - card.maxX >= width + gap * 2 || card.minX - pane.minX >= width + gap * 2 {
            let right = pane.maxX - card.maxX >= width + gap * 2
            center.x = right ? card.maxX + gap + width / 2 : card.minX - gap - width / 2
            center.y = min(max(card.midY, height / 2 + 8), size.height - height / 2 - 8)
        } else if stage != .popup, hole.midY > size.height / 2 {
            center.y = hole.minY - gap - height / 2
            tail = false
        } else if isCompact {
            let top = (frames[.card]?.maxY ?? hole.minY) + gap
            center.y = min(top + height / 2, size.height - 8 - height / 2)
        } else {
            let top = hole.maxY + gap
            if top + height <= size.height - 8 {
                center.y = top + height / 2
                tail = true
            } else {
                center.y = size.height - 8 - height / 2
            }
        }

        return CoachCard(
            step: coach.step, title: coach.title, message: isCompact ? nil : coach.message, instruction: coach.instruction,
            tailX: hole.midX, pointsUp: tail ?? true, showsTail: tail != nil, onSkip: { viewModel.skipTour() }
        )
        .accessibilityFocused($isCoachFocused)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { coachHeight = $0 }
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .position(center)
        .opacity(height > 0 ? 1 : 0)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .id(stage)
        .transition(.opacity)
    }

    // MARK: Bar

    /// "Practice round · Join a plan" with its three steps and a ✕ back to the start.
    private var practiceBar: some View {
        let step = switch stage {
        case .findPin, .addButton: 1
        case .popup, .form: 2
        case .ready: 3
        }
        return HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(1...3, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.accent : Theme.separator)
                        .frame(width: index == step ? 22 : 7, height: 7)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
            .accessibilityElement()
            .accessibilityLabel(Text("Step \(step) of 3"))
            Text(mode == .join ? "Practice round · Join a plan" : "Practice round · Host a plan")
                .font(.rounded(.subheadline, .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            Button { viewModel.endPractice() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
                    .tapTarget(.all, 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("End practice round"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(minHeight: 44)
        // The whole top row, so it covers the map's search field on any width.
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: .capsule)
        .shadow(color: Theme.shadowInk.opacity(0.18), radius: 10, y: 3)
        .padding(.horizontal, Theme.gutter)
        .animation(.snappy, value: step)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

// MARK: - Map

/// The campus map, still: no panning, no labels for places, just the streets.
private struct PracticeMapBackdrop: View {
    var campus: University?

    var body: some View {
        Group {
            if let campus {
                Map(initialPosition: .region(campus.region), interactionModes: [])
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            } else {
                Theme.mapFade
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A pretend plan's pin with its point on `tip`, like a real map annotation. With an action it's
/// the pin to tap: a button read as the real pin is, taking taps across its spotlight.
private struct PlacedPin: View {
    var plan: Game
    var people: [PersonSummary]
    var now: Date
    var tip: CGPoint
    var isSelected = false
    var action: (() -> Void)?
    @State private var height: CGFloat = 0

    var body: some View {
        let anchor = EventPin.anchor(for: plan, now: now)
        let pin = EventPin(event: plan, people: people, now: now, isSelected: isSelected, isDimmed: false)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        Group {
            if let action {
                Button(action: action) {
                    // The spotlight's 132 pt circle, without moving the pin.
                    pin.padding(40).contentShape(.circle).padding(-40)
                }
                .buttonStyle(.plain)
            } else {
                pin
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .position(x: tip.x, y: tip.y + (0.5 - anchor.y) * height)
    }
}

/// The real map's search bar, nearby count and bars, drawn for the practice in the same places as
/// on the map (`EventMapView.mapActions`): bottom bars on a phone; on a wide screen Make a plan at
/// its natural size; with the iPhone Duo's vertical bar, search, saved plans, recenter, Filter and
/// the avatar in a column on its side, and only Make a plan below. Drawn here rather than as real
/// bars so the spotlight's dimming covers them. Only Make a plan works, and only when the coach
/// says to tap it.
private struct MapChrome: View {
    var addButtonIsLive: Bool
    var showsBottomBar = true
    var onAdd: () -> Void
    var onAddFrame: (CGRect) -> Void
    @Environment(\.barLayout) private var barLayout
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The vertical bar's buttons, from the window's top and bottom edges, as iOS places them
    /// for the real map: measured on the iPhone Duo (Nov 26). The cover display's status column
    /// is taller (the camera sits above the clock), so its top group starts lower.
    private static let searchCenterCompact: CGFloat = 198
    private static let searchCenterRegular: CGFloat = 152
    /// Between one button and the next in a group.
    private static let sideBarStep: CGFloat = 52
    /// Filter's center, up from the bottom; recenter is a step above it.
    private static let filterCenterFromBottom: CGFloat = 108
    private static let avatarCenterFromBottom: CGFloat = 48

    var body: some View {
        GeometryReader { proxy in
            let isWide = sizeClass == .regular
            let isLandscape = proxy.size.width > proxy.size.height
            VStack(alignment: .leading, spacing: 12) {
                // With a vertical bar, search and saved plans are in it.
                if !barLayout.isVertical { searchRow }
                nearbyChip
                Spacer()
                bottomRow(isWide: isWide, isLandscape: isLandscape, width: proxy.size.width)
                    .opacity(showsBottomBar ? 1 : 0)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .overlay {
                if case .vertical(let edge) = barLayout {
                    sideBar(edge: edge, size: proxy.size, insets: proxy.safeAreaInsets)
                        .opacity(showsBottomBar ? 1 : 0)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .allowsHitTesting(addButtonIsLive)
        .accessibilityElement(children: addButtonIsLive ? .contain : .ignore)
        .accessibilityHidden(!addButtonIsLive)
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text("Search plans")
                Spacer()
            }
            .font(.rounded(.body))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .appGlass(in: .capsule)
            circle("bookmark")
        }
    }

    private var nearbyChip: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(Activity.builtIn.prefix(4)) { Circle().fill($0.color).frame(width: 8, height: 8) }
            }
            Text("5 plans nearby")
                .font(.rounded(.subheadline, .bold))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .appGlass(in: .capsule)
    }

    /// Phone: Filter · Make a plan · avatar, with recenter floating above the avatar; Make a plan
    /// as wide as the map's (the screen less 240 pt). Wide: Make a plan at its natural size. With a
    /// vertical bar: Make a plan alone, centered, or held left in landscape on a wide screen.
    @ViewBuilder
    private func bottomRow(isWide: Bool, isLandscape: Bool, width: CGFloat) -> some View {
        if barLayout.isVertical {
            HStack {
                if !(isWide && isLandscape) { Spacer(minLength: 0) }
                addButton(width: nil)
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .trailing, spacing: 12) {
                circle("location")
                HStack(spacing: 10) {
                    circle("line.3.horizontal.decrease")
                    Spacer(minLength: 0)
                    addButton(width: isWide ? nil : max(140, width - 240))
                    Spacer(minLength: 0)
                    avatar
                }
            }
        }
    }

    private func addButton(width: CGFloat?) -> some View {
        Button(action: onAdd) {
            Label("Make a plan", systemImage: "plus")
                .labelStyle(IconRowLabelStyle(iconWidth: 16, spacing: 6))
                .font(.rounded(.headline, .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: width)
                .padding(.horizontal, 10)
                .frame(minHeight: 50)
                .background(Theme.accent, in: .capsule)
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(PracticeMapStep.space)) } action: { onAddFrame($0) }
        .allowsHitTesting(addButtonIsLive)
        .accessibilityHidden(!addButtonIsLive)
    }

    /// The vertical bar, in the side column like iOS's: search and saved plans at the top;
    /// recenter and Filter, then the avatar, at the bottom.
    private func sideBar(edge: HorizontalEdge, size: CGSize, insets: EdgeInsets) -> some View {
        let inset = edge == .trailing ? insets.trailing : insets.leading
        // In the column's middle, or just inside the edge when there's no column.
        let x = edge == .trailing
            ? (inset > 0 ? size.width + inset / 2 : size.width - 30)
            : (inset > 0 ? -inset / 2 : 30)
        let windowTop = -insets.top
        let windowBottom = size.height + insets.bottom
        let searchCenter = sizeClass == .regular ? Self.searchCenterRegular : Self.searchCenterCompact
        return ZStack {
            group(["magnifyingglass", "bookmark"])
                .position(x: x, y: windowTop + searchCenter + Self.sideBarStep / 2)
            group(["location", "line.3.horizontal.decrease"])
                .position(x: x, y: windowBottom - Self.filterCenterFromBottom - Self.sideBarStep / 2)
            avatar
                .position(x: x, y: windowBottom - Self.avatarCenterFromBottom)
        }
    }

    private func group(_ symbols: [String]) -> some View {
        VStack(spacing: 0) {
            ForEach(symbols, id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 46, height: Self.sideBarStep)
            }
        }
        .appGlass(in: .capsule)
    }

    private func circle(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 48, height: 48)
            .appGlass(in: .circle)
    }

    private var avatar: some View {
        MeToken(name: "", size: 44, ring: 3)
            .frame(width: 48, height: 48)
            .appGlass(in: .circle)
    }
}

// MARK: - Spotlight

/// The map dimmed, with a rounded hole where the next tap goes and a green ring around it. It
/// never takes a tap: what's under the hole is tapped through it.
private struct SpotlightScrim: View {
    var hole: CGRect?
    var cornerRadius: CGFloat
    /// A second opening, a capsule with no ring.
    var alsoLit: CGRect?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .named(PracticeMapStep.space)).origin
            let local = hole?.offsetBy(dx: -origin.x, dy: -origin.y)
            let second = alsoLit?.offsetBy(dx: -origin.x, dy: -origin.y)
            ZStack {
                ScrimShape(hole: local ?? .zero, cornerRadius: cornerRadius, alsoLit: second ?? .zero)
                    .fill(Theme.scrim, style: FillStyle(eoFill: true))
                if let local {
                    RoundedRectangle(cornerRadius: cornerRadius + 8)
                        .stroke(.white.opacity(0.7), lineWidth: 3)
                        .frame(width: local.width + 16, height: local.height + 16)
                        .position(x: local.midX, y: local.midY)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Theme.accent, lineWidth: 4)
                        .frame(width: local.width, height: local.height)
                        .position(x: local.midX, y: local.midY)
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.15), value: local)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The whole screen, less a rounded rectangle (even-odd fill).
private nonisolated struct ScrimShape: Shape {
    var hole: CGRect
    var cornerRadius: CGFloat
    /// A capsule-shaped second hole; it appears and goes without animating.
    var alsoLit: CGRect = .zero

    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(hole.animatableData, cornerRadius) }
        set {
            hole.animatableData = newValue.first
            cornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if !hole.isEmpty {
            let radius = min(cornerRadius, hole.width / 2, hole.height / 2)
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius))
        }
        if !alsoLit.isEmpty, !alsoLit.intersects(hole) {
            path.addRoundedRect(in: alsoLit, cornerSize: CGSize(width: alsoLit.height / 2, height: alsoLit.height / 2))
        }
        return path
    }
}

/// The practice round's coach: which step, what to notice, and what to tap, with Skip tour.
private struct CoachCard: View {
    var step: Int
    var title: String
    /// Left out where there's no room for it.
    var message: String?
    var instruction: String
    /// Where the tail points, in the practice's coordinate space.
    var tailX: CGFloat
    var pointsUp: Bool
    var showsTail = true
    var onSkip: () -> Void
    @State private var frame: CGRect = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StepTag(text: Text("Step \(step) of 3"))
                Spacer(minLength: 8)
                Button("Skip tour", action: onSkip)
                    .font(.rounded(.subheadline, .bold))
                    .foregroundStyle(Theme.mutedLarge)
                    .buttonStyle(.plain)
                    .tapTarget(.vertical, 12)
            }
            Text(verbatim: title)
                .font(.rounded(.title3, .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(verbatim: message)
                    .font(.rounded(.body))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Circle().fill(Theme.accent).frame(width: 9, height: 9).accessibilityHidden(true)
                Text(verbatim: instruction)
                    .font(.rounded(.callout, .bold))
                    .foregroundStyle(Theme.accentText)
            }
        }
        .padding(18)
        .background(Theme.card, in: .rect(cornerRadius: 26))
        .overlay(alignment: pointsUp ? .top : .bottom) {
            if showsTail {
                CalloutTail()
                    .fill(Theme.card)
                    .frame(width: 26, height: 12)
                    .rotationEffect(.degrees(pointsUp ? 180 : 0))
                    .offset(x: tailOffset, y: pointsUp ? -11 : 11)
                    .accessibilityHidden(true)
            }
        }
        .shadow(color: Theme.shadowInk.opacity(0.18), radius: 14, y: 6)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(PracticeMapStep.space)) } action: { frame = $0 }
        .accessibilityElement(children: .contain)
    }

    /// From the card's middle to the spotlight's, kept clear of the rounded corners.
    private var tailOffset: CGFloat {
        guard frame.width > 0 else { return 0 }
        let limit = frame.width / 2 - 34
        return min(max(tailX - frame.midX, -limit), limit)
    }
}

/// Grey fine print for what the practice did and didn't do.
struct PracticeNote: View {
    var text: Text

    var body: some View {
        text
            .font(.rounded(.footnote))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 14).fill(Theme.separator).contrastOpacity(0.6) }
    }
}

// MARK: - Form (H2)

/// Make a plan, filled in from the practice sport and the time of day. Name, people and the note
/// can change; the rest is shown as it would be.
private struct PracticeFormSheet: View {
    @Binding var plan: PracticePlan
    var campus: University?
    var now: Date
    var onPeopleFrame: (CGRect) -> Void
    var onCreateFrame: (CGRect) -> Void
    var onClose: () -> Void
    var onCreate: () -> Void
    @FocusState private var focus: Field?
    @State private var contentBottom: CGFloat = 0
    @State private var buttonTop: CGFloat = .infinity
    @State private var scroll = ScrollPosition(edge: .top)

    private enum Field { case name, notes }

    private var hasMore: Bool { MoreBelowHint.isNeeded(contentBottom: contentBottom, shownBottom: buttonTop) }

    var body: some View {
        let start = PracticeRound.hostedStart(now: now)
        let place = PracticeRound.place(for: plan.activity, campus: campus)

        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.separator)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .accessibilityHidden(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SheetHeader(title: Text("Make a plan"), subtitle: Text("Get something going nearby.")) { onClose() }
                        .padding(.bottom, 2)
                    FieldBox("Sport", showsChevron: true) {
                        Text("\(plan.activity.emoji)  \(plan.activity.name)")
                            .accessibilityLabel(Text(plan.activity.name))
                    }
                    FieldBox("What's the plan?", text: $plan.title, prompt: Text("Name your plan"), isFocused: focus == .name) { field in
                        field
                            .textInputAutocapitalization(.sentences)
                            .focused($focus, equals: .name)
                    }
                    FieldBox("When", showsChevron: true) { Text(verbatim: EventFormat.dayAndTime(start)) }
                    FieldBox("Where", showsChevron: true) { Text(verbatim: place.name) }
                    peopleCard
                    OptionalQuestion("What would help someone new say yes?")
                        .padding(.top, 2)
                    TextField("Chill, all levels welcome. Coming alone is fine.", text: $plan.notes, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.rounded(.callout))
                        .foregroundStyle(Theme.ink)
                        .focused($focus, equals: .notes)
                        .padding(14)
                        .cardSurface(radius: Theme.Radius.field)
                }
                .reportsBottom($contentBottom)
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 12)
                .readableColumn()
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .scrollPosition($scroll)

            Button("Create plan", action: onCreate)
                .pill(.primary)
                .disabled(plan.title.trimmingCharacters(in: .whitespaces).isEmpty)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(PracticeMapStep.space)) } action: { onCreateFrame($0) }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .readableColumn()
                .reportsTop($buttonTop)
                .moreBelowHint(isShown: hasMore) { withAnimation(.snappy) { scroll.scrollTo(edge: .bottom) } }
                .animation(.easeOut(duration: 0.2), value: hasMore)
        }
        .background {
            UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.sheet, topTrailingRadius: Theme.Radius.sheet)
                .fill(Theme.background)
                .ignoresSafeArea(edges: [.bottom, .horizontal])
        }
        .padding(.top, 120)
    }

    /// The real form's people card: "6 people", "Including you", and a stepper.
    private var peopleCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("People")
                    .font(.rounded(.caption))
                    .foregroundStyle(Theme.muted)
                Text(verbatim: String.app("\(plan.capacity) people"))
                    .font(.rounded(.body, .bold))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text("Including you")
                    .font(.rounded(.caption))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Stepper("People", value: $plan.capacity.animation(.snappy), in: GameDraft.capacityRange)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .cardSurface(radius: Theme.Radius.field)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(PracticeMapStep.space)) } action: { onPeopleFrame($0) }
        // One adjustable element: swipe up or down to change the count (A11Y-14).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("People"))
        .accessibilityValue(Text(verbatim: "\(String.app("\(plan.capacity) people")), \(String.app("Including you"))"))
        .accessibilityAdjustableAction { direction in
            let range = GameDraft.capacityRange
            switch direction {
            case .increment: plan.capacity = min(plan.capacity + 1, range.upperBound)
            case .decrement: plan.capacity = max(plan.capacity - 1, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

/// "Your plan is ready" (H3): the plan as others will see it, the note, and the two ways on. The
/// middle scrolls when the sheet is capped under the pin; the buttons stay put.
private struct ReadySheet: View {
    var plan: Game
    var now: Date
    var titleFocus: AccessibilityFocusState<Bool>.Binding
    var onKeep: () -> Void
    var onTryJoining: () -> Void
    @State private var contentBottom: CGFloat = 0
    @State private var buttonsTop: CGFloat = .infinity
    @State private var contentHeight: CGFloat = 0
    @State private var scroll = ScrollPosition(edge: .top)

    private var hasMore: Bool { MoreBelowHint.isNeeded(contentBottom: contentBottom, shownBottom: buttonsTop) }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.separator)
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StepTag(text: Text("Step 3 of 3 · Done"))
                    Text("Your plan is ready")
                        .font(.rounded(.title, .bold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused(titleFocus)
                    ReadyCard(plan: plan, now: now)
                    PracticeNote(text: Text("Practice plans aren't posted. Keep this one and it'll be waiting in Make a plan once your account is in."))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .reportsBottom($contentBottom)
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 12)
                .readableColumn()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollPosition($scroll)
            // As tall as its content, up to the cap the map sets.
            .frame(maxHeight: contentHeight > 0 ? contentHeight : nil)

            VStack(spacing: 10) {
                Button("Keep this plan", action: onKeep)
                    .pill(.primary)
                Button("Try joining a plan too", action: onTryJoining)
                    .pill(.quiet)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .readableColumn()
            .background(Theme.card)
            .reportsTop($buttonsTop)
            .moreBelowHint(isShown: hasMore, fade: Theme.card) { withAnimation(.snappy) { scroll.scrollTo(edge: .bottom) } }
            .animation(.easeOut(duration: 0.2), value: hasMore)
        }
        .background {
            UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.sheet, topTrailingRadius: Theme.Radius.sheet)
                .fill(Theme.card)
                .ignoresSafeArea(edges: [.bottom, .horizontal])
                .shadow(color: Theme.shadowInk.opacity(0.15), radius: 12, y: -2)
        }
    }
}

/// "Your plan is ready": the plan as others will see it, on a grey card.
private struct ReadyCard: View {
    var plan: Game
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(plan.activity.emoji).accessibilityHidden(true)
                Text(verbatim: plan.hostLine)
            }
            .font(.rounded(.subheadline))
            .foregroundStyle(Theme.muted)
            Text(verbatim: plan.title)
                .font(.rounded(.title2, .bold))
                .foregroundStyle(Theme.ink)
            TokenRow(lineup: Lineup(people: [PracticeRound.you], open: plan.spotsLeft, myID: PracticeRound.you.id), size: 32, openFill: .clear)
            Text(verbatim: plan.roomLine)
                .font(.rounded(.subheadline, .bold))
                .foregroundStyle(Theme.accentText)
            Text(verbatim: "\(EventFormat.dayAndTime(plan.startsAt)) · \(plan.place.name)")
                .font(.rounded(.subheadline))
                .foregroundStyle(Theme.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background, in: .rect(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// Laid out across `pane`'s width and no further: one side of a fold, or the whole screen.
    func inPane(_ pane: CGRect) -> some View {
        frame(width: pane.width)
            .padding(.leading, pane.minX)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension CGRect {
    /// Less the room the iPhone Duo's vertical bar takes on its side.
    func avoidingSideBar(_ layout: BarLayout) -> CGRect {
        guard case .vertical(let edge) = layout else { return self }
        let bar: CGFloat = 72
        return edge == .trailing
            ? CGRect(x: minX, y: minY, width: max(width - bar, 0), height: height)
            : CGRect(x: minX + bar, y: minY, width: max(width - bar, 0), height: height)
    }
}
