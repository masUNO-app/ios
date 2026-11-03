import SwiftUI

/// Figma: "Add event" (341:1849), "Error" (341:3054), "Edit event" (341:2703) and
/// "Delete event" (341:2840) — called "game" in the app (SPEC §7.2).
struct GameFormSheet: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: GameFormViewModel
    @State private var confirmsCancel = false

    init(editing: SportsEvent? = nil) {
        let viewModel = GameFormViewModel(editing: editing)
        #if DEBUG
        // `-screen form-error`: the Figma "Error" frame (no name, a start time that already passed).
        if UserDefaults.standard.string(forKey: "screen") == "form-error" {
            viewModel.time = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: .now) ?? .now
            viewModel.showsErrors = true
        }
        #endif
        _viewModel = State(initialValue: viewModel)
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
        .alert(
            Text("Cancel \(viewModel.editing?.title ?? "")?"),
            isPresented: $confirmsCancel
        ) {
            Button("Cancel game", role: .destructive) {
                viewModel.cancelGame(in: store)
                dismiss()
            }
            Button("Keep game", role: .cancel) {}
        } message: {
            let going = (viewModel.editing?.attendees.count ?? 1) - 1
            Text("We'll let the \(going) people who are going know. This can't be undone.")
        }
    }

    private var form: some View {
        @Bindable var viewModel = viewModel

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Menu {
                    Picker("Sport", selection: $viewModel.sport) {
                        ForEach(Sport.postable) { sport in
                            Text("\(sport.emoji) \(sport.name)").tag(sport)
                        }
                    }
                } label: {
                    FieldBox("Sport", showsChevron: true) {
                        Text("\(viewModel.sport.emoji) \(viewModel.sport.name)")
                    }
                }

                FieldBox("Game name", hint: "Give it a real name, not just the sport", error: viewModel.nameError) {
                    TextField("e.g. After-work hoops", text: $viewModel.name)
                        .textInputAutocapitalization(.sentences)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Menu {
                            Picker("Date", selection: $viewModel.day) {
                                ForEach(viewModel.dayOptions, id: \.self) { option in
                                    Text(viewModel.dayLabel(option)).tag(option)
                                }
                            }
                        } label: {
                            FieldBox("Date") { Text(viewModel.dayLabel(viewModel.day)) }
                        }

                        FieldBox("Start time", isInvalid: viewModel.timeError != nil) {
                            DatePicker("Start time", selection: $viewModel.time, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .fixedSize()
                        }

                        Menu {
                            Picker("Duration", selection: $viewModel.duration) {
                                ForEach(GameFormViewModel.durations, id: \.self) { Text(EventFormat.duration($0)).tag($0) }
                            }
                        } label: {
                            FieldBox("Duration") { Text(EventFormat.duration(viewModel.duration)) }
                        }
                    }
                    if let timeError = viewModel.timeError {
                        Text(timeError)
                            .font(.caption)
                            .foregroundStyle(Theme.error)
                            .padding(.leading, 4)
                    }
                }

                locationCard

                FieldBox("Meet-up spot (optional)") {
                    TextField("e.g. North court bleachers", text: $viewModel.meetUpSpot)
                }

                FieldBox("Players", hint: "Including you") {
                    Stepper(value: $viewModel.players, in: viewModel.minimumPlayers...GameFormViewModel.playerRange.upperBound) {
                        Text(viewModel.playersLabel)
                    }
                }

                FieldBox("Notes (optional)") {
                    TextField("Casual 3-on-3. Bring a ball and some water!", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                if let formError = viewModel.formError {
                    Label(formError, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.error)
                }
            }
            .tint(Theme.accent)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Button(viewModel.saveButtonTitle, action: save)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .buttonSizing(.flexible)
                    .fontWeight(.semibold)
                if viewModel.isEditing {
                    Button("Cancel game", role: .destructive) { confirmsCancel = true }
                        .fontWeight(.semibold)
                        .tint(Theme.destructive)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 8)
        }
        .background(Theme.background)
    }

    /// Location card: map thumbnail, place, address and **Change**.
    private var locationCard: some View {
        @Bindable var viewModel = viewModel

        return FieldBox(nil) {
            HStack(spacing: 14) {
                MapThumbnail(coordinate: viewModel.venue.coordinate)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Location").font(.caption).foregroundStyle(Theme.muted)
                    Text(viewModel.venue.name).fontWeight(.semibold)
                    Text(verbatim: viewModel.venue.fullAddress)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .lineLimit(2)

                Spacer(minLength: 4)

                // TODO(E8): opens "Where's the game?".
                Menu("Change") {
                    Picker("Location", selection: $viewModel.venue) {
                        ForEach(MockData.Venues.all) { Text($0.name).tag($0) }
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accentSoft)
                .foregroundStyle(Theme.ink)
            }
        }
    }

    private func save() {
        if viewModel.save(in: store) { dismiss() }
    }
}
