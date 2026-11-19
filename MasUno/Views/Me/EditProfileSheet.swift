import SwiftUI

/// Figma "Edit profile" (E21): name, class year and the sports you play.
struct EditProfileSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ProfileEditorViewModel
    /// Where VoiceOver goes when Save finds a problem.
    @AccessibilityFocusState private var errorFocus: ProfileInput.Field?

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
                    lastNameError: viewModel.nameError(viewModel.lastName),
                    errorFocus: $errorFocus
                )

                Text("Plays")
                    .font(.rounded(.footnote, .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 4)
                FlowLayout(spacing: 8) {
                    ForEach(store.interestActivities) { sport in
                        SportToggle(sport: sport, isOn: viewModel.interests.contains(sport)) { viewModel.toggle(sport) }
                    }
                }
                if let error = viewModel.interestsError ?? viewModel.saveError {
                    Text(verbatim: error).font(.rounded(.caption)).foregroundStyle(Theme.error)
                        .accessibilityFocused($errorFocus, equals: .interests)
                } else {
                    Text("Only you see what you play.").font(.rounded(.footnote)).foregroundStyle(Theme.muted)
                }

                Button("Save") { save() }
                    .disabled(viewModel.isSaving)
                    .pill(.primary)
                    .keyboardShortcut(.defaultAction) // Return on a hardware keyboard (A11Y-20).
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

    /// On a problem, VoiceOver moves to the first one and says it.
    private func save() {
        Task {
            if await viewModel.save(in: store) { return dismiss() }
            if let first = viewModel.firstInvalidField { errorFocus = first }
            if let summary = viewModel.errorSummary { Announce.post(summary, priority: .high) }
        }
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
    /// Moved by the screen when Save finds a problem.
    var errorFocus: AccessibilityFocusState<ProfileInput.Field?>.Binding
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // The name fields stack at accessibility sizes, where half the width cuts them off (A11Y-06).
        let names = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))

        VStack(spacing: 12) {
            names {
                FieldBox("First name", text: $firstName, prompt: Text("First name"), error: firstNameError) { field in
                    field
                        .textContentType(.givenName)
                        .accessibilityFocused(errorFocus, equals: .firstName)
                }
                FieldBox("Last name", text: $lastName, prompt: Text("Last name"), error: lastNameError) { field in
                    field
                        .textContentType(.familyName)
                        .accessibilityFocused(errorFocus, equals: .lastName)
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
