import CoreLocation
import MapKit
import SwiftUI

/// Figma: "Sports event map" (341:1979) and "Popup" (341:2046), plus search results, Filter
/// games, the empty map and the location primer. The popup is part of the selected pin's
/// annotation, so MapKit moves it with the pin like any map callout.
struct EventMapView: View {
    @Environment(GameStore.self) private var store
    @Environment(AppViewModel.self) private var appViewModel
    @State private var viewModel = EventMapViewModel()
    @State private var presentationTime = Date.now
    @State private var screenSize: CGSize = .zero
    @State private var showsSaved = false
    @State private var showsFilters = false
    /// Every game on the map in one list: VoiceOver's "List games" action, for getting through
    /// the games without hunting pin by pin (A11Y-02).
    @State private var listsAllGames = false
    /// A popup just opened at an accessibility size: pan again once its real height is known.
    @State private var remeasuresPopup: UUID?
    /// The map's own frame, full screen, in global coordinates: its size tells how close pins
    /// are on screen.
    @State private var mapFrame: CGRect = .zero
    /// The safe area in global coordinates, so the popup keeps clear of a vertical side bar.
    @State private var safeFrame: CGRect = .zero
    /// A partially open iPhone Duo's fold, in the map's own points; nil when the screen is flat.
    @State private var fold: CGRect?
    /// Keeps When-In-Use location authorized while the map is up.
    @State private var locationSession: CLServiceSession?
    /// "See games near you", before the iOS prompt.
    @State private var asksForLocation = false
    @State private var declinedLocationPrimer = UserDefaults.standard.bool(forKey: EventMapView.declinedPrimerKey)
    /// The avatar's frame in the bottom bar, so the location button sits right above it.
    @State private var avatarFrame: CGRect = .zero
    @State private var locationButtonWidth: CGFloat = 0
    /// With a vertical bar, the search field only shows after tapping Search in the bar.
    @State private var showsSearchField = false
    @FocusState private var isSearchFocused: Bool
    /// Bottom bars, or the iPhone Duo's side bar. Read at the root, since a reader in here missed
    /// the change after a fold.
    @Environment(\.barLayout) private var barLayout
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    /// Room around wrapped text in the overlays at accessibility sizes; smaller sizes keep their heights.
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct AttendeeDemandKey: Hashable {
        let games: [Game]
        let revision: Int
        let sessionID: UUID
    }

    private static let declinedPrimerKey = "declinedLocationPrimer"
    /// The bottom bar's round buttons (Filter).
    private static let mapButtonSize: CGFloat = 48
    /// Widest the search field gets: the open iPhone Duo's portrait width less the gutters
    /// (669 − 40), so it fills that screen as it does a phone's.
    private static let searchWidth: CGFloat = 630
    /// What the open iPhone Duo's top row keeps besides the field: the 20 pt leading margin, and on
    /// the right Saved games, the bar's spacing and the status area. Nothing reports where the
    /// status area is, so this is measured: in portrait (669 pt) the bar fits a field ending at
    /// 448 pt and folds both items into a "…" menu past that. 10 pt of margin on top. Fixed, so a
    /// rotation needs no measuring.
    private static let navigationRowReserve: CGFloat = 20 + 221 + 10
    /// How far the avatar draws past the room its label claims in the bottom bar.
    private static let avatarOverhang: CGFloat = 5
    /// The field, chip and banners float over the map and stop growing here: at the largest
    /// sizes the field alone would cover a third of the map (A11Y-06). Arianna picks the cap.
    private static let overlayTypeCap = DynamicTypeSize.accessibility2
    /// A search result's height at the default text size; rows grow with the text.
    @ScaledMetric(relativeTo: .body) private var resultRowHeight: CGFloat = 68

    var body: some View {
        // Pins, chip, cards and search all read this one pass over the store.
        let frame = viewModel.frame(in: store, now: presentationTime, mapSize: mapSize)
        let attendeeDemand = AttendeeDemandKey(
            games: frame.attendeeDemand, revision: store.attendeeRevision, sessionID: store.sessionID
        )

        map(frame, now: presentationTime)
        .overlay { if isSearching { searchScrim } }
        .overlay(alignment: .top) { topBackdrop }
        .overlay { if !isSearching { emptyOrFailedCard(frame) } }
        .overlay(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                // The field and its results run the full width up to `searchWidth`: edge to edge
                // on a phone and the open iPhone Duo in portrait, not across a landscape screen.
                // The chip and banners keep a phone's column.
                if showsSearchRow, !searchInNavigationBar {
                    searchRow
                        .frame(maxWidth: Self.searchWidth)
                        .dynamicTypeSize(...Self.overlayTypeCap)
                }
                if isSearching {
                    searchResults(frame.filtered).frame(maxWidth: Self.searchWidth)
                } else {
                    Group {
                        // The popup opens right under the search bar, where the chip is.
                        if viewModel.popupID == nil { nearbyChip(frame.filtered) }
                        if store.isOffline, !frame.open.isEmpty { OfflineBanner() }
                        if showsLocationBanner { locationBanner }
                    }
                    .frame(maxWidth: Theme.columnWidth, alignment: .leading)
                    .dynamicTypeSize(...Self.overlayTypeCap)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottomLeading) {
            if !usesVerticalBar, !isSearching { locationButton }
        }
        .toolbar { mapActions }
        .sheet(isPresented: $showsSaved) {
            SavedGamesSheet { appViewModel.path.append(.game($0)) }
        }
        .sheet(isPresented: Binding(get: { !viewModel.groupedIDs.isEmpty }, set: { if !$0 { viewModel.groupedIDs = [] } })) {
            PinGroupSheet(gameIDs: viewModel.groupedIDs, viewModel: viewModel) { appViewModel.path.append(.game($0)) }
        }
        .sheet(isPresented: $showsFilters) {
            FilterSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $listsAllGames) {
            // In the search list's order: spots that just opened, then soonest.
            let games = viewModel.searchResults(from: frame.filtered, now: presentationTime)
            PinGroupSheet(
                gameIDs: games.map(\.id), viewModel: viewModel,
                title: Text(games.count == 1 ? "1 game nearby" : "\(games.count) games nearby"), subtitle: nil
            ) { appViewModel.path.append(.game($0)) }
        }
        .dialog(isPresented: $asksForLocation, isDismissable: false) {
            DialogCard(
                systemImage: "mappin.and.ellipse", tone: .tinted(Color(.sportVolleyball)),
                title: Text("See games near you"),
                message: Text("We use your location only while the app is open, to show games within walking distance. Your exact spot is never shared."),
                confirm: .init("Allow location") { allowLocation() },
                cancel: .init("Not now") { declineLocation() }
            )
        }
        .onAppear {
            #if DEBUG
            switch UserDefaults.standard.string(forKey: "screen") {
            case "saved": showsSaved = true
            case "filter": showsFilters = true
            case "search": viewModel.searchText = "hoops"
            case "all-games": listsAllGames = true
            default: break
            }
            #endif
            startLocation()
        }
        .task(id: store.campus) { viewModel.setCampus(store.campus) }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            // Location may have been turned on in Settings while the app was away.
            startLocation()
            if locationSession != nil { await viewModel.locate() }
        }
        // One clock drives pins, counts, search, eligibility and selection together.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            presentationTime = .now
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                presentationTime = .now
            }
        }
        // Group pins show sports/counts rather than faces. Fetch only filtered, visible single
        // pins and the selected game; Game values also invalidate demand when counts change.
        .task(id: attendeeDemand) {
            await store.loadMissingAttendees(for: attendeeDemand.games.map(\.id))
        }
        .toolbarBackgroundVisibility(.hidden, for: .bottomBar)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { screenSize = $0 }
        .onGeometryChange(for: CGRect.self) { proxy in
            let frame = proxy.frame(in: .global), insets = proxy.safeAreaInsets
            return CGRect(
                x: frame.minX + insets.leading, y: frame.minY + insets.top,
                width: frame.width - insets.leading - insets.trailing,
                height: frame.height - insets.top - insets.bottom
            )
        } action: { safeFrame = $0 }
        // Never shown here, but names the back button on pushed screens.
        .navigationTitle(String.app("Map"))
        // The vertical bar hosts the navigation bar's items (search, saved games), and so does
        // the open iPhone Duo's top row beside the status area (`searchInNavigationBar`); on a
        // phone those controls float over the map instead.
        .toolbar(showsNavigationBar ? .automatic : .hidden, for: .navigationBar)
        // Without a title the navigation bar collapses, leaving the map full height.
        .toolbar(removing: showsNavigationBar ? .title : nil)
        .toolbarTitleDisplayMode(showsNavigationBar ? .inline : .automatic)
        .animation(.spring(duration: 0.4, bounce: 0.22), value: viewModel.selectedID)
        .animation(.snappy, value: isSearching)
        #if DEBUG
        .onAppear { viewModel.openDebugPopup(in: store) }
        #endif
        // Make room for the popup above a newly selected pin, like a map callout.
        .onChange(of: viewModel.selectedID) { _, id in
            viewModel.selectionChanged(to: id)
            remeasuresPopup = typeSize.isAccessibilitySize ? id : nil
            guard let id, let event = store.game(id) else { return }
            viewModel.reveal(event, mapSize: mapSize, area: popupArea, popupWidth: popupWidth)
        }
        .onChange(of: store.lastCreatedID) { _, id in
            guard let id, let event = store.game(id) else { return }
            viewModel.focus(on: event)
        }
        .onAppear { focusOnMySportsIfAsked() }
        .onChange(of: appViewModel.focusMapOnMySports) { _, _ in focusOnMySportsIfAsked() }
        .onChange(of: store.profile?.id) { _, _ in focusOnMySportsIfAsked() }
        .onChange(of: frame.filtered.map(\.id)) { _, ids in
            if let id = viewModel.selectedID, !ids.contains(id) { viewModel.dropSelection() }
            viewModel.groupedIDs.removeAll { !ids.contains($0) }
        }
        // A popup and the results list would cover each other.
        .onChange(of: isSearching) { _, searching in
            if searching { viewModel.selectedID = nil }
        }
        // Bottom bars always show the field, so a field opened from the side bar would come back
        // already open after the next fold.
        .onChange(of: barLayout) { _, layout in
            if !layout.isVertical { showsSearchField = false }
        }
    }

    /// A win-back tap opens the map already filtered to the sports on your profile.
    private func focusOnMySportsIfAsked() {
        guard appViewModel.focusMapOnMySports, let profile = store.profile else { return }
        viewModel.sportFilter = Set(profile.interests)
        appViewModel.focusMapOnMySports = false
    }

    // MARK: Map

    @MapContentBuilder
    private func eventPin(_ event: Game, now: Date) -> some MapContent {
        let isSelected = viewModel.selectedID == event.id
        Annotation(event.title, coordinate: event.coordinate, anchor: EventPin.anchor(for: event, now: now)) {
            EventPin(
                event: event,
                people: Array(store.lineup(for: event).people.prefix(3)),
                now: now,
                isSelected: isSelected,
                isDimmed: viewModel.selectedID != nil && !isSelected
            )
            // Annotation content doesn't inherit the environment.
            .environment(\.currentUserID, store.profile?.id)
            .fontDesign(.rounded)
        }
        .annotationTitles(.hidden)
        .tag(event.id)
    }

    /// Not selectable: tapping lists its games instead of opening a popup.
    private func groupPin(_ group: PinGroup) -> some MapContent {
        Annotation(String.app("\(group.games.count) games here"), coordinate: group.coordinate, anchor: GroupPin.anchor) {
            GroupPin(games: group.games, isDimmed: viewModel.selectedID != nil)
                .fontDesign(.rounded)
                .onTapGesture { viewModel.groupedIDs = group.games.map(\.id) }
                // VoiceOver's double tap, without relying on its simulated tap reaching the gesture.
                .accessibilityAction { viewModel.groupedIDs = group.games.map(\.id) }
        }
        .annotationTitles(.hidden)
    }

    private func map(_ frame: EventMapViewModel.MapFrame, now: Date) -> some View {
        @Bindable var viewModel = viewModel

        // Native selection: tap a pin to select, tap empty map to dismiss the popup.
        return Map(position: $viewModel.position, selection: $viewModel.selectedID) {
            if let mock = LocationService.mockCoordinate {
                Annotation("You", coordinate: mock, anchor: .center) {
                    UserPin(name: store.profile?.fullName ?? "")
                }
                .annotationTitles(.hidden)
            } else {
                UserAnnotation {
                    UserPin(name: store.profile?.fullName ?? "")
                }
            }

            ForEach(frame.groups) { group in
                if group.games.count == 1, let event = group.games.first {
                    eventPin(event, now: now)
                } else {
                    groupPin(group)
                }
            }

            // The popup is its own annotation on the pin's coordinate, so MapKit moves it with
            // the pin, and the pin's annotation never changes size (which made MapKit swap and
            // cross-fade it). Added last so it draws over the pins.
            if let id = viewModel.popupID, let event = store.game(id) {
                // Titled, though MapKit then lists the game a second time: untitled, it says "Map pin".
                Annotation(event.title, coordinate: event.coordinate, anchor: viewModel.popupAnchor(for: event)) {
                    EventPopup(event: event, viewModel: viewModel)
                        .frame(width: popupWidth)
                        // Annotation content doesn't inherit the environment.
                        .environment(store)
                        .environment(appViewModel)
                        .environment(\.currentUserID, store.profile?.id)
                        .fontDesign(.rounded)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            let grew = height > viewModel.popupHeight + 1
                            viewModel.popupHeight = height
                            // At accessibility sizes the card is much taller than the height the
                            // first pan allowed for, so pan again once it's measured (A11Y-06).
                            // Only as it opens: a later change (the text size) leaves the map be.
                            guard remeasuresPopup == event.id else { return }
                            remeasuresPopup = nil
                            if grew { viewModel.reveal(event, mapSize: mapSize, area: popupArea, popupWidth: popupWidth) }
                        }
                        // Grows out of / shrinks into the pin. Annotation content is hosted outside
                        // this view's transactions, so the animation is declared in here.
                        .scaleEffect(viewModel.isPopupShown ? 1 : 0.1, anchor: .bottom)
                        .opacity(viewModel.isPopupShown ? 1 : 0)
                        .animation(.spring(duration: 0.4, bounce: 0.22), value: viewModel.isPopupShown)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .listGamesAction(frame.filtered) { listsAllGames = true }
        // Closes the popup once its pin scrolls off screen.
        .onMapCameraChange(frequency: .continuous) { context in
            let selected = viewModel.selectedID.flatMap { store.game($0) }
            viewModel.cameraChanged(to: context.region, selected: selected)
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.cameraSettled(on: context.region)
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { mapFrame = $0 }
        .onGeometryChange(for: CGRect?.self) { $0.activeFold } action: { fold = $0 }    }

    private var mapSize: CGSize { mapFrame.size }

    /// Where a popup has to fit, in the map's points: the safe area (clear of a vertical side
    /// bar), below the search field when the bar has opened it, and on a partially open iPhone
    /// Duo the larger side of the fold.
    private var popupArea: CGRect {
        guard !safeFrame.isEmpty else { return .null }
        var area = safeFrame.offsetBy(dx: -mapFrame.minX, dy: -mapFrame.minY)
        if usesVerticalBar, showsSearchField {
            // The field's 8 pt top padding and 48 pt height (see `searchRow`).
            area.origin.y += 56
            area.size.height -= 56
        }
        if let fold { area = area.pane(avoiding: fold) }
        return area
    }

    /// 16 pt from each edge of the space it opens in (the screen, on a phone), as in the Figma;
    /// never wider than the Figma card.
    private var popupWidth: CGFloat {
        let area = popupArea
        return min(max((area.isNull ? screenSize.width : area.width) - 32, 280), 370)
    }

    /// Soft fade behind the search bar ("Search backdrop" layer).
    private var topBackdrop: some View {
        // Measured from the safe area's top, so it ends just under the field on any screen: a
        // phone's 62 pt status area gives the Figma's 212 pt. Shorter under a popup, so the fade
        // doesn't wash out the top of the card.
        let topInset = safeFrame.isEmpty ? 0 : max(0, safeFrame.minY - mapFrame.minY)
        return LinearGradient(
            stops: [
                .init(color: Theme.background.opacity(0.95), location: 0),
                .init(color: Theme.background.opacity(0.8), location: 0.65),
                .init(color: Theme.background.opacity(0), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: topInset + (viewModel.popupID == nil ? 150 : 88))
        .ignoresSafeArea()
        // With a side bar the field only shows after tapping Search; without it there's nothing
        // to fade behind (the chip has its own glass), and the fade would only wash out the map.
        // Animated by whatever changes it: Search, search focus, or the root's bar change.
        .opacity(showsSearchRow ? 1 : 0)
        .allowsHitTesting(false)
    }

    // MARK: Search

    /// Also while searching, so results never show without a field to edit or clear.
    private var showsSearchRow: Bool {
        !usesVerticalBar || showsSearchField || isSearching
    }

    /// The open iPhone Duo in portrait (wide, no vertical bar) has a row beside the status area
    /// that the navigation bar uses on every other screen. The field and Saved go there, so they
    /// don't take a row of the map below it. The system keeps them clear of the status area;
    /// nothing reports where it is, so it can't be done by hand.
    private var searchInNavigationBar: Bool {
        !usesVerticalBar && isWideLayout
    }

    private var showsNavigationBar: Bool {
        usesVerticalBar || searchInNavigationBar
    }

    /// The field fills the navigation bar's row up to Saved games, which sits just before the
    /// status area.
    private var navigationFieldWidth: CGFloat {
        max(200, min(Self.searchWidth, screenSize.width - Self.navigationRowReserve))
    }

    /// Typing, or left with a query in the field: the results list is over the map.
    private var isSearching: Bool {
        isSearchFocused || !viewModel.searchText.isEmpty
    }

    private var searchRow: some View {
        HStack(spacing: 12) {
            searchField

            // With a vertical bar, Saved games lives in the bar instead.
            if !usesVerticalBar {
                Button("Saved games", systemImage: "bookmark") { openSaved() }
                    .font(.title3.weight(.medium))
                    .glassCircle()
            }
        }
        .foregroundStyle(Theme.ink)
    }

    private var searchField: some View {
        @Bindable var viewModel = viewModel

        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            TextField("Search games", text: $viewModel.searchText)
                .font(.rounded(.body, isSearching ? .bold : .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)
                // The scrim that ends search by tap is hidden from VoiceOver (A11Y-20).
                .accessibilityAction(.escape) { endSearch() }
                // Opened from the bar's Search button, so start typing right away.
                .onAppear { if usesVerticalBar { isSearchFocused = true } }
            if isSearching {
                ClearFieldButton { endSearch() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, typeSize.isAccessibilitySize ? 8 : 0)
        .frame(minHeight: 48)
        .appGlass(in: .capsule, interactive: true)
        .foregroundStyle(Theme.ink)
    }

    /// Fades the map out behind the results. Tapping it leaves search.
    private var searchScrim: some View {
        Theme.background.opacity(0.78)
            .ignoresSafeArea()
            .onTapGesture { endSearch() }
            .accessibilityHidden(true)
            .transition(.opacity)
    }

    /// Figma "Search results": "Basketball near you" over a card of matching games.
    private func searchResults(_ games: [Game]) -> some View {
        let results = viewModel.searchResults(from: games, now: presentationTime)

        return VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: results.isEmpty ? String.app("No games match that search") : viewModel.resultsTitle(for: results))
                .font(.rounded(.footnote, .bold))
                .foregroundStyle(Theme.muted)
                .padding(.leading, 4)

            if !results.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { event in
                            Button {
                                isSearchFocused = false
                                appViewModel.path.append(.game(event.id))
                            } label: {
                                GameListRow(event: event, line: viewModel.resultLine(for: event))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: min(CGFloat(results.count) * resultRowHeight, max(screenSize.height * 0.5, 204)))
                .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card))
                .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: 3)
            }
        }
        // The list changes as you type without moving focus (A11Y-03).
        .announcesChanges(of: viewModel.resultsAnnouncement(for: results))
        .transition(.opacity)
    }

    /// Clears the query and puts the keyboard away; with a vertical bar, hides the field too.
    private func endSearch() {
        isSearchFocused = false
        viewModel.searchText = ""
        if usesVerticalBar { withAnimation(.snappy) { showsSearchField = false } }
    }

    // MARK: Chips and cards

    /// Tapping refreshes: a map can't pull to refresh, because dragging pans it.
    private func nearbyChip(_ games: [Game]) -> some View {
        // One dot per sport on the map, in the sports' usual order.
        let sports = Array(Set(games.map(\.activity))).sorted { $0.sortOrder < $1.sortOrder }.prefix(4)

        return Button {
            Task { await store.refreshMap() }
        } label: {
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    if sports.isEmpty {
                        ForEach(store.postableActivities.prefix(4)) { Circle().fill($0.color).frame(width: 6, height: 6) }
                    } else {
                        ForEach(sports) { Circle().fill($0.color).frame(width: 6, height: 6) }
                    }
                }
                if games.isEmpty {
                    Text("Quiet around here")
                } else {
                    Text(games.count == 1 ? "1 game nearby" : "\(games.count) games nearby")
                }
            }
            .font(.rounded(.footnote))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, typeSize.isAccessibilitySize ? 6 : 0)
            .frame(minHeight: 32)
            .appGlass(in: .capsule, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Refreshes the map")
        .listGamesAction(games) { listsAllGames = true }
    }

    /// A failed first load, a map with nothing on it, or filters that hide everything.
    @ViewBuilder
    private func emptyOrFailedCard(_ frame: EventMapViewModel.MapFrame) -> some View {
        Group {
            switch store.mapState {
            case .failed:
                RetryCard { await store.refreshMap() }
            case .loaded where frame.open.isEmpty:
                EmptyCard(
                    title: "No games nearby yet",
                    message: store.isGuest
                        ? "Check back soon, or create an account to host the first one."
                        : "Be the first to start one. Most games just need one more."
                ) {
                    if store.isGuest {
                        Button("Create an account") { appViewModel.requireAccount(.host) }
                            .pill(.primary)
                    } else {
                        Button("Add a game") { appViewModel.presentGameForm() }
                            .pill(.primary)
                    }
                    Button("Look farther away") { viewModel.lookFartherAway() }
                        .pill(.secondary)
                }
            case .loaded where frame.filtered.isEmpty:
                EmptyCard(title: "No games fit those filters", message: "Try another sport or a wider search.") {
                    Button("Reset filters") { withAnimation(.snappy) { viewModel.resetFilters() } }
                        .pill(.primary)
                }
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: 354)
        .padding(.horizontal, 24)
        .shadow(color: Theme.ink.opacity(0.1), radius: 16, y: 6)
    }

    // MARK: Location

    /// Asks with our own card before the iOS prompt, the first time the map opens (C11).
    /// Once the answer is known, keeps location on while the map is up.
    private func startLocation() {
        #if DEBUG
        // `-screen location` shows the primer even with a mocked location or permission given.
        if UserDefaults.standard.string(forKey: "screen") == "location" { return asksForLocation = true }
        #endif
        guard LocationService.mockCoordinate == nil, locationSession == nil else { return }
        switch CLLocationManager().authorizationStatus {
        case .notDetermined:
            if !declinedLocationPrimer, !isDesignReview { asksForLocation = true }
        default:
            locationSession = CLServiceSession(authorization: .whenInUse)
        }
    }

    /// The iOS prompt follows; the map then centers on you if you're near campus.
    private func allowLocation() {
        locationSession = CLServiceSession(authorization: .whenInUse)
        Task { await viewModel.locate() }
    }

    private func declineLocation() {
        declinedLocationPrimer = true
        UserDefaults.standard.set(true, forKey: Self.declinedPrimerKey)
    }

    /// Design review (`-screen …`) skips the primer, except `-screen location`.
    private var isDesignReview: Bool {
        #if DEBUG
        let screen = UserDefaults.standard.string(forKey: "screen")
        return screen != nil && screen != "location"
        #else
        return false
        #endif
    }

    private var showsLocationBanner: Bool {
        viewModel.isLocationDenied || (declinedLocationPrimer && locationSession == nil && LocationService.mockCoordinate == nil)
    }

    /// Location off: the map stays on campus (SPEC §7.6.1).
    private var locationBanner: some View {
        Button {
            if CLLocationManager().authorizationStatus == .notDetermined {
                asksForLocation = true
            } else {
                openURL(UIApplication.openSettingsURL)
            }
        } label: {
            Label("Turn on location to see how far games are", systemImage: "location.slash")
                .font(.rounded(.footnote, .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12)
                .padding(.vertical, typeSize.isAccessibilitySize ? 6 : 0)
                .frame(minHeight: 32, alignment: .leading)
                .appGlass(in: .capsule, interactive: true)
        }
        .buttonStyle(.plain)
    }

    /// "Show my location" button, centered over the avatar in the bottom bar. Interactive glass
    /// the size of the bar's Filter button, rather than the larger native `MapUserLocationButton`.
    private var locationButton: some View {
        GeometryReader { geo in
            let container = geo.frame(in: .global)
            // Big portrait screens (iPad, iPhone Duo's inner display) raise the avatar past the
            // default gap, so keep clear of its top: its glass adds about 9, plus 10 of space.
            let clearsAvatar = avatarFrame == .zero ? 0 : container.maxY - avatarFrame.minY + 19
            Button {
                viewModel.centerOnUserLocation()
            } label: {
                // Filled while the map follows you, like the native button.
                Image(systemName: viewModel.position.followsUserLocation ? "location.fill" : "location")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Self.mapButtonSize, height: Self.mapButtonSize)
                    .appGlass(in: .circle, interactive: true)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show my location")
            // Its symbol stays this size, so a long press shows it big (A11Y-24).
            .accessibilityShowsLargeContentViewer { Label("Show my location", systemImage: "location") }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { locationButtonWidth = $0 }
            .offset(x: avatarFrame.midX - container.minX - locationButtonWidth / 2)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, max(8, clearsAvatar))
            .opacity(avatarFrame == .zero ? 0 : 1)
            // Not there for VoiceOver either until it shows (A11Y-14).
            .accessibilityHidden(avatarFrame == .zero)
        }
    }

    /// Saved games: guests get the account card instead.
    private func openSaved() {
        if store.isGuest {
            appViewModel.requireAccount(.save)
        } else {
            showsSaved = true
        }
    }

    // MARK: Bars

    /// Bottom bar: Filter · + Add game · avatar. With a vertical bar (iPhone Duo), search, saved
    /// games, recenter, Filter and the avatar move into it (bottom to top: avatar, then Filter +
    /// recenter); only Add game stays in a bottom bar. Floating over the map they would ignore
    /// the bar.
    ///
    /// Every item says which bar it goes in, whatever `barLayout` says, so the system still
    /// places it right while `barLayout` catches up with a fold. On a phone there's no vertical
    /// bar and nothing moves.
    @ToolbarContentBuilder
    private var mapActions: some ToolbarContent {
        if #available(iOS 26, *) {
            glassMapActions
        } else {
            classicMapActions
        }
    }

    /// iOS 18 toolbars use ordinary spacers and draw each control's own surface.
    @ToolbarContentBuilder
    private var classicMapActions: some ToolbarContent {
        if searchInNavigationBar {
            ToolbarItem(placement: .topBarLeading) {
                searchField.frame(width: navigationFieldWidth)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Saved games", systemImage: "bookmark") { openSaved() }
                    .tint(Theme.ink)
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            filterButton.glassCircle()
            Spacer()
            addGameButton
            Spacer()
            profileButton(matchesFilter: false)
        }
    }

    @available(iOS 26, *)
    @ToolbarContentBuilder
    private var glassMapActions: some ToolbarContent {
        if usesVerticalBar {
            // Without a vertical bar the navigation bar is hidden, and the field and Saved float
            // over the map instead.
            ToolbarItem(placement: .topBarTrailing) {
                Button("Search", systemImage: "magnifyingglass") { toggleSearchField() }
                    .tint(showsSearchField ? Theme.accent : Theme.ink)
            }
            .axis(.verticalPreferred)

            ToolbarItem(placement: .topBarTrailing) {
                Button("Saved games", systemImage: "bookmark") { openSaved() }
                    .tint(Theme.ink)
            }
            .axis(.verticalPreferred)

            // One glass group. Plain buttons: the bar draws the glass, so a glass button
            // style (or the native `MapUserLocationButton`) would nest a pill inside it.
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Show my location", systemImage: "location") { viewModel.centerOnUserLocation() }
                    .tint(Theme.ink)
                filterButton
            }
            .axis(.verticalPreferred)
        } else {
            if searchInNavigationBar {
                // Its own glass capsule, so the bar doesn't draw one around it.
                ToolbarItem(placement: .topBarLeading) {
                    searchField.frame(width: navigationFieldWidth)
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Saved games", systemImage: "bookmark") { openSaved() }
                        .tint(Theme.ink)
                }
            }

            // Recenter floats over the map instead (`locationButton`).
            ToolbarItem(placement: .bottomBar) { filterButton }
                .axis(.verticalPreferred)
        }

        // Narrow screens: centered and stretched. Wide screens (e.g. iPhone Duo's inner
        // display): natural size, centered in portrait, held left in landscape.
        if !(isWideLayout && isLandscape) {
            ToolbarSpacer(.flexible, placement: .bottomBar)
                .axis(.horizontalOnly)
        }

        ToolbarItem(placement: .bottomBar) { addGameButton }
            .axis(.horizontalOnly)

        ToolbarSpacer(.flexible, placement: .bottomBar)
            .axis(.horizontalOnly)

        // Splits the avatar into its own glass container, apart from the map actions above.
        if usesVerticalBar {
            ToolbarSpacer(.fixed, placement: .bottomBar)
                .axis(.verticalPreferred)
        }

        // The avatar is a custom view, which the system keeps horizontal by default.
        ToolbarItem(placement: .bottomBar) { profileButton(matchesFilter: !usesVerticalBar) }
            .axis(.verticalPreferred)
    }

    /// Opens Filter games. A sheet rather than a menu, so it's the same from the bottom bar
    /// and from a vertical bar.
    private var filterButton: some View {
        Button("Filter", systemImage: "line.3.horizontal.decrease") { showsFilters = true }
            // Count of active filters, since the icon button has no room for text.
            .badge(viewModel.activeFilterCount)
            .accessibilityLabel(viewModel.filterLabel)
            // Toolbar items don't grow with the text size; a long press shows them big (A11Y-24).
            .accessibilityShowsLargeContentViewer {
                Label(viewModel.filterLabel, systemImage: "line.3.horizontal.decrease")
            }
            .tint(Theme.ink)
    }

    @ViewBuilder
    private var addGameButton: some View {
        // Explicit HStack: toolbars render `Label`s icon-only, but this needs its title.
        let button = Button {
            // Guests hit the account card; `presentGameForm` also gates as a backstop.
            appViewModel.presentGameForm()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("Add game")
            }
            .font(.rounded(.headline, .bold))
            // Toolbar items size to fit, so this fills a narrow bottom bar. Natural size on wide
            // screens, and beside a vertical bar.
            .frame(width: isWideLayout || usesVerticalBar ? nil : addButtonWidth)
        }
        .accessibilityShowsLargeContentViewer { Label("Add game", systemImage: "plus") }
        if #available(iOS 26, *) {
            button
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(Theme.accent)
        } else {
            button.pill(.primary, expands: false)
        }
    }

    /// The avatar opens Me. The bar draws the glass around it, as for Filter. In the bottom bar
    /// the label claims less room than the token it draws, so that glass circle comes out the
    /// Filter button's size. (Hiding the bar's glass to draw our own made the bar put a
    /// backdrop behind every item.)
    private func profileButton(matchesFilter: Bool) -> some View {
        Button {
            if store.isGuest {
                appViewModel.requireAccount(.me)
            } else {
                appViewModel.path.append(.me())
            }
        } label: {
            if matchesFilter {
                MeToken(name: store.profile?.fullName ?? "", size: Self.mapButtonSize - 8, ring: 0)
                    .padding(-Self.avatarOverhang)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { avatarFrame = $0 }
            } else {
                MeToken(name: store.profile?.fullName ?? "", size: 36, ring: 0)
                    .frame(width: 36, height: 36)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { avatarFrame = $0 }
            }
        }
        // A custom toolbar label otherwise gets a horizontal glass capsule, so the avatar
        // sits in a pill. The circle follows the token.
        .modifier(MapProfileSizing())
        .accessibilityLabel(store.isGuest ? "Account" : "Me")
        .accessibilityShowsLargeContentViewer {
            Label(store.isGuest ? "Account" : "Me", systemImage: "person.crop.circle")
        }
        #if DEBUG
        .contextMenu {
            Button(String("Component gallery"), systemImage: "swatchpalette") { appViewModel.path.append(.gallery) }
        }
        #endif
    }

    private var usesVerticalBar: Bool {
        barLayout.isVertical
    }

    /// Shows or hides the search field; hiding it clears the search so no filter lingers unseen.
    private func toggleSearchField() {
        withAnimation(.snappy) { showsSearchField.toggle() }
        if !showsSearchField {
            isSearchFocused = false
            viewModel.searchText = ""
        }
    }

    /// Screen width minus the toolbar margins and the two round side buttons.
    private var addButtonWidth: CGFloat {
        max(140, screenSize.width - 240)
    }

    /// From the view's own size rather than device orientation, which can mislead on foldables.
    private var isLandscape: Bool {
        screenSize.width > screenSize.height
    }

    /// Regular width (unfolded iPhone Duo, iPad) rather than a device check, so it
    /// follows the space the app actually has.
    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }
}

/// Which bar a toolbar item goes in, for `axis(_:)`: `ToolbarItemAxisBehavior` itself only
/// exists from iOS 27.1.
private enum BarAxis {
    case horizontalOnly, verticalPreferred
}

private extension ToolbarContent {
    /// `axisBehavior` is in the iOS 27.1 SDK (Xcode 27). GitHub's runners still have Xcode 26, so
    /// CI builds without it; there's no vertical bar there to place items in.
    @ToolbarContentBuilder
    func axis(_ axis: BarAxis) -> some ToolbarContent {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            axisBehavior(axis == .horizontalOnly ? .horizontalOnly : .verticalPreferred)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

private extension View {
    /// "List games" in VoiceOver's actions, on the chip and the map, while there are games to list.
    func listGamesAction(_ games: [Game], perform: @escaping () -> Void) -> some View {
        accessibilityActions {
            if !games.isEmpty { Button("List games", action: perform) }
        }
    }
}

/// Only newer toolbars need to opt out of their automatic capsule sizing.
private struct MapProfileSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .buttonStyle(.plain)
                .buttonBorderShape(.circle)
                .buttonSizing(.fitted)
        } else {
            content.glassCircle()
        }
    }
}
