import SwiftUI

/// "Top teammates" (design canvas, screen 4): your campus's people with the most props this month,
/// by how many different people gave them, for one prop and one sport (or esports). Only people who
/// opted in are listed; your own standing shows at the bottom either way.
struct LeaderboardView: View {
    @Environment(GameStore.self) private var store

    @State private var prop: Prop = .goodSport
    /// Nil for all; an activity slug, or a kind ("esports").
    @State private var filter: String?
    @State private var board: PropsLeaderboard?
    @State private var error: String?
    @State private var isSavingOptIn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Picker("Prop", selection: $prop) {
                    ForEach(Prop.allCases) { Text(verbatim: $0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                filters

                if let board {
                    if board.top.isEmpty {
                        Text("No one's on the list for this yet. Props from this month show up here.")
                            .font(.rounded(.callout))
                            .foregroundStyle(Theme.mutedLarge)
                            .padding(.vertical, 24)
                    } else {
                        list(board)
                    }
                    you(board)
                } else if let error {
                    RetryCard(message: LocalizedStringKey(error)) { await load() }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: Theme.columnWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Top teammates")
        .navigationBarTitleDisplayMode(.large)
        .task(id: "\(prop.rawValue)-\(filter ?? "")") { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        Text(verbatim: subtitle)
            .font(.rounded(.subheadline))
            .foregroundStyle(Theme.mutedLarge)
    }

    /// "Tec · November · resets Dec 1".
    private var subtitle: String {
        var parts: [String] = []
        if let campus = store.campus?.shortName { parts.append(campus) }
        if let board {
            let locale = LanguageSettings.shared.locale
            parts.append(board.month.formatted(.dateTime.month(.wide).locale(locale)).capitalized(with: locale))
            parts.append(String.app("resets \(board.resetsAt.formatted(.dateTime.month(.abbreviated).day().locale(locale)))"))
        }
        return parts.joined(separator: " · ")
    }

    /// All, each sport, and esports as one.
    private var filters: some View {
        let sports = store.activities.filter { $0.active && $0.kind == Activity.sportKind }.sorted { $0.sortOrder < $1.sortOrder }
        let kinds = store.activityCatalog.kinds.filter { $0.active && $0.slug != Activity.sportKind }

        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                // The light mint in both modes: like the sport colors, it's a pastel under ink. Dark
                // mode's accentSoft is a deep green, and ink on it was unreadable.
                filterChip(String.app("All"), color: Color(Theme.accentSoft.resolve(in: EnvironmentValues())), showsDot: false, value: nil)
                ForEach(sports) { filterChip($0.name, color: $0.color, value: $0.slug) }
                ForEach(kinds) { filterChip($0.name, color: Color(.sportEsports), value: $0.slug) }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    /// Liquid Glass like `SportToggle`: plain when off, tinted with its color when on.
    private func filterChip(_ title: String, color: Color, showsDot: Bool = true, value: String?) -> some View {
        let isOn = filter == value
        return Button {
            filter = value
        } label: {
            HStack(spacing: 6) {
                if showsDot {
                    Circle().fill(color).frame(width: 9, height: 9)
                        .overlay { Circle().strokeBorder(Theme.ink.opacity(0.15)) }
                        .accessibilityHidden(true)
                }
                Text(verbatim: title)
            }
            .font(.rounded(.footnote, .bold))
            .foregroundStyle(Theme.ink)
            .inkOnColor(isOn)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .appGlass(in: .capsule, tint: isOn ? color : nil, interactive: true)
            .tapTarget(.vertical, 6)
        }
        .buttonStyle(.plain)
        .padding(.vertical, -6)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func list(_ board: PropsLeaderboard) -> some View {
        VStack(spacing: 0) {
            ForEach(board.top) { entry in
                HStack(spacing: 12) {
                    Text(verbatim: "\(entry.rank)")
                        .font(.rounded(.callout, .bold))
                        .foregroundStyle(entry.rank <= 3 ? Theme.accentText : Theme.mutedLarge)
                        .frame(minWidth: 26, alignment: .trailing)
                    PersonAvatar(person: entry.person, size: entry.rank <= 3 ? 42 : 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: entry.person.displayName)
                            .font(.rounded(.callout, .bold))
                            .foregroundStyle(Theme.ink)
                        if let mostly = entry.mostly {
                            Text("Mostly \(store.activityCatalog.activity(slug: mostly)?.name ?? mostly)")
                                .font(.rounded(.caption))
                                .foregroundStyle(Theme.mutedLarge)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(verbatim: "\(entry.people)")
                        .font(.rounded(.callout, .bold))
                        .foregroundStyle(Theme.ink)
                }
                .frame(minHeight: 56)
                .padding(.horizontal, 14)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: String.app("\(entry.rank). \(entry.person.displayName), from \(entry.people) people")))
                if entry.id != board.top.last?.id { RowDivider().padding(.leading, 14) }
            }
        }
        .padding(.vertical, 4)
        .cardSurface()
    }

    /// Your standing, and the switch to be listed.
    private func you(_ board: PropsLeaderboard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(verbatim: board.myRank.map { "#\($0)" } ?? "–")
                    .font(.rounded(.headline, .bold))
                    .frame(minWidth: 34, alignment: .leading)
                if let profile = store.profile { MeToken(name: profile.fullName, size: 38) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(board.myPeople == 1 ? "You · 1 person" : "You · \(board.myPeople) people")
                        .font(.rounded(.callout, .bold))
                    if let needed = board.neededForTopTen {
                        Text(needed == 1 ? "1 more for the top 10" : "\(needed) more for the top 10")
                            .font(.rounded(.footnote))
                    } else if !board.isOptedIn {
                        Text("Only you see this")
                            .font(.rounded(.footnote))
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.onAccent)
            .accessibilityElement(children: .combine)

            if !board.isOptedIn {
                Button(isSavingOptIn ? String.app("Working") : String.app("Show me on the leaderboard")) {
                    Task { await optIn() }
                }
                .pill(.secondary)
                .disabled(isSavingOptIn)
            }
        }
        .padding(16)
        .background(Theme.accent, in: .rect(cornerRadius: Theme.Radius.card))
    }

    private func load() async {
        error = nil
        do {
            board = try await store.propsLeaderboard(prop: prop, filter: filter)
        } catch {
            board = nil
            self.error = (error as? DomainError)?.message ?? DomainError.unknown("").message
        }
    }

    private func optIn() async {
        isSavingOptIn = true
        defer { isSavingOptIn = false }
        do {
            try await store.setPropsLeaderboardOptIn(true)
            await load()
        } catch {
            store.notice = (error as? DomainError)?.message ?? DomainError.unknown("").message
        }
    }
}
