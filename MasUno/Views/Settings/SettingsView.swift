import CoreLocation
import SwiftUI

/// Figma: "Settings" (341:2144), with the 1.0 rows from SPEC §7.6.7. Notifications come
/// in 2.0 (E16); no calendar toggle or "Who can see your name" during the program.
struct SettingsView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(GameStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var confirmsDelete = false
    @State private var locationStatus = CLLocationManager().authorizationStatus

    var body: some View {
        Form {
            Section("Privacy & safety") {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    row("Location", subtitle: Text(locationSubtitle), trailing: "arrow.up.right")
                }
                NavigationLink(value: Route.blockedPeople) {
                    row("Blocked people", subtitle: nil)
                }
                NavigationLink {
                    CommunityGuidelinesView()
                } label: {
                    row("Community guidelines", subtitle: nil)
                }
            }

            Section("About") {
                if let privacy = appViewModel.config.privacyURL {
                    Link(destination: privacy) { row("Privacy & Terms", subtitle: nil, trailing: "arrow.up.right") }
                } else {
                    row("Privacy & Terms", subtitle: Text("Coming soon"))
                }
                if let mail = appViewModel.config.supportMailURL {
                    Link(destination: mail) {
                        row("Contact us", subtitle: Text(verbatim: appViewModel.config.supportEmail), trailing: "envelope")
                    }
                }
                LabeledContent("Version", value: "\(AppConfig.currentVersion) (\(buildNumber))")
                    .foregroundStyle(Theme.ink)
            }

            Section("Account") {
                Button("Sign out") { Task { await appViewModel.signOut(store: store) } }
                    .foregroundStyle(Theme.ink)
                Button("Delete account", role: .destructive) { confirmsDelete = true }
                    .tint(Theme.destructive)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Settings")
        .onAppear { locationStatus = CLLocationManager().authorizationStatus }
        .alert("Delete your masUNO account?", isPresented: $confirmsDelete) {
            Button("Delete account", role: .destructive) { Task { await appViewModel.deleteAccount(store: store) } }
            Button("Keep account", role: .cancel) {}
        } message: {
            Text("We'll cancel games you're hosting, remove you from games you joined, and delete your profile. This can't be undone.")
        }
    }

    private var locationSubtitle: LocalizedStringKey {
        switch locationStatus {
        case .authorizedWhenInUse, .authorizedAlways: "While using the app"
        case .denied, .restricted: "Off — tap to turn on in Settings"
        default: "Not set"
        }
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    private func row(_ title: LocalizedStringKey, subtitle: Text?, trailing: String? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.ink)
                if let subtitle {
                    subtitle.font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            if let trailing {
                Image(systemName: trailing)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .contentShape(.rect)
    }
}

/// The four rules everyone agrees to in onboarding (SPEC §7.5).
struct CommunityGuidelinesView: View {
    private let rules: [LocalizedStringKey] = [
        "Be respectful. No harassment, hate or slurs.",
        "Keep it about the game: plans, timing, where to meet.",
        "Don't share anyone's personal info or photos without asking.",
        "Meet in public places and look out for each other.",
    ]

    var body: some View {
        Form {
            Section {
                ForEach(rules.indices, id: \.self) { index in
                    Label {
                        Text(rules[index]).foregroundStyle(Theme.ink)
                    } icon: {
                        Image(systemName: "checkmark").foregroundStyle(Theme.accent).fontWeight(.semibold)
                    }
                }
            } footer: {
                Text("You can report or block anyone from the Who's going list.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Community guidelines")
    }
}
