import CoreLocation
import SwiftUI

/// Figma: "Settings" (341:2144): grouped cards, a colored icon tile on each row, and Sign out and
/// Delete account as glass pills. The rows are the ones from SPEC §7.6.7 that work today; the
/// notification toggles arrive with E16, and the calendar and name-visibility rows are out (R7-5).
struct SettingsView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(GameStore.self) private var store
    @State private var confirmsSignOut = false
    @State private var confirmsDelete = false
    @State private var locationStatus = CLLocationManager().authorizationStatus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                section("Privacy & safety") {
                    NavigationLink(value: Route.locationSettings) {
                        row("Location", subtitle: Text(locationSubtitle), systemImage: "mappin.and.ellipse", color: Color(.sportVolleyball).opacity(0.45))
                    }
                    NavigationLink(value: Route.blockedPeople) {
                        row("Blocked people", subtitle: Text(blockedSubtitle), systemImage: "nosign", color: Color(.person5).opacity(0.5))
                    }
                    NavigationLink(value: Route.guidelines) {
                        row("Community guidelines", subtitle: Text("What everyone agrees to"), systemImage: "checkmark.shield", color: Theme.accentSoft)
                    }
                }

                section("About") {
                    Link(destination: appViewModel.config.privacyURL) {
                        row("Privacy & Terms", subtitle: Text("Opens our website"), systemImage: "hand.raised", color: Theme.you.opacity(0.6), trailing: "arrow.up.forward")
                    }
                    if let mail = appViewModel.config.supportMailURL {
                        Link(destination: mail) {
                            row("Contact us", subtitle: Text(verbatim: appViewModel.config.supportEmail), systemImage: "envelope", color: Color(.person1).opacity(0.5), trailing: "arrow.up.forward")
                        }
                    }
                    row("Version", subtitle: Text(verbatim: "\(AppConfig.currentVersion) (\(buildNumber))"), systemImage: "info", color: Theme.separator, trailing: nil)
                }

                VStack(spacing: 14) {
                    Button("Sign out") { confirmsSignOut = true }
                        .pill(.quietDestructive)
                    Button("Delete account") { confirmsDelete = true }
                        .pill(.quietDestructive)
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
            .readableColumn()
        }
        .background(Theme.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            locationStatus = CLLocationManager().authorizationStatus
            #if DEBUG
            switch UserDefaults.standard.string(forKey: "screen") {
            case "sign-out": confirmsSignOut = true
            case "delete-account": confirmsDelete = true
            default: break
            }
            #endif
        }
        .dialog(isPresented: $confirmsSignOut) {
            DialogCard(
                systemImage: "rectangle.portrait.and.arrow.right", tone: .destructive,
                title: Text("Sign out?"),
                message: Text("Your games and saved spots stay put. Sign back in anytime with your school email."),
                confirm: DialogAction("Sign out") { Task { await appViewModel.signOut(store: store) } },
                cancel: DialogAction("Cancel")
            )
        }
        .dialog(isPresented: $confirmsDelete) {
            DialogCard(
                systemImage: "trash", tone: .destructive,
                title: Text("Delete your account?"),
                message: Text("We'll remove your profile, cancel the games you host and give up your spots right away. People in your games will see a spot open up."),
                footnote: Text("This can't be undone."),
                confirm: DialogAction("Delete account") { Task { await appViewModel.deleteAccount(store: store) } },
                cancel: DialogAction("Keep my account")
            )
        }
    }

    private var locationSubtitle: LocalizedStringKey {
        switch locationStatus {
        case .authorizedWhenInUse, .authorizedAlways: "While using the app"
        case .denied, .restricted: "Off"
        default: "Not set"
        }
    }

    private var blockedSubtitle: LocalizedStringKey {
        switch store.blockedPeople.count {
        case 0: "No one"
        case 1: "1 person"
        default: "\(store.blockedPeople.count) people"
        }
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.rounded(.footnote, .bold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { rows() }
                .padding(.vertical, 6)
                .cardSurface()
        }
    }

    /// Icon tile, title over subtitle, and a chevron (or another symbol, or nothing).
    private func row(
        _ title: LocalizedStringKey, subtitle: Text, systemImage: String, color: Color,
        trailing: String? = "chevron.right"
    ) -> some View {
        HStack(spacing: 14) {
            IconTile(systemImage: systemImage, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.rounded(.body))
                    .foregroundStyle(Theme.ink)
                subtitle
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Image(systemName: trailing)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted.opacity(0.6))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .contentShape(.rect)
    }
}

/// Figma "Location". iOS owns the setting, so the two rows show where it stands and
/// **Open iPhone Settings** is the way to change it.
struct LocationSettingsView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = CLLocationManager().authorizationStatus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("masUNO uses your location only to show games near you. It never leaves your phone.")
                    .font(.rounded(.body))
                    .foregroundStyle(Theme.muted)

                OptionRow(title: String(localized: "While using the app"), isSelected: isOn) { openSettings() }
                OptionRow(title: String(localized: "Never"), isSelected: isOff) { openSettings() }

                Text(offNote)
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.muted)

                Button("Open iPhone Settings") { openSettings() }
                    .pill(.quiet)
                    .padding(.top, 6)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 4)
            .readableColumn()
        }
        .background(Theme.background)
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.large)
        // Back from iPhone Settings: show the new answer.
        .onChange(of: scenePhase) { status = CLLocationManager().authorizationStatus }
    }

    private var isOn: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    private var isOff: Bool {
        status == .denied || status == .restricted
    }

    private var offNote: String {
        if let campus = store.campus { return String(localized: "When it's off, we show games around \(campus.shortName) instead.") }
        return String(localized: "When it's off, we show games around your campus instead.")
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

/// The four rules everyone agrees to in onboarding (SPEC §7.5).
struct CommunityGuidelinesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("masUNO works because people show up and play fair.")
                    .font(.rounded(.body))
                    .foregroundStyle(Theme.muted)
                CommunityRules()
                    .padding(18)
                    .cardSurface()
                SafetyNote(text: "Anything feel off? You can report or block anyone from a game's Who's going list.")
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 4)
            .readableColumn()
        }
        .background(Theme.background)
        .navigationTitle("Community guidelines")
        .navigationBarTitleDisplayMode(.large)
    }
}
