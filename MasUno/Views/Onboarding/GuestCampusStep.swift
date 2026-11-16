import SwiftUI

/// "Which campus?": Browse as a guest when more than one campus is open. Also where
/// "Browse another campus" lands.
struct GuestCampusStep: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(GameStore.self) private var store
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingPage(
            title: "Which campus?",
            message: "Pick a campus to see its games. You can make an account any time."
        ) {
            if viewModel.schoolsFailedToLoad {
                RetryCard(message: "Couldn't load campuses.") { await viewModel.loadSchools() }
            } else if viewModel.isLoadingSchools {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                if viewModel.guestCampusesNeedSearch {
                    FieldBox("Search campuses") {
                        TextField("Search campuses", text: $viewModel.schoolSearch)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                campusList
            }
        } footer: {
            WorkingButton("Browse games", isWorking: viewModel.isStartingGuest) {
                Task { await viewModel.startGuestBrowsing(app: appViewModel, store: store) }
            }
            .disabled(viewModel.guestCampusChoice == nil)
        }
        .task {
            await viewModel.loadSchools()
            // Starts on the campus they were browsing, if the phone remembers one.
            if viewModel.guestCampusChoice == nil, let saved = appViewModel.guestCampus {
                viewModel.guestCampusChoice = viewModel.filteredOpenCampuses.first { $0.id == saved.id }
            }
        }
    }

    private var campusList: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.filteredOpenCampuses) { campus in
                SchoolRow(school: campus, isSelected: campus.id == viewModel.guestCampusChoice?.id) {
                    viewModel.guestCampusChoice = campus
                }
            }
        }
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .cardSurface()
    }
}
