import SwiftUI

/// Figma "Edit profile" (E21): name, class year and the sports you play.
struct EditProfileSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ProfileEditorViewModel

    init(profile: Profile) {
        _viewModel = State(initialValue: ProfileEditorViewModel(profile: profile))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(
                    title: Text("Edit profile"),
                    subtitle: Text("Others see \(viewModel.previewName) and your class year.")
                ) { dismiss() }
                    .padding(.bottom, 2)

                ProfileFields(
                    firstName: $viewModel.firstName, lastName: $viewModel.lastName, classYear: $viewModel.classYear,
                    classYears: viewModel.classYears,
                    firstNameError: viewModel.nameError(viewModel.firstName),
                    lastNameError: viewModel.nameError(viewModel.lastName)
                )

                Text("Plays")
                    .font(.rounded(.footnote, .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 4)
                FlowLayout(spacing: 8) {
                    ForEach(store.interestActivities) { sport in
                        SportToggle(sport: sport, isOn: viewModel.interests.contains(sport)) { viewModel.toggle(sport) }
                    }
                }
                if let error = viewModel.interestsError ?? viewModel.saveError {
                    Text(verbatim: error).font(.rounded(.caption)).foregroundStyle(Theme.error)
                } else {
                    Text("Only you see what you play.").font(.rounded(.footnote)).foregroundStyle(Theme.muted)
                }

                Button("Save") {
                    Task { if await viewModel.save(in: store) { dismiss() } }
                }
                .disabled(viewModel.isSaving)
                .pill(.primary)
                .padding(.top, 8)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 22)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .sheetChrome(detents: [.height(500), .large])
    }
}

/// First name, last name and class year as field cards: Make it yours and Edit profile.
/// Two name fields rather than the Figma's one, because the server keeps them apart and
/// "Emilio G." is built from the last name's initial.
struct ProfileFields: View {
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var classYear: Int
    var classYears: [Int]
    var firstNameError: String?
    var lastNameError: String?

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                FieldBox("First name", error: firstNameError) {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                }
                FieldBox("Last name", error: lastNameError) {
                    TextField("Last name", text: $lastName)
                        .textContentType(.familyName)
                }
            }

            Menu {
                Picker("Class year", selection: $classYear) {
                    ForEach(classYears, id: \.self) { Text(String($0)).tag($0) }
                }
            } label: {
                FieldBox("Class year", showsChevron: true) { Text("Class of \(String(classYear))") }
            }
        }
    }
}
