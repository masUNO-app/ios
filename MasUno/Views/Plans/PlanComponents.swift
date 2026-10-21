import SwiftUI

/// Shared scaffold for "Registered events" and "Hosted events".
struct PlansScaffold<Content: View>: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(\.dismiss) private var dismiss

    var title: String
    var subtitle: String
    var countLabel: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 34, weight: .bold))
                    Text(subtitle)
                        .foregroundStyle(Theme.secondaryInk)
                }
                content
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Theme.cream)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Map")
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 6)
                }
                .tint(Theme.ink)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Text(countLabel)
                    .font(.subheadline)
                    .foregroundStyle(Theme.orange)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            PlansBottomBar(onSearch: { dismiss() }, onAdd: { appViewModel.startAdding() })
        }
    }
}

struct PlansSectionHeader: View {
    var title: String
    var trailing: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            Text(trailing).font(.caption).foregroundStyle(Theme.secondaryInk)
        }
        .padding(.top, 8)
    }
}

/// White card with the event summary (icon, title, status, date, place, meta).
struct PlanEventCard<Footer: View>: View {
    var event: SportsEvent
    var status: String
    var statusIcon: String?
    var metaNoun = "participants"
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                EventIconTile(sport: event.sport)
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title).font(.title3.weight(.semibold))
                    HStack(spacing: 4) {
                        if let statusIcon { Image(systemName: statusIcon) }
                        Text(status)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.orange)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(EventFormat.longDate(event.start), systemImage: "calendar")
                Label {
                    Text("\(event.venue.titleLine)\n\(event.venue.city)")
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
                Text(event.metaLine(noun: metaNoun))
                    .foregroundStyle(Theme.orange)
                    .padding(.top, 2)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryInk)
            .labelStyle(OrangeIconLabelStyle())

            footer
        }
        .padding(18)
        .background(Theme.card, in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.cardStroke))
    }
}

private struct OrangeIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.foregroundStyle(Theme.orange).frame(width: 16)
            configuration.title
        }
    }
}

/// Figma "Group chat preview": members, last two messages, "Open group chat ›".
struct GroupChatPreview: View {
    var event: SportsEvent
    /// Figma's hosted card says "Accepted attendees", which implies approval (not MVP),
    /// so both screens just say "Attendees".
    var guestsRole = "Attendees"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(Theme.orange)
                Text("Group chat").font(.subheadline.weight(.semibold))
                Text("· \(event.attendees.count) members").font(.caption).foregroundStyle(Theme.secondaryInk)
                Spacer()
                if event.unreadCount > 0 {
                    Text("\(event.unreadCount) new")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.orange, in: .capsule)
                }
            }

            HStack(spacing: 10) {
                Avatar(name: event.host, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Text(event.host).fontWeight(.semibold))\(Text(" · Host").foregroundStyle(Theme.secondaryInk))")
                    if !event.guests.isEmpty {
                        let role = event.guests.count == 1 ? "Attendee" : guestsRole
                        Text("\(Text(event.guests.joined(separator: ", ")).fontWeight(.semibold))\(Text(" · \(role)").foregroundStyle(Theme.secondaryInk))")
                    }
                }
                .font(.footnote)
            }

            ForEach(event.messages.suffix(2)) { message in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(message.sender) · \(event.role(of: message.sender))")
                        .font(.caption)
                        .foregroundStyle(message.sender == event.host ? Theme.orange : Theme.secondaryInk)
                    Text(message.text).font(.subheadline)
                }
            }

            NavigationLink(value: Route.chat(event.id)) {
                Text("Open group chat  ›")
            }
            .buttonStyle(.orangeCapsule)
        }
        .padding(16)
        .background(Theme.chatBackground, in: .rect(cornerRadius: 18))
    }
}

/// Bottom glass bar on the plans screens: search + (add, filter, settings).
struct PlansBottomBar: View {
    var onSearch: () -> Void
    var onAdd: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onSearch) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.title3)
                        Text("Search Events").lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "mic").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .contentShape(.capsule)
                }
                .glassEffect(.regular.interactive(), in: .capsule)

                HStack(spacing: 18) {
                    Button("Add event", systemImage: "plus", action: onAdd)
                    Button("Filters", systemImage: "line.3.horizontal.decrease", action: onSearch)
                    Button("Settings", systemImage: "gearshape") {} // TODO: settings screen
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .glassEffect(.regular.interactive(), in: .capsule)
                .fixedSize()
            }
            .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }
}
