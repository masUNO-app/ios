import CoreLocation
import MapKit
import SwiftUI

/// Figma: "Sports event map" (341:1979) and "Popup" (341:2046). The popup is part of the
/// selected pin's annotation, so MapKit moves it with the pin like any map callout.
struct EventMapView: View {
    @Environment(GameStore.self) private var store
    @Environment(AppViewModel.self) private var appViewModel
    @State private var viewModel = EventMapViewModel()
    @State private var screenSize: CGSize = .zero
    @State private var showsSaved = false
    /// Keeps When-In-Use location authorized while the map is up (asks the first time).
    @State private var locationSession: CLServiceSession?
    /// The avatar's frame in the bottom bar, so the location button sits right above it.
    @State private var avatarFrame: CGRect = .zero
    @State private var locationButtonWidth: CGFloat = 0
    /// Set when the system shows a vertical bar on one side (e.g. iPhone Duo).
    @State private var verticalBarEdge: HorizontalEdge?
    /// With a vertical bar, the search field only shows after tapping Search in the bar.
    @State private var showsSearchField = false
    @FocusState private var isSearchFocused: Bool
    @Namespace private var mapScope
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            map(now: context.date)
        }
        .overlay(alignment: .top) { topBackdrop }
        .overlay(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                if !usesVerticalBar || showsSearchField { searchRow }
                nearbyChip
                if store.isOffline, !store.mapGames().isEmpty { OfflineBanner() }
                if viewModel.isLocationDenied { locationBanner }
                emptyOrFailedCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottomLeading) {
            if !usesVerticalBar { locationButton }
        }
        .mapScope(mapScope)
        .toolbar {
            // `usesVerticalBar` is only ever true from iOS 27.1.
            if #available(iOS 27.1, *), usesVerticalBar { verticalBarActions } else { bottomActions }
        }
        .background { VerticalBarEdgeReader(edge: $verticalBarEdge) }
        .sheet(isPresented: $showsSaved) {
            SavedGamesSheet { appViewModel.path.append(.game($0)) }
        }
        .onAppear {
            #if DEBUG
            if UserDefaults.standard.string(forKey: "screen") == "saved" { showsSaved = true }
            #endif
            if locationSession == nil, LocationService.mockCoordinate == nil {
                locationSession = CLServiceSession(authorization: .whenInUse)
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await viewModel.locate() }
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
        #if DEBUG
        .onAppear { viewModel.openDebugPopup() }
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
    }

    private func map(now: Date) -> some View {
        @Bindable var viewModel = viewModel

        // Native selection: tap a pin to select, tap empty map to dismiss the popup.
        return Map(position: $viewModel.position, selection: $viewModel.selectedID, scope: mapScope) {
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

            ForEach(viewModel.pinOrder(in: store, now: now)) { event in
                let isSelected = viewModel.selectedID == event.id
                Annotation(event.title, coordinate: event.coordinate, anchor: .bottom) {
                    EventPin(
                        event: event, now: now,
                        isSelected: isSelected,
                        isDimmed: viewModel.selectedID != nil && !isSelected
                    )
                }
                .annotationTitles(.hidden)
                .tag(event.id)
            }

            // The popup is its own annotation on the pin's coordinate, so MapKit moves it with
            // the pin, and the pin's annotation never changes size (which made MapKit swap and
            // cross-fade it). Added last so it draws over the pins.
            if let id = viewModel.popupID, let event = store.game(id) {
                Annotation(event.title, coordinate: event.coordinate, anchor: viewModel.popupAnchor(for: event)) {
                    EventPopup(event: event, viewModel: viewModel)
                        .frame(width: 320)
                        // Annotation content doesn't inherit the environment.
                        .environment(store)
                        .environment(appViewModel)
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
        .ignoresSafeArea()
    }

    /// Soft fade behind the search bar ("Search backdrop" layer).
    private var topBackdrop: some View {
        LinearGradient(
            colors: [Theme.background.opacity(0.95), Theme.background.opacity(0)],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 212)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var searchRow: some View {
        @Bindable var viewModel = viewModel

        return HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(Theme.muted)
                TextField("Search games", text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    // Opened from the bar's Search button, so start typing right away.
                    .onAppear { if usesVerticalBar { isSearchFocused = true } }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .glassEffect(.regular.interactive(), in: .capsule)

            // With a vertical bar, Saved games lives in the bar instead.
            if !usesVerticalBar {
                Button("Saved games", systemImage: "bookmark") { showsSaved = true }
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.medium))
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(Theme.ink)
            }
        }
        .foregroundStyle(Theme.ink)
    }

    /// Native `MapUserLocationButton` for the real location; a glass button with the same
    /// look while the location is mocked (the native one can only follow real GPS).
    @ViewBuilder
    private var userLocationButton: some View {
        if LocationService.mockCoordinate != nil {
            Button("Show my location", systemImage: "location.fill") { viewModel.centerOnMockLocation() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
        } else {
            MapUserLocationButton(scope: mapScope)
        }
    }

    /// "Show my location" button, centered over the avatar in the bottom bar.
    private var locationButton: some View {
        GeometryReader { geo in
            let container = geo.frame(in: .global)
            // Big portrait screens (iPad, iPhone Duo's inner display) raise the avatar past the
            // default gap, so keep clear of its top: its glass adds about 6, plus 10 of space.
            let clearsAvatar = avatarFrame == .zero ? 0 : container.maxY - avatarFrame.minY + 16
            userLocationButton
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(Theme.ink)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { locationButtonWidth = $0 }
                .offset(x: avatarFrame.midX - container.minX - locationButtonWidth / 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, max(8, clearsAvatar))
                .opacity(avatarFrame == .zero ? 0 : 1)
        }
    }

    /// Tapping refreshes: a map can't pull to refresh, because dragging pans it.
    private var nearbyChip: some View {
        Button {
            Task { await store.refreshMap() }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(Theme.ink).frame(width: 6, height: 6)
                Text("\(viewModel.mapEvents(in: store).count) games nearby")
            }
            .font(.footnote)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Refreshes the map")
    }

    /// A failed first load, or a map with nothing on it. Not while searching or filtering:
    /// the chip already says "0 games nearby" there.
    @ViewBuilder
    private var emptyOrFailedCard: some View {
        switch store.mapState {
        case .failed:
            RetryCard { await store.refreshMap() }
        case .loaded where store.mapGames().isEmpty:
            VStack(spacing: 12) {
                Text("No open games right now. Start one?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                Button("Add game") { appViewModel.presentGameForm() }
                    .buttonStyle(.glassProminent)
                    .fontWeight(.semibold)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .cardSurface()
        default:
            EmptyView()
        }
    }

    /// Location off: the map stays on campus (SPEC §7.6.1).
    private var locationBanner: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        } label: {
            Label("Turn on location to see how far games are", systemImage: "location.slash")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
    }

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
            Button("Show my location", systemImage: "location.fill") { viewModel.centerOnUserLocation() }
                .tint(Theme.ink)
            filterMenu
        }
        .axisBehavior(.verticalPreferred)

        // Splits the avatar into its own glass container, apart from the map actions above.
        ToolbarSpacer(.fixed, placement: .bottomBar)

        // The avatar is a custom view, which the system keeps horizontal by default.
        ToolbarItem(placement: .bottomBar) { profileButton }
            .axisBehavior(.verticalPreferred)
    }

    /// Bottom toolbar: sport filter · + Add game · avatar.
    @ToolbarContentBuilder
    private var bottomActions: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) { filterMenu }

        // Narrow screens: centered and stretched. Wide screens (e.g. iPhone Duo's inner
        // display): natural size, centered in portrait, left next to Filters in landscape.
        if !(isWideLayout && isLandscape) {
            ToolbarSpacer(.flexible, placement: .bottomBar)
        }

        ToolbarItem(placement: .bottomBar) { addGameButton }

        ToolbarSpacer(.flexible, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) { profileButton }
    }

    private var filterMenu: some View {
        Menu {
            Button("All sports") { viewModel.clearSportFilter() }
            Divider()
            ForEach(store.postableActivities) { sport in
                Toggle("\(sport.emoji) \(sport.name)", isOn: Binding(
                    get: { viewModel.sportFilter.contains(sport) },
                    set: { _ in viewModel.toggleSport(sport) }
                ))
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease")
        }
        // Count of active sport filters, since the icon button has no room for text.
        .badge(viewModel.sportFilter.count)
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
            .font(.headline)
            .modifier(BottomBarWidth(width: isWideLayout ? nil : addButtonWidth))
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(Theme.accent)
    }

    private var profileButton: some View {
        Button {
            appViewModel.path.append(.me())
        } label: {
            Avatar(name: store.profile?.fullName ?? "", size: 32)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { avatarFrame = $0 }
        }
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
        if !showsSearchField { viewModel.searchText = "" }
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
private struct VerticalBarEdgeReader: View {
    @Binding var edge: HorizontalEdge?

    var body: some View {
        if #available(iOS 27.1, *) {
            VerticalBarEdgeReader27(edge: $edge)
        } else {
            Color.clear
        }
    }
}

@available(iOS 27.1, *)
private struct VerticalBarEdgeReader27: View {
    @Binding var edge: HorizontalEdge?
    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    var body: some View {
        Color.clear
            .onChange(of: verticalEdge, initial: true) { _, newValue in edge = newValue }
    }
}

/// Toolbar items size to fit, so this gives Add game an explicit width to fill a
/// horizontal bottom bar. When the system moves the toolbar into a vertical bar on
/// one side (e.g. iPhone Duo half-open), the button keeps its natural size instead.
/// A `nil` width also means natural size.
private struct BottomBarWidth: ViewModifier {
    var width: CGFloat?

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.modifier(VerticalBarAwareWidth(width: width))
        } else {
            content.frame(width: width)
        }
    }
}

@available(iOS 27.1, *)
private struct VerticalBarAwareWidth: ViewModifier {
    var width: CGFloat?
    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    func body(content: Content) -> some View {
        content.frame(width: verticalEdge == nil ? width : nil)
    }
}
