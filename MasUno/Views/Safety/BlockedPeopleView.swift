import SwiftUI

/// Settings › Blocked people (SPEC §7.6.6), with Unblock.
struct BlockedPeopleView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if store.blockedPeople.isEmpty {
                    ContentUnavailableView(
                        "No one blocked",
                        systemImage: "nosign",
                        description: Text("Block someone from a plan's Who's going list.")
                    )
                    .padding(.top, 60)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(store.blockedPeople.enumerated()), id: \.element.id) { index, person in
                            if index > 0 { RowDivider().padding(.leading, 64) }
                            // Unblock goes under the name at accessibility sizes (A11Y-06).
                            rowLayout {
                                HStack(spacing: 12) {
                                    PersonAvatar(person: person, size: 36, ring: 0)
                                    Text(verbatim: person.displayName)
                                        .font(.rounded(.body))
                                        .foregroundStyle(Theme.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Button("Unblock") { Task { await store.unblock(person) } }
                                    .pill(.secondary, expands: false, size: .regular)
                                    .accessibilityLabel(String.app("Unblock \(person.displayName)"))
                                    .accessibilityInputLabels([Text("Unblock")])
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, typeSize.isAccessibilitySize ? 12 : 0)
                            .frame(minHeight: 60)
                        }
                    }
                    .cardSurface()

                    Text("You won't see each other's plans or messages, and neither of you can join the other's plans.")
                        .font(.rounded(.footnote))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .readableColumn(alignment: .leading)
            .animation(.default, value: store.blockedPeople)
        }
        .background(Theme.background)
        .navigationTitle(String.app("Blocked people"))
    }

    private var rowLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
    }
}
