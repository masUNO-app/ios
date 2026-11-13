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
    @State private var screenSize: CGSize = .zero
    @State private var showsSaved = false
    @State private var showsFilters = false
    /// The map's own size, full screen, to tell how close pins are on screen.
    @State private var mapSize: CGSize = .zero
    /// Keeps When-In-Use location authorized while the map is up.
    @State private var locationSession: CLServiceSession?
    /// "See games near you", before the iOS prompt.
    @State private var asksForLocation = false
    @State private var declinedLocationPrimer = UserDefaults.standard.bool(forKey: EventMapView.declinedPrimerKey)
    /// The avatar's frame in the bottom bar, so the location button sits right above it.
    @State private var avatarFrame: CGRect = .zero
    @State private var locationButtonWidth: CGFloat = 0
    /// Set when the system shows a vertical bar on one side (e.g. iPhone Duo).
    @State private var verticalBarEdge: HorizontalEdge?
    /// With a vertical bar, the search field only shows after tapping Search in the bar.
    @State private var showsSearchField = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    private static let declinedPrimerKey = "declinedLocationPrimer"
    /// The bottom bar's round buttons (Filter).
    private static let mapButtonSize: CGFloat = 48
    /// How far the avatar draws past the room its label claims in the bottom bar.
    private static let avatarOverhang: CGFloat = 5

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            map(now: context.date)
        }
        .overlay { if isSearching { searchScrim } }
        .overlay(alignment: .top) { topBackdrop }
        .overlay { if !isSearching { emptyOrFailedCard } }
        .overlay(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                if !usesVerticalBar || showsSearchField { searchRow }
                if isSearching {
                    searchResults
                } else {
                    // The popup opens right under the search bar, where the chip is.
                    if viewModel.popupID == nil { nearbyChip }
                    if store.isOffline, !store.mapGames().isEmpty { OfflineBanner() }
                    if showsLocationBanner { locationBanner }
                }
            }
            .frame(maxWidth: Theme.columnWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottomLeading) {
            if !usesVerticalBar, !isSearching { locationButton }
        }
        .toolbar {
            // `usesVerticalBar` is only ever true from iOS 27.1.
            #if compiler(>=6.4) // The vertical bar needs Xcode 27; see VerticalBarEdgeReader.
            if #available(iOS 27.1, *), usesVerticalBar { verticalBarActions } else { bottomActions }
            #else
            bottomActions
            #endif
        }
        .background { VerticalBarEdgeReader(edge: $verticalBarEdge) }
        .sheet(isPresented: $showsSaved) {
            SavedGamesSheet { appViewModel.path.append(.game($0)) }
        }
        .sheet(isPresented: Binding(get: { !viewModel.groupedIDs.isEmpty }, set: { if !$0 { viewModel.groupedIDs = [] } })) {
            PinGroupSheet(gameIDs: viewModel.groupedIDs, viewModel: viewModel) { appViewModel.path.append(.game($0)) }
        }
        .sheet(isPresented: $showsFilters) {
            FilterSheet(viewModel: viewModel)
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
        // Tokens under the pins: who's going to each game on the map.
        .task(id: store.mapGames().map(\.id)) {
            await store.loadMissingAttendees(for: store.mapGames().map(\.id))
        }
        .toolbarBackgroundVisibility(.hidden, for: .bottomBar)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { screenSize = $0 }
        // Never shown here, but names the back button on pushed screens.
        .navigationTitle("Map")
        // The vertical bar hosts the navigation bar's items (search, saved games), so
        // it stays visible there; elsewhere those controls float over the map instead.
        .toolbar(usesVerticalBar ? .automatic : .hidden, for: .navigationBar)
        // Without a title the navigation bar collapses, leaving the map full height.
        .toolbar(removing: usesVerticalBar ? .title : nil)
        .toolbarTitleDisplayMode(usesVerticalBar ? .inline : .automatic)
        .animation(.spring(duration: 0.4, bounce: 0.22), value: viewModel.selectedID)
        .animation(.snappy, value: isSearching)
        #if DEBUG
        .onAppear { viewModel.openDebugPopup(in: store) }
        #endif
        // Make room for the popup above a newly selected pin, like a map callout.
        .onChange(of: viewModel.selectedID) { _, id in
            viewModel.selectionChanged(to: id)
            guard let id, let event = store.game(id) else { return }
            viewModel.reveal(event)
        }
        .onChange(of: store.lastCreatedID) { _, id in
            guard let id, let event = store.game(id) else { return }
            viewModel.focus(on: event)
        }
        .onChange(of: viewModel.mapEvents(in: store).map(\.id)) { _, ids in
            if let id = viewModel.selectedID, !ids.contains(id) { viewModel.dropSelection() }
        }
        // A popup and the results list would cover each other.
        .onChange(of: isSearching) { _, searching in
            if searching { viewModel.selectedID = nil }
        }
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
        Annotation(String(localized: "\(group.games.count) games here"), coordinate: group.coordinate, anchor: GroupPin.anchor) {
            GroupPin(games: group.games, isDimmed: viewModel.selectedID != nil)
                .fontDesign(.rounded)
                .onTapGesture { viewModel.groupedIDs = group.games.map(\.id) }
        }
        .annotationTitles(.hidden)
    }

    private func map(now: Date) -> some View {
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

            ForEach(viewModel.pinGroups(in: store, now: now, mapSize: mapSize)) { group in
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
                Annotation(event.title, coordinate: event.coordinate, anchor: viewModel.popupAnchor(for: event)) {
                    EventPopup(event: event, viewModel: viewModel)
                        .frame(width: popupWidth)
                        // Annotation content doesn't inherit the environment.
                        .environment(store)
                        .environment(appViewModel)
                        .environment(\.currentUserID, store.profile?.id)
                        .fontDesign(.rounded)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewModel.popupHeight = $0 }
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
        // Closes the popup once its pin scrolls off screen.
        .onMapCameraChange(frequency: .continuous) { context in
            let selected = viewModel.selectedID.flatMap { store.game($0) }
            viewModel.cameraChanged(to: context.region, selected: selected)
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.cameraSettled(on: context.region)
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { mapSize = $0 }
    }

    /// 16 pt from each edge on a phone, as in the Figma; never wider than the Figma card.
    private var popupWidth: CGFloat {
        min(max(screenSize.width - 32, 280), 370)
    }

    /// Soft fade behind the search bar ("Search backdrop" layer).
    private var topBackdrop: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.background.opacity(0.95), location: 0),
                .init(color: Theme.background.opacity(0.8), location: 0.65),
                .init(color: Theme.background.opacity(0), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        // Shorter under a popup, so the fade doesn't wash out the top of the card.
        .frame(height: viewModel.popupID == nil ? 212 : 150)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Search

    /// Typing, or left with a query in the field: the results list is over the map.
    private var isSearching: Bool {
        isSearchFocused || !viewModel.searchText.isEmpty
    }

    private var searchRow: some View {
        @Bindable var viewModel = viewModel

        return HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(Theme.muted)
                TextField("Search games", text: $viewModel.searchText)
                    .font(.rounded(.body, isSearching ? .bold : .medium))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    // Opened from the bar's Search button, so start typing right away.
                    .onAppear { if usesVerticalBar { isSearchFocused = true } }
                if isSearching {
                    Button("Clear search", systemImage: "xmark.circle.fill") { endSearch() }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.muted.opacity(0.6))
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .glassEffect(.regular.interactive(), in: .capsule)

            // With a vertical bar, Saved games lives in the bar instead.
            if !usesVerticalBar {
                Button("Saved games", systemImage: "bookmark") { showsSaved = true }
                    .font(.title3.weight(.medium))
                    .glassCircle()
            }
        }
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
    private var searchResults: some View {
        let results = viewModel.searchResults(in: store)

        return VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: results.isEmpty ? String(localized: "No games match that search") : viewModel.resultsTitle(for: results))
                .font(.rounded(.footnote, .bold))
                .foregroundStyle(Theme.muted)
                .padding(.leading, 4)

            if !results.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
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
                .frame(maxHeight: min(CGFloat(results.count) * 68, max(screenSize.height * 0.5, 204)))
                .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card))
                .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: 3)
            }
        }
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
    private var nearbyChip: some View {
        let games = viewModel.mapEvents(in: store)
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
            .frame(height: 32)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Refreshes the map")
    }

    /// A failed first load, a map with nothing on it, or filters that hide everything.
    @ViewBuilder
    private var emptyOrFailedCard: some View {
        Group {
            switch store.mapState {
            case .failed:
                RetryCard { await store.refreshMap() }
            case .loaded where store.mapGames().isEmpty:
                EmptyCard(
                    title: "No games nearby yet",
                    message: "Be the first to start one. Most games just need one more."
                ) {
                    Button("Add a game") { appViewModel.presentGameForm() }
                        .pill(.primary)
                    Button("Look farther away") { viewModel.lookFartherAway() }
                        .pill(.secondary)
                }
            case .loaded where viewModel.mapEvents(in: store).isEmpty:
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
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            Label("Turn on location to see how far games are", systemImage: "location.slash")
                .font(.rounded(.footnote, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .glassEffect(.regular.interactive(), in: .capsule)
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
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show my location")
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { locationButtonWidth = $0 }
            .offset(x: avatarFrame.midX - container.minX - locationButtonWidth / 2)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, max(8, clearsAvatar))
            .opacity(avatarFrame == .zero ? 0 : 1)
        }
    }

    // MARK: Bars

    #if compiler(>=6.4) // The vertical bar needs Xcode 27; see VerticalBarEdgeReader.
    /// With a vertical bar (iPhone Duo), search, saved games, recenter, filter and the avatar
    /// move into the bar (bottom to top: avatar, then filter + recenter); only Add game stays in
    /// the horizontal bottom bar. Floating over the map they would ignore the bar.
    @available(iOS 27.1, *)
    @ToolbarContentBuilder
    private var verticalBarActions: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Search", systemImage: "magnifyingglass") { toggleSearchField() }
                .tint(showsSearchField ? Theme.accent : Theme.ink)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button("Saved games", systemImage: "bookmark") { showsSaved = true }
                .tint(Theme.ink)
        }

        ToolbarItem(placement: .bottomBar) { addGameButton }
            .axisBehavior(.horizontalOnly)

        // Alone in the bottom bar it would center, so on wide landscape screens this holds
        // it left, as in `bottomActions`.
        if isWideLayout && isLandscape {
            ToolbarSpacer(.flexible, placement: .bottomBar)
                .axisBehavior(.horizontalOnly)
        }

        // One glass group. Plain buttons: the bar draws the glass, so a glass button
        // style (or the native `MapUserLocationButton`) would nest a pill inside it.
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Show my location", systemImage: "location") { viewModel.centerOnUserLocation() }
                .tint(Theme.ink)
            filterButton
        }
        .axisBehavior(.verticalPreferred)

        // Splits the avatar into its own glass container, apart from the map actions above.
        ToolbarSpacer(.fixed, placement: .bottomBar)

        // The avatar is a custom view, which the system keeps horizontal by default.
        ToolbarItem(placement: .bottomBar) { profileButton(matchesFilter: false) }
            .axisBehavior(.verticalPreferred)
    }
    #endif

    /// Bottom toolbar: filter · + Add game · avatar.
    @ToolbarContentBuilder
    private var bottomActions: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) { filterButton }

        // Narrow screens: centered and stretched. Wide screens (e.g. iPhone Duo's inner
        // display): natural size, centered in portrait, left next to Filter in landscape.
        if !(isWideLayout && isLandscape) {
            ToolbarSpacer(.flexible, placement: .bottomBar)
        }

        ToolbarItem(placement: .bottomBar) { addGameButton }

        ToolbarSpacer(.flexible, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) { profileButton(matchesFilter: true) }
    }

    /// Opens Filter games. A sheet rather than a menu, so it's the same from the bottom bar
    /// and from a vertical bar.
    private var filterButton: some View {
        Button("Filter", systemImage: "line.3.horizontal.decrease") { showsFilters = true }
            // Count of active filters, since the icon button has no room for text.
            .badge(viewModel.activeFilterCount)
            .accessibilityLabel(viewModel.filterLabel)
            .tint(Theme.ink)
    }

    private var addGameButton: some View {
        // Explicit HStack: toolbars render `Label`s icon-only, but this needs its title.
        Button {
            appViewModel.presentGameForm()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("Add game")
            }
            .font(.rounded(.headline, .bold))
            .modifier(BottomBarWidth(width: isWideLayout ? nil : addButtonWidth))
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(Theme.accent)
    }

    /// The avatar opens Me. The bar draws the glass around it, as for Filter. In the bottom bar
    /// the label claims less room than the token it draws, so that glass circle comes out the
    /// Filter button's size. (Hiding the bar's glass to draw our own made the bar put a
    /// backdrop behind every item.)
    private func profileButton(matchesFilter: Bool) -> some View {
        Button {
            appViewModel.path.append(.me())
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
        .buttonStyle(.plain)
        .buttonBorderShape(.circle)
        .buttonSizing(.fitted)
        .accessibilityLabel("Me")
        #if DEBUG
        .contextMenu {
            Button(String("Component gallery"), systemImage: "swatchpalette") { appViewModel.path.append(.gallery) }
        }
        #endif
    }

    private var usesVerticalBar: Bool {
        verticalBarEdge != nil
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

/// Publishes `toolbarVerticalEdge`, which is only available from iOS 27.1, to a binding.
/// `toolbarVerticalEdge` is in the iOS 27.1 SDK (Xcode 27). GitHub's runners still have Xcode 26,
/// so CI builds without it and the toolbar never switches to the vertical bar there.
struct VerticalBarEdgeReader: View {
    @Binding var edge: HorizontalEdge?

    var body: some View {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            VerticalBarEdgeReader27(edge: $edge)
        } else {
            Color.clear
        }
        #else
        Color.clear
        #endif
    }
}

#if compiler(>=6.4) // `toolbarVerticalEdge` needs Xcode 27; see VerticalBarEdgeReader.
@available(iOS 27.1, *)
private struct VerticalBarEdgeReader27: View {
    @Binding var edge: HorizontalEdge?
    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    var body: some View {
        Color.clear
            .onChange(of: verticalEdge, initial: true) { _, newValue in edge = newValue }
    }
}
#endif

/// Toolbar items size to fit, so this gives Add game an explicit width to fill a
/// horizontal bottom bar. When the system moves the toolbar into a vertical bar on
/// one side (e.g. iPhone Duo half-open), the button keeps its natural size instead.
/// A `nil` width also means natural size.
private struct BottomBarWidth: ViewModifier {
    var width: CGFloat?

    func body(content: Content) -> some View {
        #if compiler(>=6.4) // `toolbarVerticalEdge` needs Xcode 27; see VerticalBarEdgeReader.
        if #available(iOS 27.1, *) {
            content.modifier(VerticalBarAwareWidth(width: width))
        } else {
            content.frame(width: width)
        }
        #else
        content.frame(width: width)
        #endif
    }
}

#if compiler(>=6.4) // `toolbarVerticalEdge` needs Xcode 27; see VerticalBarEdgeReader.
@available(iOS 27.1, *)
private struct VerticalBarAwareWidth: ViewModifier {
    var width: CGFloat?
    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    func body(content: Content) -> some View {
        content.frame(width: verticalEdge == nil ? width : nil)
    }
}
#endif
