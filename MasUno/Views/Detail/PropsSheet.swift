import SwiftUI

/// Props after a plan, or after one round of a round night (design canvas "After the game: props &
/// leaderboard", screens 1 and 5). Each person you played with, the four props as toggles, then Send.
/// They see the props, never who sent them. Problems go to Report, not here.
struct PropsSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var gameID: UUID
    /// A round night's round (from 0); nil for a whole plan.
    var round: Int?
    /// "Station 3", for a round's title.
    var station: Int?

    @State private var props: PropsToGive?
    @State private var picks: [UUID: Set<Prop>] = [:]
    @State private var showsEveryone = false
    @State private var isSending = false
    @State private var error: String?
    @State private var reportsPlan = false

    /// Three people before "Show N more", like the design.
    private let firstShown = 3

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SheetHeader(title: title, subtitle: nil) { dismiss() }
                if let props {
                    if props.isOpen, !props.people.isEmpty {
                        content(props)
                    } else {
                        Text(props.isOpen ? "Nobody to give props to." : "Props for this plan are closed.")
                            .font(.rounded(.body))
                            .foregroundStyle(Theme.mutedLarge)
                    }
                } else if let error {
                    RetryCard(message: LocalizedStringKey(error)) { await load() }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 26)
            .padding(.bottom, 24)
        }
        .task { await load() }
        .sheetChrome(detents: [.large], background: Theme.card)
        .sheet(isPresented: $reportsPlan) { ReportSheet(target: .game(gameID)) }
    }

    private var title: Text {
        if let station { return Text("Props for Station \(station)?") }
        return round == nil ? Text("How did it go?") : Text("Props for this round?")
    }

    private func content(_ props: PropsToGive) -> some View {
        let shown = showsEveryone ? props.people : Array(props.people.prefix(firstShown))
        let hidden = props.people.count - shown.count

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                if let closes = props.closesAt {
                    Text("Open until \(EventFormat.dayAndTime(closes))")
                        .font(.rounded(.footnote))
                        .foregroundStyle(Theme.mutedLarge)
                }
                Text(round == nil
                     ? "Give props to anyone who earned them. They see the props, not who sent them."
                     : "Same props as any plan, while your group is fresh. Skip anyone.")
                    .font(.rounded(.callout))
                    .foregroundStyle(Theme.mutedLarge)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(shown) { peer in
                    personRow(peer)
                    RowDivider()
                }
                if hidden > 0 {
                    Button("Show \(hidden) more people") { withAnimation(.snappy) { showsEveryone = true } }
                        .font(.rounded(.callout, .bold))
                        .foregroundStyle(Theme.accentText)
                        .frame(minHeight: 44)
                }
            }

            if let error {
                Text(verbatim: error)
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.error)
            }

            VStack(spacing: 10) {
                WorkingButton(verbatim: sendTitle, isWorking: isSending) { Task { await send() } }
                    .disabled(changes.isEmpty)
                Button("Not now") { dismiss() }
                    .pill(.secondary)
                Button {
                    reportsPlan = true
                } label: {
                    Text("Something wrong? **Report it** instead. Only the team sees reports.")
                        .font(.rounded(.footnote))
                        .foregroundStyle(Theme.mutedLarge)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func personRow(_ peer: PropsPeer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PersonAvatar(person: peer.person, size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: peer.person.firstName)
                        .font(.rounded(.callout, .bold))
                        .foregroundStyle(Theme.ink)
                    Text(verbatim: meta(peer))
                        .font(.rounded(.footnote))
                        .foregroundStyle(Theme.mutedLarge)
                }
            }
            .accessibilityElement(children: .combine)
            FlowLayout(spacing: 6) {
                ForEach(Prop.allCases) { prop in
                    PropToggle(prop: prop, isOn: picks[peer.id, default: []].contains(prop)) {
                        picks[peer.id, default: []].formSymmetricDifference([prop])
                    }
                    .accessibilityHint(Text("For \(peer.person.firstName)"))
                }
            }
        }
        .padding(.vertical, 14)
    }

    /// "Host", "First time playing together", "Played together 3 times".
    private func meta(_ peer: PropsPeer) -> String {
        if peer.isHost { return String.app("Host") }
        if peer.playedBefore == 0 { return String.app("First time playing together") }
        return String.app("Played together \(peer.playedBefore + 1) times")
    }

    /// People whose props differ from what was already sent.
    private var changes: [UUID: Set<Prop>] {
        guard let props else { return [:] }
        return props.people.reduce(into: [:]) { changes, peer in
            let picked = picks[peer.id, default: []]
            if picked != peer.sent { changes[peer.id] = picked }
        }
    }

    private var sendTitle: String {
        let count = picks.values.map(\.count).reduce(0, +)
        switch count {
        case 0: return String.app("Send props")
        case 1: return String.app("Send 1 prop")
        default: return String.app("Send \(count) props")
        }
    }

    private func load() async {
        error = nil
        do {
            let loaded = try await store.propsToGive(gameID, round: round)
            props = loaded
            picks = Dictionary(uniqueKeysWithValues: loaded.people.map { ($0.id, $0.sent) })
        } catch {
            self.error = (error as? DomainError)?.message ?? DomainError.unknown("").message
        }
    }

    private func send() async {
        let changes = changes
        guard !changes.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await store.giveProps(gameID, round: round, changes)
            store.notice = String.app("Props sent")
            dismiss()
        } catch {
            self.error = (error as? DomainError)?.message ?? DomainError.unknown("").message
        }
    }
}

/// One prop as a toggle: green with a check when on, plain when off.
struct PropToggle: View {
    var prop: Prop
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.rounded(.caption, .bold))
                        .accessibilityHidden(true)
                }
                Text(verbatim: prop.name)
            }
            .font(.rounded(.footnote, .bold))
            .foregroundStyle(isOn ? Theme.onAccent : Theme.ink)
            .padding(.horizontal, 13)
            .frame(minHeight: 36)
            .background(isOn ? Theme.accent : Theme.card, in: .capsule)
            .overlay { Capsule().strokeBorder(isOn ? Theme.accent : Theme.hairline, lineWidth: 1.5) }
            .tapTarget(.vertical, 4)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
