import MapKit
import SwiftUI

/// Figma: "Sports event map" and "Sports event map · Popup".
struct EventMapView: View {
    @Environment(EventStore.self) private var store
    @Binding var path: [Route]

    @State private var position: MapCameraPosition = .region(MockData.initialRegion)
    @State private var selectedID: SportsEvent.ID?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            map(now: context.date)
        }
        .overlay(alignment: .top) { topBackdrop }
        .overlay(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                searchRow
                nearbyChip
                if let id = selectedID, let event = store.event(id) {
                    EventPopup(event: event, path: $path)
                        .transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { bottomActions }
        .toolbar(.hidden, for: .navigationBar)
        .animation(.snappy, value: selectedID)
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.string(forKey: "screen") == "popup" {
                selectedID = store.mapEvents.first { $0.venue == MockData.Venues.market760 }?.id
            }
        }
        #endif
        .onChange(of: store.lastCreatedID) { _, id in
            guard let id, let event = store.event(id) else { return }
            withAnimation {
                position = .region(MKCoordinateRegion(center: event.coordinate, span: MockData.initialRegion.span))
            }
            selectedID = id
        }
    }

    private func map(now: Date) -> some View {
        // Native selection: tap a pin to select, tap empty map to dismiss the popup.
        Map(position: $position, selection: $selectedID) {
            Annotation("You", coordinate: MockData.userLocation, anchor: .bottom) {
                UserPin()
            }
            .annotationTitles(.hidden)

            ForEach(store.mapEvents) { event in
                Annotation(event.title, coordinate: event.coordinate, anchor: .bottom) {
                    EventPin(event: event, now: now, isSelected: selectedID == event.id)
                }
                .annotationTitles(.hidden)
                .tag(event.id)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
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
        @Bindable var store = store

        return HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                TextField("Search Events", text: $store.searchText)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                Image(systemName: "mic")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .glassEffect(.regular.interactive(), in: .capsule)

            Menu {
                Button("Your plans", systemImage: "calendar") { path.append(.registered) }
                Button("Hosting", systemImage: "person.2") { path.append(.hosted) }
                if !store.bookmarkedEvents.isEmpty {
                    Section("Bookmarked") {
                        ForEach(store.bookmarkedEvents) { event in
                            Button("\(event.sport.emoji) \(event.title)\(event.isFull ? " · Full" : "")") {
                                selectedID = event.id
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "bookmark")
                    .font(.title3.weight(.medium))
                    .frame(width: 48, height: 48)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .tint(.primary)
        }
        .foregroundStyle(.primary)
    }

    private var nearbyChip: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.actionBlue).frame(width: 7, height: 7)
            Text("·")
            Text("\(store.mapEvents.count) nearby")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }

    private var bottomActions: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Menu {
                        Button("All sports") { store.sportFilter.removeAll() }
                        Divider()
                        ForEach(Sport.postable) { sport in
                            Toggle("\(sport.emoji) \(sport.name)", isOn: Binding(
                                get: { store.sportFilter.contains(sport) },
                                set: { on in
                                    if on { store.sportFilter.insert(sport) } else { store.sportFilter.remove(sport) }
                                }
                            ))
                        }
                    } label: {
                        toolLabel(
                            store.sportFilter.isEmpty ? "Filters" : "Filters · \(store.sportFilter.count)",
                            systemImage: "line.3.horizontal.decrease"
                        )
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .tint(.primary)

                    Menu {
                        // TODO: real settings screen (profile, notifications, campus).
                        Section("Demo") {
                            Button("Simulate a player dropping out", systemImage: "person.fill.xmark") {
                                withAnimation { store.simulateDropOut() }
                            }
                        }
                    } label: {
                        toolLabel("Settings", systemImage: "gearshape")
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .tint(.primary)
                }

                Button {
                    store.startAdding()
                } label: {
                    Label("Add Event", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.actionBlue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private func toolLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
            Text(title)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(.capsule)
    }
}

// MARK: - Pins

/// Blue sport pin with a "starts in" label (Figma "Sports event pin").
struct EventPin: View {
    var event: SportsEvent
    var now: Date
    var isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(EventFormat.countdown(to: event.start, from: now))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)

            VStack(spacing: -6) {
                ZStack {
                    Circle().fill(Theme.pinBlue).frame(width: 46, height: 46)
                    Text(event.sport.emoji).font(.system(size: 30))
                }
                Triangle().fill(Theme.pinBlue).frame(width: 18, height: 14)
            }
            .shadow(color: .black.opacity(0.2), radius: 3, y: 3)
        }
        .scaleEffect(isSelected ? 1.15 : 1, anchor: .bottom)
        .animation(.snappy, value: isSelected)
        .contentShape(.rect)
    }
}

/// Red "You" pin (Figma "User location pin").
struct UserPin: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("You")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)

            VStack(spacing: -6) {
                ZStack {
                    Circle().fill(Theme.youRed).frame(width: 46, height: 46)
                    Circle().fill(Color(.systemGray5)).frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color(.systemGray))
                        }
                }
                Triangle().fill(Theme.youRed).frame(width: 18, height: 14)
            }
            .shadow(color: .black.opacity(0.2), radius: 3, y: 3)
        }
        .allowsHitTesting(false)
    }
}
