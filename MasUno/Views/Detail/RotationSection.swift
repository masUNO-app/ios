import SwiftUI

/// A round night on Event detail: each round's time, how it's going, and your group and station
/// once they're out. After the night, everyone you played with.
struct RotationSection: View {
    @Environment(GameStore.self) private var store
    var event: Game
    var rotation: Rotation
    @State private var plan: RotationPlan?
    /// The round whose props sheet is open (1.0).
    @State private var propsFor: PropsRound?

    private struct PropsRound: Identifiable {
        var round: Int
        var station: Int
        var id: Int { round }
    }

    /// You're in this game and may see who's in your groups.
    private var isMember: Bool { event.isGoing && !event.hidesPeople }
    private var myID: UUID? { store.profile?.id }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        // Again when people come or go, and as each round's groups come out.
        .task(id: "\(event.id)-\(event.goingCount)-\(event.startsAt.timeIntervalSince1970)-\(rotation.hashValue)") {
            while !Task.isCancelled {
                plan = try? await store.rotationPlan(event.id)
                guard let next = plan?.rounds.first(where: { $0.groups == nil && $0.revealsAt > .now })?.revealsAt else { return }
                try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
            }
        }
        .sheet(item: $propsFor) { PropsSheet(gameID: event.id, round: $0.round, station: $0.station) }
    }

    /// Before the plan loads (or if it can't), the rounds' times alone.
    private var rounds: [RotationRound] {
        plan?.rounds ?? (0..<rotation.rounds).map { round in
            RotationRound(
                index: round, startsAt: rotation.start(of: round, from: event.startsAt),
                endsAt: rotation.end(of: round, from: event.startsAt),
                revealsAt: rotation.reveal(of: round, from: event.startsAt), groups: nil
            )
        }
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rounds")
                .font(.rounded(.headline, .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 6)

            if event.hasEnded(now: now), isMember, let plan, let myID {
                recap(plan.peopleMet(by: myID))
            }

            ForEach(rounds) { round in
                if round.index > 0 {
                    Text("\(rotation.breakMinutes) min break, new groups")
                        .font(.rounded(.caption))
                        .foregroundStyle(Theme.muted)
                        .padding(.leading, 14)
                }
                roundCard(round, now: now)
                if !event.isCancelled { propsButton(round, phase: phase(of: round, now: now), now: now) }
            }

            if !event.hasEnded(now: now) {
                Text("Everyone plays with up to \(rotation.mostNewPeople(players: event.capacity)) new people.")
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.mutedLarge)
            }
        }
    }

    // MARK: Rounds

    private enum Phase { case played, now, upcoming }

    private func phase(of round: RotationRound, now: Date) -> Phase {
        if now >= round.endsAt { return .played }
        return now >= round.startsAt ? .now : .upcoming
    }

    private func roundCard(_ round: RotationRound, now: Date) -> some View {
        let phase = phase(of: round, now: now)
        let isCancelled = event.isCancelled

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Round \(round.index + 1)")
                    .font(.rounded(.subheadline, .bold))
                    .foregroundStyle(Theme.ink)
                Text(verbatim: "\(EventFormat.time(round.startsAt)) – \(EventFormat.time(round.endsAt))")
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.mutedLarge)
                Spacer(minLength: 8)
                if !isCancelled { badge(phase) }
            }
            if !isCancelled { groupLine(round) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.field))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.field)
                .strokeBorder(phase == .now && !isCancelled ? Color(.sportEsports) : Theme.hairline, lineWidth: phase == .now ? 2 : 1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func badge(_ phase: Phase) -> some View {
        switch phase {
        case .played:
            Label("Played", systemImage: "checkmark")
                .labelStyle(IconRowLabelStyle(iconWidth: 12, spacing: 4))
                .font(.rounded(.caption, .bold))
                .foregroundStyle(Theme.mutedLarge)
        case .now:
            Text("Now")
                .font(.rounded(.caption, .bold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Theme.accent, in: .capsule)
        case .upcoming:
            EmptyView()
        }
    }

    /// Your group and station, "4 groups" for someone not in it, or when the groups come out.
    @ViewBuilder
    private func groupLine(_ round: RotationRound) -> some View {
        if let groups = round.groups {
            if isMember, let myID, let mine = plan?.group(of: myID, in: round) {
                HStack(spacing: 10) {
                    HStack(spacing: -6) {
                        YouToken(size: 30)
                        ForEach(mine.people) { PersonAvatar(person: $0, size: 30) }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Station \(mine.station)")
                            .font(.rounded(.footnote, .bold))
                            .foregroundStyle(Theme.ink)
                        Text(verbatim: mine.people.map(\.firstName).formatted(.list(type: .and).locale(LanguageSettings.shared.locale)))
                            .font(.rounded(.caption))
                            .foregroundStyle(Theme.mutedLarge)
                            .lineLimit(2)
                    }
                }
            } else {
                Text("\(groups.count) groups")
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.mutedLarge)
            }
        } else {
            Label {
                Text("Groups come out at \(EventFormat.time(round.revealsAt))")
            } icon: {
                Image(systemName: "shuffle")
            }
            .labelStyle(IconRowLabelStyle(iconWidth: 16, spacing: 6))
            .font(.rounded(.footnote))
            .foregroundStyle(Theme.mutedLarge)
        }
    }

    // MARK: Props

    /// After a round you played, in the break and for a day: props for your group that round.
    @ViewBuilder
    private func propsButton(_ round: RotationRound, phase: Phase, now: Date) -> some View {
        if phase == .played, now < round.endsAt.addingTimeInterval(24 * 3600), isMember, let myID,
           let mine = plan?.group(of: myID, in: round), !mine.people.isEmpty {
            Button("Give props to Station \(mine.station)", systemImage: "hand.thumbsup") {
                propsFor = PropsRound(round: round.index, station: mine.station)
            }
            .font(.rounded(.footnote, .bold))
            .foregroundStyle(Theme.accentText)
            .frame(minHeight: 44)
        }
    }

    // MARK: Recap

    /// "You played with 9 new people", their tokens and first names.
    private func recap(_ people: [PersonSummary]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You played with \(people.count) new people")
                .font(.rounded(.title3, .bold))
                .foregroundStyle(Theme.ink)
            FlowLayout(spacing: 12) {
                ForEach(people) { person in
                    VStack(spacing: 4) {
                        PersonAvatar(person: person, size: 44)
                        Text(verbatim: person.firstName)
                            .font(.rounded(.caption, .bold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    .frame(width: 58)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.sportEsports).opacity(0.22), in: .rect(cornerRadius: 20))
    }
}
