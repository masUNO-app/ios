import MapKit
import SwiftUI

/// Figma: "Sports event map" and "Sports event map · Popup".
struct EventMapView: View {
    @Environment(EventStore.self) private var store
    @Environment(AppViewModel.self) private var appViewModel
    @State private var viewModel = EventMapViewModel()
    @State private var cameraTracker = MapCameraTracker()
    @State private var screenSize: CGSize = .zero
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        MapReader { proxy in
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
            .overlay {
                PinPopupLayer(
                    event: viewModel.selectedID.flatMap { store.event($0) },
                    proxy: proxy,
                    cameraTracker: cameraTracker,
                    viewModel: viewModel
                )
            }
        }
        .toolbar { bottomActions }
        .toolbarBackgroundVisibility(.hidden, for: .bottomBar)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { screenSize = $0 }
        // Hidden here, but names the back button on pushed screens.
        .navigationTitle("Map")
        .toolbar(.hidden, for: .navigationBar)
        .animation(.spring(duration: 0.4, bounce: 0.22), value: viewModel.selectedID)
        #if DEBUG
        .onAppear { viewModel.openDebugPopup(in: store) }
        #endif
        .onChange(of: store.lastCreatedID) { _, id in
            guard let id, let event = store.event(id) else { return }
            viewModel.focus(on: event)
        }
    }

    private func map(now: Date) -> some View {
        @Bindable var viewModel = viewModel

        // Native selection: tap a pin to select, tap empty map to dismiss the popup.
        return Map(position: $viewModel.position, selection: $viewModel.selectedID) {
            Annotation("You", coordinate: MockData.userLocation, anchor: .bottom) {
                UserPin()
            }
            .annotationTitles(.hidden)

            ForEach(viewModel.mapEvents(in: store)) { event in
                Annotation(event.title, coordinate: event.coordinate, anchor: .bottom) {
                    EventPin(event: event, now: now, isSelected: viewModel.selectedID == event.id)
                }
                .annotationTitles(.hidden)
                .tag(event.id)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        // Keeps the popup pinned to its annotation while the map pans/zooms.
        .onMapCameraChange(frequency: .continuous) { context in
            cameraTracker.camera = context.camera
        }
        .overlay { Theme.mapWarmth.allowsHitTesting(false) }
        .ignoresSafeArea()
    }

    /// Soft cream fade behind the search bar ("Search backdrop" layer).
    private var topBackdrop: some View {
        LinearGradient(
            colors: [Theme.cream.opacity(0.95), Theme.cream.opacity(0)],
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
                    .foregroundStyle(Theme.orange)
                TextField("Search Events", text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                Image(systemName: "mic")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .glassEffect(.regular.interactive(), in: .capsule)

            Menu {
                Button("Your plans", systemImage: "calendar") { appViewModel.path.append(.registered) }
                Button("Hosting", systemImage: "person.2") { appViewModel.path.append(.hosted) }
                if !viewModel.bookmarkedEvents(in: store).isEmpty {
                    Section("Bookmarked") {
                        ForEach(viewModel.bookmarkedEvents(in: store)) { event in
                            Button("\(event.sport.emoji) \(event.title)\(event.isFull ? " · Full" : "")") {
                                // Bring the pin on screen so its popup has somewhere to grow from.
                                viewModel.focus(on: event)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "bookmark")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.orange)
                    .frame(width: 48, height: 48)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .tint(Theme.orange)
        }
        .foregroundStyle(.primary)
    }

    private var nearbyChip: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.actionBlue).frame(width: 7, height: 7)
            Text("·")
            Text("\(viewModel.mapEvents(in: store).count) nearby")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }

    /// Bottom toolbar: filters · Add Event · profile avatar.
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
                Label("Filters", systemImage: "line.3.horizontal.decrease")
            }
            // Count of active sport filters, since the icon button has no room for text.
            .badge(viewModel.sportFilter.count)
            .accessibilityLabel(viewModel.filterLabel)
        }

        // Narrow screens: centered and stretched. Wide screens (e.g. iPhone Duo's inner
        // display): natural size, centered in portrait, left next to Filters in landscape.
        if !(isWideLayout && isLandscape) {
            ToolbarSpacer(.flexible, placement: .bottomBar)
        }

        ToolbarItem(placement: .bottomBar) {
            // Explicit HStack: toolbars render `Label`s icon-only, but this needs its title.
            Button {
                appViewModel.startAdding()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Event")
                }
                .font(.headline)
                .modifier(BottomBarWidth(width: isWideLayout ? nil : addButtonWidth))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.actionBlue)
        }

        ToolbarSpacer(.flexible, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) {
            Menu {
                // TODO: real profile screen.
                Section("Demo") {
                    Button("Simulate a player dropping out", systemImage: "person.fill.xmark") {
                        viewModel.simulateDropOut(in: store)
                    }
                }
            } label: {
                Avatar(name: Person.you, size: 32)
            }
            .accessibilityLabel("Profile")
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

/// Toolbar items size to fit, so this gives Add Event an explicit width to fill a
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

// MARK: - Popup placement

/// Holds the latest camera so only `PinPopupLayer` re-renders while the map moves,
/// rather than the whole map view body.
@Observable
final class MapCameraTracker {
    var camera: MapCamera?
}

/// Positions `EventPopup` next to its pin and scales it out of (and back into) the pin.
private struct PinPopupLayer: View {
    var event: SportsEvent?
    var proxy: MapProxy
    var cameraTracker: MapCameraTracker
    var viewModel: EventMapViewModel

    @State private var popupHeight: CGFloat = 250

    private let margin: CGFloat = 16
    /// Height of a selected `EventPin` (label + bubble, scaled 1.15) plus a small gap.
    private let pinClearance: CGFloat = 104
    /// Keeps the popup clear of the search row and nearby chip.
    private let topLimit: CGFloat = 116

    var body: some View {
        // Read the camera so this view re-lays out whenever the map moves.
        let _ = cameraTracker.camera

        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.clear.allowsHitTesting(false)

                if let event, let tip = pinTip(for: event, in: geo) {
                    let width = min(320, geo.size.width - margin * 2)
                    let minX = min(max(tip.x - width / 2, margin), geo.size.width - margin - width)
                    let opensAbove = tip.y - pinClearance - popupHeight >= topLimit
                    let anchor = UnitPoint(
                        x: min(max((tip.x - minX) / width, 0), 1),
                        y: opensAbove ? 1 : 0
                    )

                    EventPopup(event: event, viewModel: viewModel)
                        .frame(width: width)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { popupHeight = $0 }
                        .transition(.scale(scale: 0.1, anchor: anchor).combined(with: .opacity))
                        // Place by the popup's own edges so no measured height is needed.
                        .alignmentGuide(.leading) { _ in -minX }
                        .alignmentGuide(.top) { d in
                            opensAbove ? d.height - (tip.y - pinClearance) : -(tip.y + 8)
                        }
                        // New identity per event: the old popup shrinks into its pin
                        // while the new one grows out of the tapped pin.
                        .id(event.id)
                }
            }
        }
    }

    /// The pin's tip (the annotation's coordinate) in this layer's local space.
    private func pinTip(for event: SportsEvent, in geo: GeometryProxy) -> CGPoint? {
        guard let point = proxy.convert(event.coordinate, to: .global) else { return nil }
        let frame = geo.frame(in: .global)
        return CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
    }
}
