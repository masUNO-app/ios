import SwiftUI

/// Figma: "Sports event map · Add event". Also used for "Edit event" on hosted cards.
struct AddEventSheet: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AddEventViewModel

    init(editing: SportsEvent? = nil) {
        _viewModel = State(initialValue: AddEventViewModel(editing: editing))
    }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle(viewModel.title)
                .navigationSubtitle(viewModel.subtitle)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
    }

    private var form: some View {
        @Bindable var viewModel = viewModel

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sport")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                sportPicker

                FieldBox("Event name", hint: "Give it a real name, not just the sport") {
                    TextField("After-work hoops", text: $viewModel.name)
                        .textInputAutocapitalization(.sentences)
                }

                HStack(spacing: 10) {
                    Menu {
                        Picker("Date", selection: $viewModel.day) {
                            ForEach(viewModel.dayOptions, id: \.self) { option in
                                Text(viewModel.dayLabel(option)).tag(option)
                            }
                        }
                    } label: {
                        FieldBox("Date") { Text(viewModel.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) }
                    }

                    FieldBox("Start time") {
                        DatePicker("Start time", selection: $viewModel.time, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .fixedSize()
                    }

                    Menu {
                        Picker("Duration", selection: $viewModel.duration) {
                            ForEach(AddEventViewModel.durations, id: \.self) { Text(EventFormat.duration($0)).tag($0) }
                        }
                    } label: {
                        FieldBox("Duration") { Text(EventFormat.duration(viewModel.duration)) }
                    }
                }

                Menu {
                    Picker("Location", selection: $viewModel.venue) {
                        ForEach(MockData.Venues.postable) { venue in
                            Text(venue.name).tag(venue)
                        }
                    }
                } label: {
                    FieldBox(nil) {
                        HStack(spacing: 14) {
                            Image(systemName: "mappin.circle")
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Location").font(.caption).foregroundStyle(Theme.muted)
                                Text(viewModel.venue.name)
                                Text(verbatim: viewModel.venue.fullAddress).font(.footnote).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text("Change")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .frame(height: Theme.compactButtonHeight)
                                .background(Theme.accentSoft, in: .capsule)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Menu {
                        Picker("Players", selection: $viewModel.players) {
                            ForEach(AddEventViewModel.playerCounts, id: \.self) { Text("\($0) players").tag($0) }
                        }
                    } label: {
                        FieldBox("Players", hint: "Including you", showsChevron: true) { Text("\(viewModel.players) players") }
                    }

                    Menu {
                        Picker("Skill level", selection: $viewModel.skill) {
                            ForEach(SkillLevel.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        FieldBox("Skill level", showsChevron: true) { Text(viewModel.skill.rawValue) }
                    }
                    .frame(maxWidth: 160)
                }

                FieldBox("Notes (optional)") {
                    TextField("Casual 3-on-3. Bring a ball and some water!", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(1...3)
                }

                Label("Public game · visible to players nearby", systemImage: "globe")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .tint(Theme.ink)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(viewModel.saveButtonTitle, action: save)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .buttonSizing(.flexible)
                .disabled(!viewModel.isNameValid)
                .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 8)
        }
        .background(Theme.background)
    }

    private var sportPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.sportOptions) { option in
                    let isSelected = option == viewModel.sport
                    Button {
                        viewModel.sport = option
                    } label: {
                        HStack(spacing: 6) {
                            Text(option.emoji)
                            Text(option.name)
                        }
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background(isSelected ? Theme.accentSoft : Theme.card, in: .capsule)
                        .overlay(Capsule().strokeBorder(isSelected ? Theme.accent : Theme.hairline, lineWidth: isSelected ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(1)
        }
    }

    private func save() {
        viewModel.save(in: store)
        dismiss()
    }
}
