import SwiftUI

/// Figma: "Sports event map · Add event". Also used for "Edit event" on hosted cards.
struct AddEventSheet: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let editing: SportsEvent?

    @State private var sport: Sport
    @State private var name: String
    @State private var day: Date
    @State private var time: Date
    @State private var duration: TimeInterval
    @State private var venue: Venue
    @State private var players: Int
    @State private var skill: SkillLevel
    @State private var notes: String

    private static let durations: [TimeInterval] = [1800, 3600, 5400, 7200, 10800]
    private static let playerCounts = Array(2...22)

    init(editing: SportsEvent? = nil) {
        self.editing = editing
        let defaultStart = Calendar.current.date(bySettingHour: 17, minute: 30, second: 0, of: .now) ?? .now
        _sport = State(initialValue: editing?.sport ?? .basketball)
        _name = State(initialValue: editing?.title ?? "")
        _day = State(initialValue: Calendar.current.startOfDay(for: editing?.start ?? .now))
        _time = State(initialValue: editing?.start ?? defaultStart)
        _duration = State(initialValue: editing?.duration ?? 3600)
        _venue = State(initialValue: editing?.venue ?? MockData.Venues.postable[0])
        _players = State(initialValue: editing?.capacity ?? 6)
        _skill = State(initialValue: editing?.skillLevel ?? .allLevels)
        _notes = State(initialValue: editing?.notes ?? "")
    }

    /// Games are posted up to 2 days ahead (today, tomorrow, the day after).
    private var dayOptions: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0...2).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    private var sportOptions: [Sport] {
        // Keep a non-sport category selectable when editing one of the Figma mock events.
        Sport.postable.contains(sport) ? Sport.postable : [sport] + Sport.postable
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                Text("Sport")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 8)
                sportPicker

                FieldBox("Event name") {
                    TextField("After-work hoops", text: $name)
                        .textInputAutocapitalization(.sentences)
                }

                HStack(spacing: 10) {
                    Menu {
                        Picker("Date", selection: $day) {
                            ForEach(dayOptions, id: \.self) { option in
                                Text(dayLabel(option)).tag(option)
                            }
                        }
                    } label: {
                        FieldBox("Date") { Text(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) }
                    }

                    FieldBox("Start time") {
                        DatePicker("Start time", selection: $time, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .fixedSize()
                    }

                    Menu {
                        Picker("Duration", selection: $duration) {
                            ForEach(Self.durations, id: \.self) { Text(EventFormat.duration($0)).tag($0) }
                        }
                    } label: {
                        FieldBox("Duration") { Text(EventFormat.duration(duration)) }
                    }
                }

                Menu {
                    Picker("Location", selection: $venue) {
                        ForEach(MockData.Venues.postable) { venue in
                            Text(venue.name).tag(venue)
                        }
                    }
                } label: {
                    FieldBox(nil) {
                        HStack(spacing: 14) {
                            Image(systemName: "mappin.circle")
                                .font(.title2)
                                .foregroundStyle(Theme.actionBlue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Location").font(.caption).foregroundStyle(.secondary)
                                Text(venue.name)
                                Text(venue.street + ", San Francisco").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Menu {
                        Picker("Players", selection: $players) {
                            ForEach(Self.playerCounts, id: \.self) { Text("\($0) players").tag($0) }
                        }
                    } label: {
                        FieldBox("Players · including you", trailingChevron: true) { Text("\(players) players") }
                    }

                    Menu {
                        Picker("Skill level", selection: $skill) {
                            ForEach(SkillLevel.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        FieldBox("Skill level", trailingChevron: true) { Text(skill.rawValue) }
                    }
                    .frame(maxWidth: 160)
                }

                FieldBox("Notes · optional") {
                    TextField("Casual 3-on-3. Bring a ball and some water!", text: $notes, axis: .vertical)
                        .lineLimit(1...3)
                }

                Label("Public event · visible to players nearby", systemImage: "globe")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .tint(Theme.ink)
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                Text(editing == nil ? "Create event" : "Save changes")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.actionBlue)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(Theme.card)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(editing == nil ? "Add event" : "Edit event")
                    .font(.largeTitle.bold())
                Text(editing == nil ? "Get a game going nearby." : "Update the details for your group.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.headline)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
                .tint(.primary)
        }
        .padding(.top, 16)
    }

    private var sportPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(sportOptions) { option in
                    let isSelected = option == sport
                    Button {
                        sport = option
                    } label: {
                        HStack(spacing: 6) {
                            Text(option.emoji)
                            Text(option.name)
                        }
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.actionBlue : .primary)
                        .padding(.horizontal, 18)
                        .frame(height: 40)
                        .background(isSelected ? Theme.actionBlue.opacity(0.12) : Color.white, in: .capsule)
                        .overlay(Capsule().stroke(isSelected ? Theme.actionBlue : Color(.systemGray4)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(1)
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let label = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if Calendar.current.isDateInToday(date) { return "Today · \(label)" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow · \(label)" }
        return label
    }

    private func save() {
        let calendar = Calendar.current
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        let start = calendar.date(bySettingHour: clock.hour ?? 17, minute: clock.minute ?? 30, second: 0, of: day) ?? day
        let title = name.trimmingCharacters(in: .whitespaces)

        var event = editing ?? SportsEvent(
            title: title, sport: sport, host: Person.you, start: start, duration: duration,
            capacity: players, attendees: [Person.you], venue: venue
        )
        event.title = title
        event.sport = sport
        event.start = start
        event.duration = duration
        event.venue = venue
        event.capacity = max(players, event.attendees.count)
        event.skillLevel = skill
        event.notes = notes

        store.save(event)
        dismiss()
    }
}

/// Bordered field container with a small caption label.
private struct FieldBox<Content: View>: View {
    var label: String?
    var trailingChevron = false
    @ViewBuilder var content: Content

    init(_ label: String?, trailingChevron: Bool = false, @ViewBuilder content: () -> Content) {
        self.label = label
        self.trailingChevron = trailingChevron
        self.content = content()
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let label {
                    Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                content.foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.75)
            }
            if trailingChevron {
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray5)))
    }
}
