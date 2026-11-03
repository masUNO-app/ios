import SwiftUI

/// Figma: "Add event" (341:1849), "Error" (341:3054), "Edit event" (341:2703) and
/// "Delete event" (341:2840) — called "game" in the app (SPEC §7.2).
struct GameFormSheet: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: GameFormViewModel
    @State private var confirmsCancel = false
    @State private var picksLocation = false

    init(editing: SportsEvent? = nil) {
        let viewModel = GameFormViewModel(editing: editing)
        #if DEBUG
        // `-screen form-error`: the Figma "Error" frame (no name, a start time that already passed).
        if UserDefaults.standard.string(forKey: "screen") == "form-error" {
            viewModel.time = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: .now) ?? .now
            viewModel.showsErrors = true
        }
        // `-screen add-filled`: a filled-in Add game form (marketing screenshots).
        if UserDefaults.standard.string(forKey: "screen") == "add-filled" {
            viewModel.name = "After-work hoops"
            viewModel.time = Calendar.current.date(bySettingHour: 19, minute: 30, second: 0, of: .now) ?? .now
            viewModel.meetUpSpot = "North court bleachers"
            viewModel.notes = "Casual 3-on-3. Bring a ball and some water!"
        }
        // `-screen picker`: straight into "Where's the game?".
        _picksLocation = State(initialValue: UserDefaults.standard.string(forKey: "screen") == "picker")
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
                            .tint(Theme.ink)
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .sheet(isPresented: $picksLocation) {
            LocationPickerSheet(venue: $viewModel.venue)
        }
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

                FieldBox("Meet-up spot (optional)", error: viewModel.meetUpError) {
                    TextField("e.g. North court bleachers", text: $viewModel.meetUpSpot)
                }

                FieldBox("Players", hint: "Including you") {
                    Stepper(value: $viewModel.players, in: viewModel.minimumPlayers...GameFormViewModel.playerRange.upperBound) {
                        Text(viewModel.playersLabel)
                    }
                }

                // Auto-repost (not in the Figma or SPEC yet — design + backend TBD).
                FieldBox(nil) {
                    Toggle(isOn: $viewModel.autoRepost) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-repost")
                                .foregroundStyle(Theme.ink)
                            Text("If someone drops out, we'll bump your game back to the top of the map.")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                FieldBox("Notes (optional)", error: viewModel.notesError) {
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
            .padding(.top, 12)
            .padding(.bottom, 8)
            // Solid so the fields don't show through the buttons.
            .background(Theme.background)
            .overlay(alignment: .top) { Divider().overlay(Theme.hairline) }
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

                Button("Change") { picksLocation = true }
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
