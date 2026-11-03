#if DEBUG
import SwiftUI

/// Every design-system token and component on one screen, for design review with Arianna.
/// Open it by long-pressing the avatar on the map, or launch with `-screen gallery`.
struct ComponentGallery: View {
    @State private var reminders = true
    @State private var calendar = false
    @State private var name = ""
    @State private var showsDialog = false
    @State private var showsSheet = false

    private let swatches: [(String, Color)] = [
        ("accent", Theme.accent), ("accentSoft", Theme.accentSoft),
        ("background", Theme.background), ("card", Theme.card),
        ("ink", Theme.ink), ("muted", Theme.muted), ("mutedLarge", Theme.mutedLarge),
        ("pin", Theme.pin), ("destructive", Theme.destructive), ("error", Theme.error),
        ("chipSport", Theme.chipSport), ("hairline", Theme.hairline),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                section("Colors") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                        ForEach(swatches, id: \.0) { name, color in
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(color)
                                    .frame(height: 44)
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline))
                                Text(verbatim: name).font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }

                section("Text") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "After-work hoops").font(.largeTitle.bold())
                        Text(verbatim: "Who's going").font(.headline)
                        Text(verbatim: "Casual 3-on-3 after work. Bring a ball if you have one.").font(.body)
                        Text(verbatim: "Starts in 35 min · about 1 hour").font(.footnote).foregroundStyle(Theme.muted)
                        Text(verbatim: "Basketball · Hosted by Alex (≥ 18 pt)").font(.title3).foregroundStyle(Theme.mutedLarge)
                    }
                    .foregroundStyle(Theme.ink)
                }

                section("Buttons (native styles)") {
                    VStack(spacing: 12) {
                        Button(String("Primary · .glassProminent")) {}
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .buttonSizing(.flexible)
                        Button(String("Secondary · .glassProminent + accentSoft")) {}
                            .buttonStyle(.glassProminent)
                            .tint(Theme.accentSoft)
                            .foregroundStyle(Theme.ink)
                            .controlSize(.large)
                            .buttonSizing(.flexible)
                        Button(String("Delete event"), role: .destructive) { showsDialog = true }
                            .buttonStyle(.glassProminent)
                            .tint(Theme.destructive)
                            .controlSize(.large)
                            .buttonSizing(.flexible)
                        Button(String("Disabled")) {}
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .buttonSizing(.flexible)
                            .disabled(true)
                        HStack(spacing: 12) {
                            Button(String("Leave")) {}
                                .buttonStyle(.glassProminent)
                                .tint(Theme.accentSoft)
                                .foregroundStyle(Theme.ink)
                            Button(String("Edit")) {}
                                .buttonStyle(.glassProminent)
                                .tint(Theme.accentSoft)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                        }
                        HStack(spacing: 12) {
                            ForEach(["chevron.left", "bookmark", "gearshape", "xmark"], id: \.self) { symbol in
                                Button(symbol, systemImage: symbol) {}
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.glass)
                                    .buttonBorderShape(.circle)
                                    .controlSize(.large)
                                    .tint(Theme.ink)
                            }
                            Spacer()
                        }
                        Button(String("Sign out"), role: .destructive) {}
                            .tint(Theme.destructive)
                            .fontWeight(.semibold)
                    }
                }

                section("Fields") {
                    VStack(spacing: 12) {
                        FieldBox("Event name", hint: "Give it a real name, not just the sport") {
                            TextField(text: $name) { Text(verbatim: "e.g. After-work hoops") }
                        }
                        FieldBox("Event name", error: "Add a name so people know what they're joining.") {
                            Text(verbatim: "e.g. After-work hoops").foregroundStyle(Theme.muted)
                        }
                        HStack(spacing: 10) {
                            FieldBox("Date", showsChevron: true) { Text(verbatim: "Sat, Oct 24") }
                            FieldBox("Start time", error: "Already passed", showsChevron: true) { Text(verbatim: "9:00 AM") }
                        }
                    }
                }

                section("Chips & tiles") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            StatusChip("Open · 4 spots left")
                            StatusChip("Full")
                        }
                        HStack {
                            ForEach(Sport.postable) { InterestChip(sport: $0) }
                        }
                        HStack(spacing: 12) {
                            ForEach(Sport.allCases) { ActivityTile(sport: $0) }
                        }
                    }
                }

                section("Avatars") {
                    HStack(spacing: 16) {
                        Avatar(name: "Leo Park", size: 40)
                        Avatar(name: "Maya", size: 40)
                        Avatar(name: Person.you, size: 40)
                        AvatarStack(names: ["Maya Chen", "Jordan Lee", "Leo Park"])
                        AvatarStack(names: ["Maya Chen", "Jordan Lee", "Leo Park", "Sofía Ramírez", "Diego Morales", "You"])
                    }
                }

                section("Game card") {
                    GameCard(event: MockData.events()[0]) {
                        Button(String("Leave")) {}
                            .buttonStyle(.glassProminent)
                            .tint(Theme.accentSoft)
                            .foregroundStyle(Theme.ink)
                    } footer: {
                        Button(String("Group chat · 2 new")) {}
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .buttonSizing(.flexible)
                    }
                }

                section("Native patterns") {
                    VStack(spacing: 12) {
                        NavigationLink(String("Settings · Form + Toggle")) { settingsSample }
                        Button(String("Sheet · title, subtitle, close")) { showsSheet = true }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accentSoft)
                    .foregroundStyle(Theme.ink)
                    .controlSize(.large)
                    .buttonSizing(.flexible)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .background(Theme.background)
        .navigationTitle(Text(verbatim: "Component gallery"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsSheet) { sheetSample }
        .alert(Text(verbatim: "Delete Sunday Coffee Walk?"), isPresented: $showsDialog) {
            Button(role: .destructive) {} label: { Text(verbatim: "Delete event") }
            Button(role: .cancel) {} label: { Text(verbatim: "Keep event") }
        } message: {
            Text(verbatim: "We'll let the 3 people who joined know it's cancelled.")
        }
    }

    /// Settings use a native `Form`; the theme only hides the default background.
    private var settingsSample: some View {
        Form {
            Section(String("Notifications")) {
                Toggle(isOn: $reminders) {
                    Text(verbatim: "Game reminders")
                    Text(verbatim: "30 min before games you've joined")
                }
                Toggle(isOn: $calendar) {
                    Text(verbatim: "Add games to my calendar")
                    Text(verbatim: "Only games you join, nothing else")
                }
            }
            Section(String("Calendar & privacy")) {
                NavigationLink {
                    EmptyView()
                } label: {
                    Text(verbatim: "Location")
                    Text(verbatim: "While using the app")
                }
                Button(String("Sign out"), role: .destructive) {}
                    .tint(Theme.destructive)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(Text(verbatim: "Settings"))
    }

    /// Sheets use the native large title, subtitle and close button.
    private var sheetSample: some View {
        NavigationStack {
            Text(verbatim: "Sheet content")
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
                .navigationTitle(Text(verbatim: "Edit event"))
                .navigationSubtitle(Text(verbatim: "Changes are shared with everyone going."))
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) { showsSheet = false }
                    }
                }
        }
        .presentationDetents([.large])
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .textCase(.uppercase)
            content()
        }
    }
}

#Preview {
    NavigationStack { ComponentGallery() }
}
#endif
