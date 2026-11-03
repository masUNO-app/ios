import MapKit
import SwiftUI

/// Figma: "Add event · Choose location" (341:2646) — "Where's the game?".
struct LocationPickerSheet: View {
    @Binding var venue: Venue
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: LocationPickerViewModel
    @FocusState private var isSearchFocused: Bool

    init(venue: Binding<Venue>) {
        _venue = venue
        _viewModel = State(initialValue: LocationPickerViewModel(current: venue.wrappedValue))
    }

    var body: some View {
        NavigationStack {
            map
                .overlay(alignment: .top) { searchPanel }
                .safeAreaInset(edge: .bottom) { selectionBar }
                .navigationTitle("Where's the game?")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                            .tint(Theme.ink)
                    }
                }
                .alert(
                    Text(viewModel.errorMessage ?? ""),
                    isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
                ) {
                    Button("OK", role: .cancel) {}
                }
        }
        .presentationBackground(Theme.background)
        .onAppear {
            isSearchFocused = true
            #if DEBUG
            if UserDefaults.standard.string(forKey: "screen") == "picker" { viewModel.query = "Estadio" }
            #endif
        }
    }

    private var map: some View {
        @Bindable var viewModel = viewModel

        return Map(position: $viewModel.position) {
            Annotation(viewModel.selection.name, coordinate: viewModel.selection.coordinate, anchor: .bottom) {
                VStack(spacing: -6) {
                    Circle().fill(Theme.pin).frame(width: 36, height: 36)
                        .overlay(Image(systemName: "mappin").foregroundStyle(Theme.onAccent))
                    Triangle().fill(Theme.pin).frame(width: 14, height: 10)
                }
                .shadow(color: Theme.shadow, radius: 3, y: 2)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea(edges: .bottom)
    }

    private var searchPanel: some View {
        @Bindable var viewModel = viewModel

        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search for a court, field or address", text: $viewModel.query)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if viewModel.isResolving {
                    ProgressView()
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Theme.card, in: .capsule)
            .overlay(Capsule().strokeBorder(isSearchFocused ? Theme.accent : Theme.hairline, lineWidth: isSearchFocused ? 1.5 : 1))

            if viewModel.showsSuggestions || isSearchFocused {
                suggestionList
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            row(title: Text("Use my current location"), subtitle: nil, systemImage: "location") {
                Task { await viewModel.useCurrentLocation() }
            }
            ForEach(viewModel.suggestions) { suggestion in
                Divider().overlay(Theme.hairline).padding(.leading, 56)
                row(title: Text(verbatim: suggestion.title), subtitle: suggestion.subtitle, systemImage: "mappin.and.ellipse") {
                    Task { await viewModel.select(suggestion) }
                }
            }
        }
        .cardSurface()
    }

    private func row(
        title: Text, subtitle: String?, systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            isSearchFocused = false
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(Theme.accentSoft, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    title.font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    if let subtitle, !subtitle.isEmpty {
                        Text(verbatim: subtitle).font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var selectionBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.selection.name).font(.headline).foregroundStyle(Theme.ink)
                Text(verbatim: viewModel.selection.fullAddress).font(.footnote).foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            Button("Set location") {
                venue = viewModel.selection
                dismiss()
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .buttonSizing(.flexible)
            .fontWeight(.semibold)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(Theme.background, in: .rect(topLeadingRadius: Theme.Radius.dialog, topTrailingRadius: Theme.Radius.dialog))
    }
}
