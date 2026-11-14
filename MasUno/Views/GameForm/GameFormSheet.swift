import SwiftUI

/// Figma: "Add game" (341:1849), "Error" (341:3054), "Edit game" (341:2703) and its cancel
/// confirmation (341:2840): a stack of field cards. Errors are a red outline and a line under
/// the field, never an alert (SPEC §7.7.3).
struct GameFormSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: GameFormViewModel
    @State private var cancelling: Game?
    @State private var picksLocation = false
    @State private var picksTime = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name, meetUp, notes
    }

    init(editing: Game? = nil, template: Game? = nil) {
        let viewModel = GameFormViewModel(editing: editing, template: template)
        #if DEBUG
        // `-screen form-error`: the Figma "Error" frame (no name, a start time that already passed).
        if UserDefaults.standard.string(forKey: "screen") == "form-error" {
            viewModel.time = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: .now) ?? .now
            viewModel.place = MockFixtures.Places.basketballCourts
            viewModel.meetUpSpot = "By the north court bleachers"
            viewModel.notes = "Casual 3-on-3. I have an extra ball."
            viewModel.showsErrors = true
        }
        // `-screen add-filled`: a filled-in Add game form (marketing screenshots).
        if UserDefaults.standard.string(forKey: "screen") == "add-filled" {
            viewModel.name = "After-work hoops"
            viewModel.time = Calendar.current.date(bySettingHour: 19, minute: 30, second: 0, of: .now) ?? .now
            viewModel.meetUpSpot = "By the north court bleachers"
            viewModel.notes = "Casual 3-on-3. I have an extra ball."
            viewModel.place = MockFixtures.Places.basketballCourts
        }
        // `-screen picker`: straight into "Where's the game?".
        _picksLocation = State(initialValue: UserDefaults.standard.string(forKey: "screen") == "picker")
        #endif
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            form
                .toolbar(.hidden, for: .navigationBar)
                .navigationTitle(viewModel.title)
                .navigationDestination(isPresented: $picksLocation) {
                    LocationPickerView(place: $viewModel.place, campus: store.campus, sport: viewModel.sport)
                }
        }
        .sheetChrome()
        .cancelGameDialog($cancelling) { dismiss() }
        #if DEBUG
        .onAppear {
            // `-screen cancel-game`: the confirmation over Edit game.
            if UserDefaults.standard.string(forKey: "screen") == "cancel-game" { cancelling = viewModel.editing }
        }
        #endif
    }

    private var form: some View {
        @Bindable var viewModel = viewModel

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(title: Text(viewModel.title), subtitle: Text(viewModel.subtitle)) { dismiss() }
                    .padding(.bottom, 2)

                Menu {
                    Picker("Sport", selection: $viewModel.sport) {
                        ForEach(store.postableActivities) { sport in
                            Text("\(sport.emoji) \(sport.name)").tag(sport)
                        }
                    }
                } label: {
                    FieldBox("Sport", showsChevron: true) {
                        Text("\(viewModel.sport.emoji)  \(viewModel.sport.name)")
                    }
                }

                FieldBox("Game name", error: viewModel.nameError, isFocused: focus == .name) {
                    TextField("e.g. After-work hoops", text: $viewModel.name)
                        .textInputAutocapitalization(.sentences)
                        .focused($focus, equals: .name)
                }

                schedule

                locationCard

                FieldBox("Meet-up spot (optional)", error: viewModel.meetUpError, isFocused: focus == .meetUp) {
                    TextField("e.g. By the north court bleachers", text: $viewModel.meetUpSpot)
                        .focused($focus, equals: .meetUp)
                }

                playersCard

                Toggle(isOn: $viewModel.autoRepost) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Auto-repost")
                            .font(.rounded(.body, .bold))
                            .foregroundStyle(Theme.ink)
                        Text("If someone drops out, we'll bump your game back to the top of the map.")
                            .font(.rounded(.caption))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .cardSurface(radius: Theme.Radius.field)

                notes

                if let formError = viewModel.formError {
                    Label(formError, systemImage: "exclamationmark.circle")
                        .font(.rounded(.footnote))
                        .foregroundStyle(Theme.error)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 22)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Button {
                    save()
                } label: {
                    if viewModel.isSaving { ProgressView().tint(Theme.onAccent) } else { Text(viewModel.saveButtonTitle) }
                }
                .disabled(viewModel.isSaving)
                .pill(.primary)

                if let editing = viewModel.editing {
                    Button("Cancel game") { cancelling = editing }
                        .pill(.quietDestructive)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 10)
            .padding(.bottom, 8)
            // Solid so the fields don't show through the buttons.
            .background(Theme.background)
        }
    }

    /// Date · Start time · Duration, with the time error under the row.
    private var schedule: some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Date", selection: $viewModel.day) {
                        ForEach(viewModel.dayOptions, id: \.self) { option in
                            Text(viewModel.dayLabel(option)).tag(option)
                        }
                    }
                } label: {
                    FieldBox("Date", showsChevron: true, isCompact: true) { Text(viewModel.dayLabel(viewModel.day)) }
                }

                Button {
                    focus = nil
                    picksTime = true
                } label: {
                    FieldBox("Start time", isInvalid: viewModel.timeError != nil, showsChevron: true, isCompact: true) {
                        Text(verbatim: viewModel.timeLabel)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $picksTime) {
                    DatePicker("Start time", selection: $viewModel.time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(width: 250, height: 180)
                        .padding(.horizontal, 8)
                        .presentationCompactAdaptation(.popover)
                }

                Menu {
                    Picker("Duration", selection: $viewModel.duration) {
                        ForEach(GameFormViewModel.durations, id: \.self) { Text(EventFormat.duration($0)).tag($0) }
                    }
                } label: {
                    FieldBox("Duration", showsChevron: true, isCompact: true) { Text(EventFormat.duration(viewModel.duration)) }
                }
            }
            if let timeError = viewModel.timeError {
                Text(timeError)
                    .font(.rounded(.caption))
                    .foregroundStyle(Theme.error)
                    .padding(.leading, 4)
            }
        }
    }

    /// Location card: map thumbnail, place, address and **Change**.
    private var locationCard: some View {
        HStack(spacing: 12) {
            if let coordinate = viewModel.place?.coordinate ?? store.campus?.center {
                MapThumbnail(coordinate: coordinate)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Location")
                    .font(.rounded(.caption))
                    .foregroundStyle(Theme.muted)
                if let place = viewModel.place {
                    Text(verbatim: place.name)
                        .font(.rounded(.body, .bold))
                        .foregroundStyle(Theme.ink)
                    Text(verbatim: place.address)
                        .font(.rounded(.caption))
                        .foregroundStyle(Theme.muted)
                } else {
                    Text("Where's the game?")
                        .font(.rounded(.body, .bold))
                        .foregroundStyle(Theme.ink)
                    if let error = viewModel.placeError {
                        Text(verbatim: error).font(.rounded(.caption)).foregroundStyle(Theme.error)
                    }
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(viewModel.place == nil ? "Choose" : "Change") {
                focus = nil
                picksLocation = true
            }
            .pill(.secondary, expands: false, size: .regular)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 68)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.field))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.field)
                .strokeBorder(viewModel.placeError == nil ? Theme.hairline : Theme.error, lineWidth: viewModel.placeError == nil ? 1 : 1.5)
        }
    }

    /// "6 players" with a stepper; "Including you", or "3 joined" when editing.
    private var playersCard: some View {
        @Bindable var viewModel = viewModel

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Players")
                    .font(.rounded(.caption))
                    .foregroundStyle(Theme.muted)
                Text(verbatim: viewModel.playersLabel)
                    .font(.rounded(.body, .bold))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Text(verbatim: viewModel.playersHint)
                    .font(.rounded(.caption))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Stepper("Players", value: $viewModel.players.animation(.snappy), in: viewModel.minimumPlayers...GameFormViewModel.playerRange.upperBound)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .cardSurface(radius: Theme.Radius.field)
        .accessibilityElement(children: .combine)
    }

    /// "What would help someone new say yes?", with one-tap suggestions that add to the note.
    private var notes: some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("What would help someone new say yes?")
                    .font(.rounded(.footnote, .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                OptionalTag()
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Casual 3-on-3. I have an extra ball.", text: $viewModel.notes, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.rounded(.callout))
                    .foregroundStyle(Theme.ink)
                    .focused($focus, equals: .notes)
                if let error = viewModel.notesError {
                    Text(verbatim: error).font(.rounded(.caption)).foregroundStyle(Theme.error)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.field))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.field)
                    .strokeBorder(outline(isInvalid: viewModel.notesError != nil, isFocused: focus == .notes), lineWidth: viewModel.notesError != nil || focus == .notes ? 1.5 : 1)
            }

            if !viewModel.suggestions.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(viewModel.suggestions, id: \.self) { suggestion in
                        Button {
                            withAnimation(.snappy) { viewModel.addSuggestion(suggestion) }
                        } label: {
                            Label(suggestion, systemImage: "plus")
                                .labelStyle(IconRowLabelStyle(iconWidth: 10, spacing: 4))
                                .font(.rounded(.footnote, .bold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 11)
                                .frame(height: 30)
                                .background(Theme.accentSoft, in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func outline(isInvalid: Bool, isFocused: Bool) -> Color {
        if isInvalid { return Theme.error }
        return isFocused ? Theme.accent : Theme.hairline
    }

    private func save() {
        focus = nil
        Task { if await viewModel.save(in: store) { dismiss() } }
    }
}
