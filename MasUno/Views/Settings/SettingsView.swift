import CoreLocation
import SwiftUI

/// Figma: "Settings" (341:2144): grouped cards, a colored icon tile on each row, and Sign out and
/// Delete account as glass pills. Notifications sit above Privacy & safety (E16). The calendar and
/// name-visibility rows are out (R7-5).
struct SettingsView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(GameStore.self) private var store
    @Environment(PushNotificationService.self) private var push
    @State private var prefQueue = NotificationPrefQueue()
    @State private var prefsLoaded = false
    @State private var prefsFailed = false
    @State private var confirmsSignOut = false
    @State private var confirmsDelete = false
    @State private var locationStatus = CLLocationManager().authorizationStatus
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            // Side by side in open landscape, stacked otherwise. Spacing 10 keeps phones as they were.
            CardGrid(spacing: 10) {
                section("Notifications") {
                    if push.authorizationStatus == .denied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            row(
                                "Notifications are off in iOS Settings",
                                subtitle: Text("Open Settings"),
                                systemImage: "bell.slash",
                                color: Theme.separator,
                                trailing: "arrow.up.forward"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if prefsLoaded {
                        preference("Games that match your sports", key: \.interestMatch, systemImage: "sportscourt", color: Color(.sportSoccer).opacity(0.35))
                        preference("A spot opens up", key: \.spotOpen, systemImage: "person.badge.plus", color: Color(.person4).opacity(0.45))
                        preference("Game reminders", key: \.reminders, systemImage: "clock", color: Color(.person1).opacity(0.5))
                        preference("Updates on games you host", key: \.hosting, systemImage: "megaphone", color: Color(.sportBasketball).opacity(0.35))
                        preference("Group chat messages", key: \.chat, systemImage: "bubble.left.and.bubble.right", color: Color(.sportVolleyball).opacity(0.45))
                        preference("Tips to play", key: \.winback, systemImage: "sparkles", color: Theme.you.opacity(0.55))
                        Text("Cancellations, changes and You're in are always on.")
                            .font(.rounded(.footnote))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                    } else if prefsFailed {
                        Button {
                            Task { await loadPrefs() }
                        } label: {
                            row(
                                "Couldn't load notification settings",
                                subtitle: Text("Try again"),
                                systemImage: "arrow.clockwise",
                                color: Theme.separator,
                                trailing: nil
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                }

                section("Privacy & safety") {
                    // iOS owns the setting, so the row goes straight to it.
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        row(
                            "Location", subtitle: Text(locationSubtitle), systemImage: "mappin.and.ellipse",
                            color: Color(.sportVolleyball).opacity(0.45), trailing: "arrow.up.forward"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens iPhone Settings")
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

                // The third grid item, so it's one column wide and lands under Privacy & safety
                // when there are two.
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
            .wideColumn()
        }
        .background(Theme.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await push.refreshAuthorization()
            await loadPrefs()
        }
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
        // Back from iPhone Settings: show the new answer.
        .onChange(of: scenePhase) {
            locationStatus = CLLocationManager().authorizationStatus
            if scenePhase == .active {
                Task {
                    await push.refreshAuthorization()
                    if prefsFailed { await loadPrefs() }
                }
            }
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

    private func loadPrefs() async {
        prefsFailed = false
        do {
            prefQueue.replace(try await push.fetchPrefs())
            prefsLoaded = true
        } catch {
            prefsLoaded = false
            prefsFailed = true
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
    private func preference(
        _ title: String, key: WritableKeyPath<NotificationPrefs, Bool>, systemImage: String, color: Color
    ) -> some View {
        Toggle(isOn: Binding(
            get: { prefQueue.displayed[keyPath: key] },
            set: { newValue in
                prefQueue.set(key, to: newValue, send: { snapshot in
                    try await push.setPrefs(snapshot)
                }, onFailure: { error in
                    store.notice = error.message
                })
            }
        )) {
            HStack(spacing: 14) {
                IconTile(systemImage: systemImage, color: color)
                Text(title)
                    .font(.rounded(.body))
                    .foregroundStyle(Theme.ink)
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
    }

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
            .readableColumn(alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle("Community guidelines")
        .navigationBarTitleDisplayMode(.large)
    }
}
