import SwiftUI

/// Settings › Blocked people (SPEC §7.6.6), with Unblock.
struct BlockedPeopleView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if store.blockedPeople.isEmpty {
                    ContentUnavailableView(
                        "No one blocked",
                        systemImage: "nosign",
                        description: Text("Block someone from a game's Who's going list.")
                    )
                    .padding(.top, 60)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(store.blockedPeople.enumerated()), id: \.element.id) { index, person in
                            if index > 0 { Theme.separator.frame(height: 1).padding(.leading, 64) }
                            HStack(spacing: 12) {
                                PersonAvatar(person: person, size: 36, ring: 0)
                                Text(verbatim: person.displayName)
                                    .font(.rounded(.body))
                                    .foregroundStyle(Theme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button("Unblock") { Task { await store.unblock(person) } }
                                    .pill(.secondary, expands: false, size: .regular)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 60)
                        }
                    }
                    .cardSurface()

                    Text("You won't see each other's games or messages, and neither of you can join the other's games.")
                        .font(.rounded(.footnote))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .readableColumn()
            .animation(.default, value: store.blockedPeople)
        }
        .background(Theme.background)
        .navigationTitle("Blocked people")
    }
}
