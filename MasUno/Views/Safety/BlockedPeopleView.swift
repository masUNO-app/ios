import SwiftUI

/// Settings › Blocked people (SPEC §7.6.6), with Unblock.
struct BlockedPeopleView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        Form {
            if store.blockedPeople.isEmpty {
                ContentUnavailableView(
                    "No one blocked",
                    systemImage: "hand.raised",
                    description: Text("Block someone from a game's Who's going list.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(store.blockedPeople) { person in
                        HStack(spacing: 12) {
                            Avatar(name: person.displayName, size: 32)
                            Text(person.displayName)
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Unblock") { Task { await store.unblock(person) } }
                                .buttonStyle(.glassProminent)
                                .tint(Theme.accentSoft)
                                .foregroundStyle(Theme.ink)
                        }
                    }
                } footer: {
                    Text("You won't see each other's games or names, and neither of you can join the other's games.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Blocked people")
    }
}
