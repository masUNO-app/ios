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
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                Text("Sport")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 8)
                sportPicker

                FieldBox("Event name") {
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
                                .foregroundStyle(Theme.actionBlue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Location").font(.caption).foregroundStyle(.secondary)
                                Text(viewModel.venue.name)
                                Text(viewModel.venue.street + ", San Francisco").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Menu {
                        Picker("Players", selection: $viewModel.players) {
                            ForEach(AddEventViewModel.playerCounts, id: \.self) { Text("\($0) players").tag($0) }
                        }
                    } label: {
                        FieldBox("Players · including you", trailingChevron: true) { Text("\(viewModel.players) players") }
                    }

                    Menu {
                        Picker("Skill level", selection: $viewModel.skill) {
                            ForEach(SkillLevel.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        FieldBox("Skill level", trailingChevron: true) { Text(viewModel.skill.rawValue) }
                    }
                    .frame(maxWidth: 160)
                }

                FieldBox("Notes · optional") {
                    TextField("Casual 3-on-3. Bring a ball and some water!", text: $viewModel.notes, axis: .vertical)
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
                Text(viewModel.saveButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.actionBlue)
            .disabled(!viewModel.isNameValid)
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
                Text(viewModel.title)
                    .font(.largeTitle.bold())
                Text(viewModel.subtitle)
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

    private func save() {
        viewModel.save(in: store)
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
