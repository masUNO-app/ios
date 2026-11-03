import SwiftUI

/// Edit profile & interests (E21), reusing the onboarding "About you" + "Interests" fields.
struct EditProfileSheet: View {
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ProfileEditorViewModel

    init(profile: Profile) {
        _viewModel = State(initialValue: ProfileEditorViewModel(profile: profile))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        FieldBox("First name", error: viewModel.nameError(viewModel.firstName)) {
                            TextField("First name", text: $viewModel.firstName)
                                .textContentType(.givenName)
                        }
                        FieldBox("Last name", error: viewModel.nameError(viewModel.lastName)) {
                            TextField("Last name", text: $viewModel.lastName)
                                .textContentType(.familyName)
                        }
                    }

                    Menu {
                        Picker("Class year", selection: $viewModel.classYear) {
                            ForEach(viewModel.classYears, id: \.self) { Text(String($0)).tag($0) }
                        }
                    } label: {
                        FieldBox("Class year", showsChevron: true) { Text(String(viewModel.classYear)) }
                    }

                    // Preview, as on onboarding screen 4.
                    HStack(spacing: 12) {
                        Avatar(name: "\(viewModel.firstName) \(viewModel.lastName)", size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.preview).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text("This is how others see you.").font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What do you play?")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                            .padding(.top, 8)
                        FlowLayout(spacing: 8) {
                            ForEach(Sport.postable) { sport in
                                interestToggle(sport)
                            }
                        }
                        if let error = viewModel.interestsError {
                            Text(error).font(.caption).foregroundStyle(Theme.error)
                        } else {
                            Text("Only you see your interests.").font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) {
                Button("Save") {
                    if viewModel.save(in: store) { dismiss() }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .buttonSizing(.flexible)
                .fontWeight(.semibold)
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 8)
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .tint(Theme.ink)
                }
            }
        }
        .presentationBackground(Theme.background)
    }

    private func interestToggle(_ sport: Sport) -> some View {
        let isOn = viewModel.interests.contains(sport)
        return Button {
            viewModel.toggle(sport)
        } label: {
            HStack(spacing: 6) {
                Text(sport.emoji)
                Text(sport.name)
                if isOn { Image(systemName: "checkmark").fontWeight(.semibold) }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(isOn ? Theme.chipSport : Theme.card, in: .capsule)
            .overlay(Capsule().strokeBorder(isOn ? Theme.pin.opacity(0.5) : Theme.hairline, lineWidth: isOn ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
