import SwiftUI

/// Figma "Filter games": sports, when, how far and "Starting soon". The filters apply as you
/// change them, so the button can say how many games are left.
struct FilterSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: EventMapViewModel

    var body: some View {
        let count = viewModel.mapEvents(in: store).count

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetHeader(title: Text("Filter games"), subtitle: Text("Show me games that fit.")) { dismiss() }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sports")
                        .font(.rounded(.footnote, .bold))
                        .foregroundStyle(Theme.ink)
                    FlowLayout(spacing: 8) {
                        ForEach(store.postableActivities) { sport in
                            SportToggle(sport: sport, isOn: viewModel.sportFilter.contains(sport)) {
                                viewModel.toggleSport(sport)
                            }
                        }
                    }
                }

                Menu {
                    Picker("When", selection: $viewModel.whenFilter) {
                        ForEach(EventMapViewModel.WhenFilter.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    FieldBox("When", showsChevron: true) { Text(viewModel.whenFilter.label) }
                }

                Menu {
                    Picker("How far", selection: $viewModel.distanceFilter) {
                        ForEach(EventMapViewModel.DistanceFilter.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    FieldBox("How far", showsChevron: true) { Text(viewModel.distanceFilter.label) }
                }

                Toggle(isOn: $viewModel.startingSoonOnly) {
                    HStack(spacing: 12) {
                        IconTile(systemImage: "alarm", color: Color(.person1).opacity(0.45))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Starting soon")
                                .font(.rounded(.body))
                                .foregroundStyle(Theme.ink)
                            Text("Only games in the next hour")
                                .font(.rounded(.footnote))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                .tint(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .cardSurface(radius: Theme.Radius.field)

                VStack(spacing: 10) {
                    Button(count == 1 ? "Show 1 game" : "Show \(count) games") { dismiss() }
                        .pill(.primary)
                    Button("Reset") { withAnimation(.snappy) { viewModel.resetFilters() } }
                        .pill(.quiet)
                        .disabled(viewModel.activeFilterCount == 0)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 22)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheetChrome(detents: [.height(560), .large])
    }
}
