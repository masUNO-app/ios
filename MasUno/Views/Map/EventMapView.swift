import CoreLocation
import MapKit
import SwiftUI

/// Figma: "Sports event map" (341:1979) and "Popup" (341:2046). The popup is part of the
/// selected pin's annotation, so MapKit moves it with the pin like any map callout.
struct EventMapView: View {
    @Environment(EventStore.self) private var store
    @Environment(AppViewModel.self) private var appViewModel
    @State private var viewModel = EventMapViewModel()
    @State private var screenSize: CGSize = .zero
    @State private var showsSaved = false
    /// Keeps When-In-Use location authorized while the map is up (asks the first time).
    @State private var locationSession: CLServiceSession?
    /// The avatar's frame in the bottom bar, so the location button sits right above it.
    @State private var avatarFrame: CGRect = .zero
    @State private var locationButtonWidth: CGFloat = 0
    @Namespace private var mapScope
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            map(now: context.date)
        }
        .overlay(alignment: .top) { topBackdrop }
        .overlay(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                searchRow
                nearbyChip
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottomLeading) { locationButton }
        .mapScope(mapScope)
        .toolbar { bottomActions }
        .sheet(isPresented: $showsSaved) {
            SavedGamesSheet { appViewModel.path.append(.game($0)) }
        }
        .onAppear {
            if locationSession == nil, LocationService.mockCoordinate == nil {
                locationSession = CLServiceSession(authorization: .whenInUse)
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .bottomBar)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { screenSize = $0 }
        // Hidden here, but names the back button on pushed screens.
        .navigationTitle("Map")
        .toolbar(.hidden, for: .navigationBar)
        .animation(.spring(duration: 0.4, bounce: 0.22), value: viewModel.selectedID)
        #if DEBUG
        .onAppear { viewModel.openDebugPopup(in: store) }
        #endif
        // Make room for the popup above a newly selected pin, like a map callout.
        .onChange(of: viewModel.selectedID) { _, id in
            guard let id, let event = store.event(id) else { return }
            viewModel.reveal(event)
        }
        .onChange(of: store.lastCreatedID) { _, id in
            guard let id, let event = store.event(id) else { return }
            viewModel.focus(on: event)
        }
    }

    private func map(now: Date) -> some View {
        @Bindable var viewModel = viewModel

        // Native selection: tap a pin to select, tap empty map to dismiss the popup.
        return Map(position: $viewModel.position, selection: $viewModel.selectedID, scope: mapScope) {
            if let mock = LocationService.mockCoordinate {
                Annotation("You", coordinate: mock, anchor: .center) {
                    UserPin(name: store.profile.fullName)
                }
                .annotationTitles(.hidden)
            } else {
                UserAnnotation {
                    UserPin(name: store.profile.fullName)
                }
            }

            ForEach(viewModel.mapEvents(in: store)) { event in
                let isSelected = viewModel.selectedID == event.id
                // Anchored at the pin's tip, so the popup above it moves with the map.
                Annotation(event.title, coordinate: event.coordinate, anchor: .bottom) {
                    VStack(spacing: 10) {
                        if isSelected {
                            EventPopup(event: event, viewModel: viewModel)
                                .frame(width: 320)
                                // Annotation content doesn't inherit the environment.
                                .environment(store)
                                .environment(appViewModel)
                                .transition(.scale(scale: 0.1, anchor: .bottom).combined(with: .opacity))
                        }
                        EventPin(
                            event: event, now: now,
                            isSelected: isSelected,
                            isDimmed: viewModel.selectedID != nil && !isSelected
                        )
                    }
                    .zIndex(isSelected ? 1 : 0)
                }
                .annotationTitles(.hidden)
                .tag(event.id)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        // Closes the popup once its pin scrolls off screen.
        .onMapCameraChange(frequency: .continuous) { context in
            let selected = viewModel.selectedID.flatMap { store.event($0) }
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
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .glassEffect(.regular.interactive(), in: .capsule)

            Button("Saved games", systemImage: "bookmark") { showsSaved = true }
                .labelStyle(.iconOnly)
                .font(.title3.weight(.medium))
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(Theme.ink)
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
            let containerMinX = geo.frame(in: .global).minX
            userLocationButton
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(Theme.ink)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { locationButtonWidth = $0 }
                .offset(x: avatarFrame.midX - containerMinX - locationButtonWidth / 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 8)
                .opacity(avatarFrame == .zero ? 0 : 1)
        }
    }

    private var nearbyChip: some View {
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

    /// Bottom toolbar: sport filter · + Add game · avatar.
    @ToolbarContentBuilder
    private var bottomActions: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Menu {
                Button("All sports") { viewModel.clearSportFilter() }
                Divider()
                ForEach(Sport.postable) { sport in
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

        // Narrow screens: centered and stretched. Wide screens (e.g. iPhone Duo's inner
        // display): natural size, centered in portrait, left next to Filters in landscape.
        if !(isWideLayout && isLandscape) {
            ToolbarSpacer(.flexible, placement: .bottomBar)
        }

        ToolbarItem(placement: .bottomBar) {
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

        ToolbarSpacer(.flexible, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) {
            Button {
                appViewModel.path.append(.me())
            } label: {
                Avatar(name: store.profile.fullName, size: 32)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { avatarFrame = $0 }
            }
            .accessibilityLabel("Me")
            #if DEBUG
            .contextMenu {
                Button("Component gallery", systemImage: "swatchpalette") { appViewModel.path.append(.gallery) }
            }
            #endif
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
