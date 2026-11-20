import SwiftUI

/// Figma: "Make a plan" (341:1849), "Error" (341:3054), "Edit plan" (341:2703) and its cancel
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
    /// Where VoiceOver goes when Create/Save finds a problem.
    @AccessibilityFocusState private var errorFocus: Field?
    /// At accessibility sizes, rows of side-by-side pieces stack (A11Y-06).
    @Environment(\.dynamicTypeSize) private var typeSize

    private typealias Field = GameFormViewModel.Field

    init(editing: Game? = nil, template: Game? = nil) {
        let viewModel = GameFormViewModel(editing: editing, template: template)
        #if DEBUG
        // `-screen form-error`: the Figma "Error" frame (no name, a start time that already passed).
        if UserDefaults.standard.string(forKey: "screen") == "form-error" {
            viewModel.time = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: .now) ?? .now
            viewModel.place = MockFixtures.Places.basketballCourts
            viewModel.meetUpSpot = "By the north court bleachers"
            viewModel.notes = "Chill, all levels welcome. Coming alone is fine."
            viewModel.showsErrors = true
        }
        // `-screen add-filled`: a filled-in Add game form (marketing screenshots).
        if UserDefaults.standard.string(forKey: "screen") == "add-filled" {
            let shot = MockFixtures.isScreenshotWorld
            viewModel.name = shot ? MockFixtures.spanishShot("Pickup after class", "Retas después de clase") : "After-work hoops"
            viewModel.time = Calendar.current.date(bySettingHour: shot ? 17 : 19, minute: 30, second: 0, of: .now) ?? .now
            // Screenshots: today before 3 PM, tomorrow after, like the fixtures, so it's never in the past.
            if shot, Calendar.current.component(.hour, from: .now) >= 15, viewModel.dayOptions.count > 1 {
                viewModel.day = viewModel.dayOptions[1]
            }
            viewModel.meetUpSpot = MockFixtures.spanishShot("By the north court bleachers", "Junto a las gradas de la cancha norte")
            viewModel.notes = shot
                ? MockFixtures.spanishShot("First time? Come anyway, we rotate every game.", "¿Primera vez? Vente, rotamos cada juego.")
                : "Chill, all levels welcome. Coming alone is fine."
            viewModel.place = MockFixtures.Places.basketballCourts
        }
        // `-screen picker`: straight into "Where's it happening?" (`picker-map`: without the search).
        _picksLocation = State(initialValue: ["picker", "picker-map"].contains(UserDefaults.standard.string(forKey: "screen")))
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

                if store.activityKinds.count > 1 {
                    kindPicker
                } else {
                    Menu {
                        Picker("Sport", selection: $viewModel.sport) {
                            ForEach(store.postableActivities) { sport in
                                Text("\(sport.emoji) \(sport.name)")
                                    .accessibilityLabel(Text(sport.name))
                                    .tag(sport)
                            }
                        }
                    } label: {
                        FieldBox("Sport", showsChevron: true) {
                            // The name alone: the emoji would be read too (A11Y-11).
                            Text("\(viewModel.sport.emoji)  \(viewModel.sport.name)")
                                .accessibilityLabel(Text(viewModel.sport.name))
                        }
                    }
                }

                FieldBox(
                    "What's the plan?", text: $viewModel.name,
                    prompt: viewModel.isEsports ? Text("e.g. Valorant night at the game room") : Text("e.g. Pickup after class"),
                    error: viewModel.nameError, isFocused: focus == .name
                ) { field in
                    field
                        .textInputAutocapitalization(.sentences)
                        .focused($focus, equals: .name)
                        .accessibilityFocused($errorFocus, equals: .name)
                        .accessibilityIdentifier("game-name-field")
                }

                schedule

                locationCard

                FieldBox(
                    "Meet-up spot (optional)", text: $viewModel.meetUpSpot, prompt: Text("e.g. By the big tree outside the library"),
                    error: viewModel.meetUpError, isFocused: focus == .meetUp
                ) { field in
                    field
                        .focused($focus, equals: .meetUp)
                        .accessibilityFocused($errorFocus, equals: .meetUp)
                }

                playersCard

                if viewModel.isEsports { rotationCard }

                Toggle(isOn: $viewModel.autoRepost) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Auto-repost")
                            .font(.rounded(.body, .bold))
                            .foregroundStyle(Theme.ink)
                        Text("If someone drops out, we'll bump your plan back to the top of the map.")
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
                WorkingButton(verbatim: viewModel.saveButtonTitle, isWorking: viewModel.isSaving) { save() }
                    .keyboardShortcut(.defaultAction) // Return on a hardware keyboard (A11Y-20).

                if let editing = viewModel.editing {
                    Button("Cancel plan") { cancelling = editing }
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
            stacksAt(spacing: 8) {
                Menu {
                    Picker("Date", selection: $viewModel.day) {
                        ForEach(viewModel.dayOptions, id: \.self) { option in
                            Text(viewModel.dayLabel(option)).tag(option)
                        }
                    }
                } label: {
                    FieldBox("Date", showsChevron: true, isCompact: true) { Text(viewModel.dayLabel(viewModel.day)) }
                }

                if typeSize.isAccessibilitySize {
                    startTimePicker
                } else {
                    Button {
                        focus = nil
                        picksTime = true
                    } label: {
                        FieldBox("Start time", isInvalid: viewModel.timeError != nil, showsChevron: true, isCompact: true) {
                            Text(verbatim: viewModel.timeLabel)
                        }
                    }
                    .buttonStyle(.plain)
                    // The row's error belongs to Start time.
                    .accessibilityHint(Text(verbatim: viewModel.timeError ?? ""))
                    .accessibilityFocused($errorFocus, equals: .time)
                    .popover(isPresented: $picksTime) {
                        DatePicker("Start time", selection: $viewModel.time, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            // The popover asks for its ideal size; the compact picker above
                            // replaces it at accessibility sizes.
                            .frame(minWidth: 250, idealWidth: 250, minHeight: 180, idealHeight: 180)
                            .padding(.horizontal, 8)
                            .presentationCompactAdaptation(.popover)
                    }
                }

                if viewModel.usesRotation {
                    // Set by the rounds below.
                    FieldBox("Ends", isCompact: true) { Text(verbatim: viewModel.endLabel) }
                } else {
                    Menu {
                        Picker("Duration", selection: $viewModel.duration) {
                            ForEach(GameFormViewModel.durations, id: \.self) { Text(EventFormat.duration($0)).tag($0) }
                        }
                    } label: {
                        FieldBox("Duration", showsChevron: true, isCompact: true) { Text(EventFormat.duration(viewModel.duration)) }
                    }
                }
            }
            if let timeError = viewModel.timeError {
                Text(timeError)
                    .font(.rounded(.caption))
                    .foregroundStyle(Theme.error)
                    .padding(.leading, 4)
                    // Read as Start time's hint.
                    .accessibilityHidden(true)
            }
        }
    }

    /// At accessibility sizes the wheel in a popover would be cut off, so the field is the
    /// system's compact picker, which opens its own.
    private var startTimePicker: some View {
        @Bindable var viewModel = viewModel
        let isInvalid = viewModel.timeError != nil

        return VStack(alignment: .leading, spacing: 4) {
            Text("Start time")
                .font(.rounded(.caption))
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            DatePicker("Start time", selection: $viewModel.time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(Theme.accent)
                .accessibilityHint(Text(verbatim: viewModel.timeError ?? ""))
                .accessibilityFocused($errorFocus, equals: .time)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.field))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.field)
                .strokeBorder(isInvalid ? Theme.error : Theme.hairline, lineWidth: isInvalid ? 1.5 : 1)
        }
    }

    /// Side by side, or stacked and leading-aligned at accessibility sizes.
    private func stacksAt(spacing: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        return layout(content)
    }

    /// Location card: map thumbnail, place, address and **Change**, which goes under the text at
    /// accessibility sizes.
    private var locationCard: some View {
        stacksAt(spacing: 12) {
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
                    Text("Where's it happening?")
                        .font(.rounded(.body, .bold))
                        .foregroundStyle(Theme.ink)
                    if let error = viewModel.placeError {
                        Text(verbatim: error).font(.rounded(.caption)).foregroundStyle(Theme.error)
                            // Read as Choose's hint.
                            .accessibilityHidden(true)
                    }
                }
            }
            // Two lines, so a long name or address still reads next to Change on a narrow screen.
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            // "Location", the place and its address in one stop (A11Y-13).
            .accessibilityElement(children: .combine)

            Button(viewModel.place == nil ? "Choose" : "Change") {
                focus = nil
                picksLocation = true
            }
            .pill(.secondary, expands: false, size: .regular)
            .accessibilityLabel(viewModel.place == nil ? Text("Choose") : Text("Change location"))
            .accessibilityInputLabels([viewModel.place == nil ? Text("Choose") : Text("Change")])
            .accessibilityHint(Text(verbatim: viewModel.placeError ?? ""))
            .accessibilityFocused($errorFocus, equals: .place)
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

    /// "6 players" with a stepper; "Including you", or "3 joined" when editing. The stepper goes
    /// under the text at accessibility sizes.
    private var playersCard: some View {
        @Bindable var viewModel = viewModel

        return stacksAt(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("People")
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

            Stepper("People", value: $viewModel.players.animation(.snappy), in: viewModel.playersRange)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .cardSurface(radius: Theme.Radius.field)
        // One adjustable element: swipe up or down to change the count (A11Y-14).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("People"))
        .accessibilityValue(Text(verbatim: "\(viewModel.playersLabel), \(viewModel.playersHint)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: withAnimation(.snappy) { viewModel.stepPlayers(by: 1) }
            case .decrement: withAnimation(.snappy) { viewModel.stepPlayers(by: -1) }
            @unknown default: break
            }
        }
    }

    /// Sports | Esports | …, then that kind's activities as chips. Only once the catalog has more
    /// than one kind.
    private var kindPicker: some View {
        let kind = Binding(
            get: { viewModel.sport.kind },
            set: { kind in withAnimation(.snappy) { viewModel.setKind(kind, from: store.postableActivities) } }
        )
        let choices = store.postableActivities.filter { $0.kind == viewModel.sport.kind }

        return VStack(alignment: .leading, spacing: 12) {
            Picker("Type", selection: kind) {
                ForEach(store.activityKinds, id: \.self) { Text(verbatim: Activity.kindName($0)).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: Activity.itemName(viewModel.sport.kind))
                    .font(.rounded(.caption))
                    .foregroundStyle(Theme.muted)
                FlowLayout(spacing: 8) {
                    ForEach(choices) { activity in
                        SportToggle(sport: activity, isOn: viewModel.sport == activity) {
                            withAnimation(.snappy) { viewModel.sport = activity }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: Theme.Radius.field)
        }
    }

    /// Rotate groups: rounds, their length, the break and the group size, with the night's
    /// timeline under them.
    private var rotationCard: some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $viewModel.rotates.animation(.snappy)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Rotate groups")
                        .font(.rounded(.body, .bold))
                        .foregroundStyle(Theme.ink)
                    Text("Play a round, take a break, then play with a new group.")
                        .font(.rounded(.caption))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)

            if viewModel.rotates {
                stacksAt(spacing: 8) {
                    rotationMenu("Rounds", selection: $viewModel.rotation.rounds, options: Rotation.roundCounts) { Text(verbatim: "\($0)") }
                    rotationMenu("Each round", selection: $viewModel.rotation.roundMinutes, options: Rotation.roundLengths) { Text(EventFormat.duration($0)) }
                }
                stacksAt(spacing: 8) {
                    rotationMenu("Break", selection: $viewModel.rotation.breakMinutes, options: Rotation.breakLengths) { Text(EventFormat.duration($0)) }
                    rotationMenu("Group size", selection: $viewModel.rotation.groupSize, options: Rotation.groupSizes) { Text(verbatim: "\($0)") }
                }

                roundTimeline

                Label {
                    Text("Everyone plays with up to \(viewModel.mostNewPeople) new people. Groups are shuffled so nobody repeats.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "person.2.wave.2")
                }
                .labelStyle(IconRowLabelStyle(iconWidth: 22, spacing: 10))
                .font(.rounded(.footnote))
                .foregroundStyle(Theme.ink)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.sportEsports).opacity(0.22), in: .rect(cornerRadius: 14))

                if let error = viewModel.rotationError {
                    Text(verbatim: error)
                        .font(.rounded(.caption))
                        .foregroundStyle(Theme.error)
                        .accessibilityFocused($errorFocus, equals: .rotation)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.field))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.field)
                .strokeBorder(
                    viewModel.rotationError != nil ? Theme.error : viewModel.rotates ? Color(.sportEsports) : Theme.hairline,
                    lineWidth: viewModel.rotates ? 1.5 : 1
                )
        }
    }

    private func rotationMenu<Choice: View>(
        _ title: LocalizedStringKey, selection: Binding<Int>, options: [Int], label: @escaping (Int) -> Choice
    ) -> some View {
        Menu {
            Picker(title, selection: selection.animation(.snappy)) {
                ForEach(options, id: \.self) { label($0).tag($0) }
            }
        } label: {
            FieldBox(title, showsChevron: true, isCompact: true) { label(selection.wrappedValue) }
        }
    }

    /// Round 1 · break · Round 2 …, at the times the start picked gives them.
    private var roundTimeline: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(viewModel.roundTimes, id: \.round) { round in
                if round.round > 1 {
                    HStack(spacing: 8) {
                        Rectangle().fill(Color(.sportEsports)).frame(width: 2, height: 14).padding(.horizontal, 4)
                        Text("\(viewModel.rotation.breakMinutes) min break, new groups")
                            .font(.rounded(.caption))
                            .foregroundStyle(Theme.muted)
                    }
                    .accessibilityElement(children: .combine)
                }
                HStack(spacing: 8) {
                    Circle().fill(Color(.sportEsports)).frame(width: 10, height: 10)
                    Text("Round \(round.round)")
                        .font(.rounded(.subheadline, .bold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    Text(verbatim: round.time)
                        .font(.rounded(.subheadline))
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 2)
    }

    /// "What would help someone new say yes?", with one-tap suggestions that add to the note.
    private var notes: some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 8) {
            OptionalQuestion("What would help someone new say yes?")
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Chill, all levels welcome. Coming alone is fine.", text: $viewModel.notes, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.rounded(.callout))
                    .foregroundStyle(Theme.ink)
                    .focused($focus, equals: .notes)
                    .accessibilityHint(Text(verbatim: viewModel.notesError ?? ""))
                    .accessibilityFocused($errorFocus, equals: .notes)
                if let error = viewModel.notesError {
                    Text(verbatim: error).font(.rounded(.caption)).foregroundStyle(Theme.error)
                        // Read as the note's hint.
                        .accessibilityHidden(true)
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
                                .padding(.vertical, typeSize.isAccessibilitySize ? 5 : 0)
                                .frame(minHeight: 30)
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

    /// On a problem, VoiceOver moves to the first field with one and says what's wrong.
    private func save() {
        focus = nil
        Task {
            if await viewModel.save(in: store) { return dismiss() }
            if let first = viewModel.firstInvalidField { errorFocus = first }
            if let summary = viewModel.errorSummary { Announce.post(summary, priority: .high) }
        }
    }
}
