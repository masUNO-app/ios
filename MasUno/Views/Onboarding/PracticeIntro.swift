import SwiftUI

/// Figma "Reimagined · S · What do you play?" (513:7173): a tile per activity, in its color once
/// picked. The first pick is the practice round's.
struct SportsStep: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    var viewModel: OnboardingViewModel

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2)

        OnboardingPage(title: "What do you play?", message: "Pick as many as you like. We'll use your first pick for a quick practice round.") {
            LazyVGrid(columns: columns, spacing: 12) {
                // The server's catalog, so an activity added there can be picked here.
                ForEach(store.interestActivities) { sport in
                    SportTile(sport: sport, isOn: viewModel.picks.contains(sport)) { viewModel.togglePick(sport) }
                }
            }
            .task { await store.loadCatalogIfNeeded() }
        } footer: {
            Button("Continue") { viewModel.continueFromSports() }
                .pill(.primary)
                .disabled(viewModel.picks.isEmpty)
        }
        .toolbar {
            ToolbarItem(placement: .principal) { OnboardingProgress(step: 1) }
        }
    }
}

/// Figma "Reimagined · P · Pick your practice round" (513:7246): join someone's plan or make your
/// own, with a pretend one, or skip straight to the account.
struct StartStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingPage(title: "How do you want to start?", message: "Try one with a pretend plan first. You can do both anytime from the map.") {
            ChoiceCard(
                title: "Join a plan", message: "Find a plan that's one or two people short and take the open spot.",
                isOn: viewModel.practiceMode == .join
            ) {
                viewModel.practiceMode = .join
            } art: {
                JoinArt(sport: viewModel.practiceSport)
            }
            ChoiceCard(
                title: "Host a plan", message: "Short on people? Post your plan and let people nearby come to you.",
                isOn: viewModel.practiceMode == .host
            ) {
                viewModel.practiceMode = .host
            } art: {
                HostArt()
            }
        } footer: {
            VStack(spacing: 4) {
                Button("Start practice round") { viewModel.startPractice() }
                    .pill(.primary)
                Button { viewModel.skipTour() } label: {
                    Text("Skip the tour").tapTarget(.vertical, 12)
                }
                .font(.rounded(.callout, .bold))
                .foregroundStyle(Theme.mutedLarge)
                .buttonStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) { OnboardingProgress(step: 2) }
        }
    }
}

// MARK: - Pieces

/// Three bars across the top of What do you play? and How do you want to start?, the third
/// being the practice round.
struct OnboardingProgress: View {
    var step: Int
    var steps = 3

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...steps, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Theme.accent : Theme.separator)
                    .frame(height: 6)
            }
        }
        .frame(width: 220)
        // Read as "Step 1 of 3"; 44 pt tall, as everything in the bar is (A11Y-19).
        .frame(height: 44)
        .contentShape(.rect)
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(step) of \(steps)"))
    }
}

/// "Step 1 of 3", "Step 3 of 3 · Done": a mint tag on the practice round's cards.
struct StepTag: View {
    var text: Text

    var body: some View {
        text
            .font(.rounded(.subheadline, .bold))
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.accentSoft, in: .capsule)
    }
}

/// An activity on What do you play?: plain white with a dot of its color, or filled with its color
/// and a court line once picked.
private struct SportTile: View {
    var sport: Activity
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Text(sport.emoji)
                        .font(.system(size: 30))
                        .accessibilityHidden(true)
                    Spacer(minLength: 4)
                    indicator
                }
                Text(sport.name)
                    .font(.rounded(.title3, .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background { background }
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(isOn ? .clear : Theme.hairline)
            }
            .inkOnColor(isOn)
            .contentShape(.rect(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .animation(.snappy, value: isOn)
    }

    @ViewBuilder
    private var indicator: some View {
        if isOn {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.accent)
                .frame(width: 26, height: 26)
                .background(.white, in: .circle)
                .accessibilityHidden(true)
        } else {
            Circle()
                .fill(sport.color)
                .frame(width: 13, height: 13)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var background: some View {
        if isOn {
            sport.color
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .strokeBorder(.white.opacity(0.35), lineWidth: 2)
                        .frame(width: 110, height: 110)
                        .offset(x: 34, y: 46)
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.white.opacity(0.35))
                        .frame(height: 2)
                        .padding(.bottom, 12)
                }
        } else {
            Theme.card
        }
    }
}

/// One of the two ways to start: a picture strip over a title and a line, with a radio.
private struct ChoiceCard<Art: View>: View {
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    var isOn: Bool
    var action: () -> Void
    @ViewBuilder var art: Art

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                art
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .clipped()
                    .accessibilityHidden(true)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.rounded(.title3, .bold))
                            .foregroundStyle(Theme.ink)
                        Text(message)
                            .font(.rounded(.subheadline))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    radio
                }
                .padding(18)
            }
            .background(Theme.card)
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(isOn ? Theme.accent : Theme.hairline, lineWidth: isOn ? 2.5 : 1)
            }
            .contentShape(.rect(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .animation(.snappy, value: isOn)
    }

    @ViewBuilder
    private var radio: some View {
        if isOn {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 28, height: 28)
                .background(Theme.accent, in: .circle)
        } else {
            Circle()
                .strokeBorder(Theme.muted.opacity(0.5), lineWidth: 2)
                .frame(width: 28, height: 28)
        }
    }
}

/// A strip of court in the practice sport's color, with Alex, Ricardo and two open spots.
private struct JoinArt: View {
    var sport: Activity

    var body: some View {
        ZStack {
            sport.color
            Rectangle()
                .fill(.white.opacity(0.4))
                .frame(height: 2)
            Circle()
                .strokeBorder(.white.opacity(0.4), lineWidth: 2)
                .frame(width: 76, height: 76)
                .offset(y: 26)
            HStack(spacing: -4) {
                PersonAvatar(person: PracticeRound.alex, size: 34)
                PersonAvatar(person: PracticeRound.ricardo, size: 34)
                OpenSpotToken(size: 34, fillOpacity: 0.7)
                OpenSpotToken(size: 34, fillOpacity: 0.7)
            }
        }
        .inkOnColor()
    }
}

/// The mint strip of Make a plan: the button on the map, you, and the spots you'd open.
private struct HostArt: View {
    var body: some View {
        ZStack {
            Theme.accentSoft
            HStack(spacing: 14) {
                Label("Make a plan", systemImage: "plus")
                    .labelStyle(IconRowLabelStyle(iconWidth: 14, spacing: 6))
                    .font(.rounded(.subheadline, .bold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Theme.accent, in: .capsule)
                HStack(spacing: -4) {
                    YouToken(size: 32)
                    OpenSpotToken(size: 32, fillOpacity: 0.7)
                    OpenSpotToken(size: 32, fillOpacity: 0.7)
                }
            }
        }
    }
}
