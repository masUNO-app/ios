import MapKit
import SwiftUI

/// Figma: "Add game · Choose location" (341:2646) — "Where's the game?". Search, use where you
/// are, or drag the map under the pin; the bar at the bottom says where that is. Pushed inside
/// the game form's sheet, so Back returns to the form.
struct LocationPickerView: View {
    @Binding var place: Place?
    var sport: Activity
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: LocationPickerViewModel
    @FocusState private var isSearchFocused: Bool

    init(place: Binding<Place?>, campus: University?, sport: Activity) {
        _place = place
        self.sport = sport
        _viewModel = State(initialValue: LocationPickerViewModel(current: place.wrappedValue, campus: campus))
    }

    var body: some View {
        map
            .overlay { pin }
            .overlay(alignment: .top) { searchPanel }
            .safeAreaInset(edge: .bottom, spacing: 0) { selectionBar }
            .navigationTitle("Where's the game?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .dialog(isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
                DialogCard(
                    systemImage: "mappin.slash", tone: .tinted(Color(.sportVolleyball)),
                    title: Text("We couldn't place that"),
                    message: Text(verbatim: viewModel.errorMessage ?? ""),
                    confirm: DialogAction("OK")
                )
            }
            .onAppear {
                #if DEBUG
                if UserDefaults.standard.string(forKey: "screen") == "picker" {
                    viewModel.query = "Estadio"
                    isSearchFocused = true
                }
                #endif
            }
    }

    private var map: some View {
        @Bindable var viewModel = viewModel

        return Map(position: $viewModel.position)
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .onMapCameraChange(frequency: .onEnd) { context in
                Task { await viewModel.mapSettled(at: context.region.center) }
            }
            .ignoresSafeArea(edges: .bottom)
    }

    /// Fixed in the middle of the map, point down: the map moves under it.
    private var pin: some View {
        VStack(spacing: 6) {
            Text("Drag the map to adjust")
                .font(.rounded(.footnote, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Theme.card, in: .capsule)
                .shadow(color: Theme.ink.opacity(0.12), radius: 4, y: 2)
            PinMarker(color: sport.color) {
                Text(sport.emoji).font(.system(size: 24))
            }
        }
        // Everything sits above the center, so the point is on it.
        .alignmentGuide(VerticalAlignment.center) { $0[.bottom] }
        .opacity(isSearchFocused || viewModel.showsSuggestions ? 0 : 1)
        .animation(.snappy, value: isSearchFocused)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var searchPanel: some View {
        @Bindable var viewModel = viewModel

        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search for a court, field or address", text: $viewModel.query)
                    .font(.rounded(.body))
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if viewModel.isResolving {
                    ProgressView()
                } else if !viewModel.query.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { viewModel.query = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.muted.opacity(0.6))
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Theme.card, in: .capsule)
            .overlay(Capsule().strokeBorder(isSearchFocused ? Theme.accent : Theme.hairline, lineWidth: isSearchFocused ? 1.5 : 1))
            .shadow(color: Theme.ink.opacity(0.08), radius: 6, y: 2)

            if viewModel.showsSuggestions || isSearchFocused {
                suggestionList
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
        .frame(maxWidth: Theme.columnWidth)
        .animation(.snappy, value: isSearchFocused)
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            row(title: Text("Use my current location"), subtitle: nil, systemImage: "location") {
                Task { await viewModel.useCurrentLocation() }
            }
            ForEach(viewModel.suggestions) { suggestion in
                Theme.separator.frame(height: 1)
                row(title: Text(verbatim: suggestion.title), subtitle: suggestion.subtitle, systemImage: nil) {
                    Task { await viewModel.select(suggestion) }
                }
            }
        }
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card))
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.hairline))
        .shadow(color: Theme.ink.opacity(0.1), radius: 10, y: 4)
    }

    private func row(
        title: Text, subtitle: String?, systemImage: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            isSearchFocused = false
            action()
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let systemImage {
                        Image(systemName: systemImage).font(.subheadline)
                    } else {
                        PlaceIcon(size: 17)
                    }
                }
                .foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
                .background(Theme.accentSoft, in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    title.font(.rounded(.callout, .bold)).foregroundStyle(Theme.ink)
                    if let subtitle, !subtitle.isEmpty {
                        Text(verbatim: subtitle).font(.rounded(.footnote)).foregroundStyle(Theme.muted)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 60)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var selectionBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let selection = viewModel.selection {
                    Text(verbatim: selection.name).font(.rounded(.headline, .bold)).foregroundStyle(Theme.ink)
                    Text(verbatim: selection.address).font(.rounded(.footnote)).foregroundStyle(Theme.muted)
                } else {
                    Text("No spot yet").font(.rounded(.headline, .bold)).foregroundStyle(Theme.ink)
                    Text("Search, or drag the map under the pin.").font(.rounded(.footnote)).foregroundStyle(Theme.muted)
                }
            }
            .lineLimit(1)
            Button("Set location") {
                place = viewModel.selection
                dismiss()
            }
            .disabled(viewModel.selection == nil)
            .pill(.primary)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background, in: .rect(topLeadingRadius: Theme.Radius.sheet, topTrailingRadius: Theme.Radius.sheet))
    }
}
