import SwiftUI

/// Figma "Reimagined · J3 · You're in" (513:6629): the pretend plan's court, where you land as
/// you take the spot, and what this screen holds on the day.
struct PracticeJoinedStep: View {
    var viewModel: OnboardingViewModel
    /// Your spot stays open for a moment, so you're seen arriving and the others hop.
    @State private var holdsYou = true

    var body: some View {
        let sport = viewModel.practiceSport
        let capacity = PracticeRound.capacity(for: sport)
        let people = PracticeRound.joinPeople + [PracticeRound.you]
        let lineup = Lineup(people: people, open: capacity - people.count, myID: PracticeRound.you.id)

        CourtPage(activity: sport, lineup: lineup, capacity: capacity, holdsYou: holdsYou) {
            VStack(alignment: .leading, spacing: 12) {
                StepTag(text: Text("Step 3 of 3 · Done"))
                Text("That's it. You're in!")
                    .font(.rounded(.largeTitle, .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("\(PracticeRound.alex.firstName) can see you joined. Everything you need for the plan lives on this screen:")
                    .font(.rounded(.body))
                    .foregroundStyle(Theme.muted)
                VStack(alignment: .leading, spacing: 12) {
                    GuideRow(systemImage: "clock", tint: Color(.person1), title: Text("When and where"), subtitle: Text("Tap the address for directions"))
                    GuideRow(systemImage: "person.2", tint: Color(.person2), title: Text("Who's going"), subtitle: Text("Tap anyone to report or block them"))
                    GuideRow(systemImage: "bubble.left", tint: Color(.person7), title: Text("Group chat"), subtitle: Text("Say hi, or ask what to bring"))
                }
                .padding(.top, 2)
                PracticeNote(text: Text("This was a practice plan, so nobody's waiting on you."))
            }
        } footer: {
            VStack(spacing: 10) {
                Button("Make it official") { viewModel.makeItOfficial() }
                    .pill(.primary)
                Button("Try hosting a plan too") { viewModel.tryOtherPractice(.host) }
                    .pill(.quiet)
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            holdsYou = false
            Announce.post(String.app("You're in"))
        }
    }
}

/// Figma "Reimagined · C6 · You're all set" (513:7744): you on the court, the two ways to play,
/// and your invite code to share. Go to the map lets the map in.
struct AllSetStep: View {
    @Environment(GameStore.self) private var store
    var viewModel: OnboardingViewModel
    @State private var holdsYou = true

    var body: some View {
        let sport = viewModel.picks.first ?? viewModel.interests.sorted { $0.sortOrder < $1.sortOrder }.first ?? Activity.builtIn[0]
        let capacity = PracticeRound.capacity(for: sport)
        let people = PracticeRound.joinPeople + [PracticeRound.you]
        let lineup = Lineup(people: people, open: capacity - people.count, myID: PracticeRound.you.id)

        CourtPage(activity: sport, lineup: lineup, capacity: capacity, holdsYou: holdsYou) {
            VStack(alignment: .leading, spacing: 14) {
                Text(verbatim: viewModel.allSetTitle)
                    .font(.rounded(.largeTitle, .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Two ways to play. Do either one, anytime, right from the map.")
                    .font(.rounded(.callout, .bold))
                    .foregroundStyle(Theme.mutedLarge)

                VStack(alignment: .leading, spacing: 18) {
                    GuideRow(
                        icon: { PlaceIcon(size: 22).foregroundStyle(.white) }, tint: Color(.sportBasketball), solid: true,
                        title: Text("Join a plan"), subtitle: Text("Tap any pin, then Count me in")
                    )
                    GuideRow(
                        icon: { Image(systemName: "plus").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.onAccent) },
                        tint: Theme.accent, solid: true,
                        title: Text("Host a plan"), subtitle: Text("Tap Make a plan at the bottom of the map")
                    )
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()

                if let invite = store.invites.first(where: { !$0.isUsed }) {
                    CrewCard(invite: invite)
                }
            }
        } footer: {
            Button("Go to the map") { viewModel.finishOnboarding() }
                .pill(.primary)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.loadInvites() }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            holdsYou = false
        }
    }
}

/// "Bring your crew": friends skip the waitlist with your invite code.
private struct CrewCard: View {
    var invite: Invite

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 44, height: 44)
                .background(Theme.accent, in: .rect(cornerRadius: Theme.Radius.tile))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bring your crew")
                    .font(.rounded(.headline, .bold))
                    .foregroundStyle(Theme.ink)
                Text("Friends skip the waitlist with your invite code")
                    .font(.rounded(.footnote))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ShareLink(item: shareMessage) {
                Text("Share")
                    .font(.rounded(.callout, .bold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 40)
                    .background(Theme.accent, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Share invite code"))
        }
        .padding(16)
        .background(Theme.accentSoft, in: .rect(cornerRadius: Theme.Radius.card))
    }

    /// The same message as Me › Invites.
    private var shareMessage: String {
        let message = String.app("Skip the masUNO waitlist with my invite code \(invite.displayCode)")
        guard let url = AppConfig.inviteURL else { return message + "." }
        return message + ": " + url.absoluteString
    }
}

/// A tinted square with a symbol, a title and a line: what's where, on J3 and You're all set.
private struct GuideRow<Icon: View>: View {
    @ViewBuilder var icon: Icon
    var tint: Color
    /// Filled with the tint instead of a soft wash of it.
    var solid = false
    var title: Text
    var subtitle: Text

    var body: some View {
        HStack(spacing: 14) {
            icon
                .frame(width: 44, height: 44)
                .background { RoundedRectangle(cornerRadius: Theme.Radius.tile).fill(tint.opacity(solid ? 1 : 0.4)) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.rounded(.headline, .bold))
                    .foregroundStyle(Theme.ink)
                subtitle
                    .font(.rounded(.subheadline))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension GuideRow where Icon == AnyView {
    /// A symbol in ink on a soft wash.
    init(systemImage: String, tint: Color, title: Text, subtitle: Text) {
        self.init(
            icon: { AnyView(Image(systemName: systemImage).font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.ink)) },
            tint: tint, title: title, subtitle: subtitle
        )
    }
}

/// A court at the top, its content as the sheet, and a pinned bottom action (J3, You're all set).
/// When the sheet runs on under the buttons, a hint says there's more.
/// The court is only a picture: no taps, hidden from VoiceOver.
struct CourtPage<Content: View, Footer: View>: View {
    var activity: Activity
    var lineup: Lineup
    var capacity: Int
    var holdsYou = false
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    @Environment(\.dynamicTypeSize) private var typeSize
    /// Where the content and the shown part of the screen end, for `MoreBelowHint`.
    @State private var contentBottom: CGFloat = 0
    @State private var scrollBottom: CGFloat = .infinity
    @State private var footerTop: CGFloat = .infinity
    @State private var scroll = ScrollPosition(edge: .top)

    /// The content runs on under the pinned buttons (or off the screen at accessibility sizes).
    private var hasMore: Bool {
        MoreBelowHint.isNeeded(
            contentBottom: contentBottom,
            shownBottom: typeSize.isAccessibilitySize ? scrollBottom : min(scrollBottom, footerTop)
        )
    }

    var body: some View {
        CourtScaffold(activity: activity, lineup: lineup, capacity: capacity, holdsYou: holdsYou) {
            VStack(alignment: .leading, spacing: 0) {
                content
                // After the text at accessibility sizes, as on `OnboardingPage` (A11Y-06).
                if typeSize.isAccessibilitySize { footer.padding(.top, 18) }
            }
            .reportsBottom($contentBottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollPosition($scroll)
        .reportsBottom($scrollBottom)
        .animation(.easeOut(duration: 0.2), value: hasMore)
        .overlay(alignment: .bottom) {
            if typeSize.isAccessibilitySize, hasMore { MoreBelowHint(scrollToEnd: scrollToEnd) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !typeSize.isAccessibilitySize {
                footer
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .readableColumn()
                    .background(Theme.background)
                    .reportsTop($footerTop)
                    .moreBelowHint(isShown: hasMore, scrollToEnd: scrollToEnd)
            }
        }
    }

    private func scrollToEnd() {
        withAnimation(.snappy) { scroll.scrollTo(edge: .bottom) }
    }
}
