import SwiftUI

/// Shared scaffold for "Registered events" and "Hosted events": native large title,
/// system back button, and a bottom toolbar (search, add, filter, profile).
struct PlansScaffold<Content: View>: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(\.dismiss) private var dismiss

    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey
    var countLabel: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle(Text(title))
        .navigationSubtitle(Text(subtitle))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(countLabel)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            .sharedBackgroundVisibility(.hidden)

            // Search lives on the map, so this takes you back there.
            ToolbarItem(placement: .bottomBar) {
                Button { dismiss() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("Search events")
                    }
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Add event", systemImage: "plus") { appViewModel.startAdding() }
                Button("Filters", systemImage: "line.3.horizontal.decrease") { dismiss() }
                Button {} label: { // TODO: profile screen
                    Avatar(name: Person.you, size: 30)
                }
                .accessibilityLabel("Profile")
            }
        }
    }
}

struct PlansSectionHeader: View {
    var title: LocalizedStringKey
    var trailing: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline).foregroundStyle(Theme.ink)
            Spacer()
            Text(trailing).font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(.top, 8)
    }
}

/// Figma "Group chat preview": members, last two messages, "Group chat · N new".
struct GroupChatPreview: View {
    var event: SportsEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AvatarStack(names: event.attendees, size: 24)
                Text("\(event.attendees.count) members")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            ForEach(event.messages.suffix(2)) { message in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(message.sender) · \(event.role(of: message.sender))")
                        .font(.caption.weight(message.sender == event.host ? .semibold : .regular))
                        .foregroundStyle(Theme.muted)
                    Text(message.text).font(.subheadline).foregroundStyle(Theme.ink)
                }
            }

            NavigationLink(value: Route.chat(event.id)) {
                Text(event.unreadCount > 0 ? "Group chat · \(event.unreadCount) new" : "Group chat")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .buttonSizing(.flexible)
        }
    }
}
