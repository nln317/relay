import RelayGames
import RelayUI
import SwiftUI

/// Companion app home. Milestone 1 scope: explain how to play in Messages and
/// offer offline practice. Locker, store, stats and profile come later.
struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Relay")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(RelayTheme.textPrimary)
                        Text("Quick games with friends, right in Messages.")
                            .foregroundStyle(RelayTheme.textSecondary)
                    }

                    HowToPlayCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Practice")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(RelayTheme.textPrimary)
                        ForEach(PracticeOpponent.allCases) { opponent in
                            NavigationLink(value: opponent) {
                                PracticeRow(opponent: opponent)
                            }
                            .buttonStyle(PressableStyle())
                        }
                        ForEach(DartsPracticeOpponent.allCases) { opponent in
                            NavigationLink(value: opponent) {
                                PracticeRow(opponent: opponent)
                            }
                            .buttonStyle(PressableStyle())
                        }
                        ForEach(EightBallPracticeOpponent.allCases) { opponent in
                            NavigationLink(value: opponent) {
                                PracticeRow(opponent: opponent)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }

                    #if DEBUG
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Developer")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(RelayTheme.textPrimary)
                        NavigationLink {
                            RehearsalView()
                        } label: {
                            Label("Two-phone rehearsal", systemImage: "iphone.gen3.radiowaves.left.and.right")
                                .font(.headline)
                                .foregroundStyle(RelayTheme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(RelayTheme.surface))
                        }
                        .accessibilityIdentifier("home.rehearsal")
                    }
                    #endif
                }
                .padding(20)
            }
            .background(RelayTheme.background.ignoresSafeArea())
            .navigationDestination(for: PracticeOpponent.self) { opponent in
                PracticeView(opponent: opponent)
            }
            .navigationDestination(for: DartsPracticeOpponent.self) { opponent in
                DartsPracticeView(opponent: opponent)
            }
            .navigationDestination(for: EightBallPracticeOpponent.self) { opponent in
                EightBallPracticeView(opponent: opponent)
            }
        }
    }
}

struct HowToPlayCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Play in Messages")
                .font(.headline)
                .foregroundStyle(RelayTheme.textPrimary)
            step(1, "Open a conversation, tap +, then Relay. Scroll down the list if you don't see it.")
            step(2, "Pick a game and make your first move.")
            step(3, "Tap send. Your friend taps the bubble to reply.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(RelayTheme.surface))
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(RelayTheme.accent)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(RelayTheme.textSecondary)
        }
    }
}

struct PracticeRow<Option: PracticeOption>: View {
    let opponent: Option
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 36

    var body: some View {
        HStack {
            // At accessibility sizes the icon sits above the text so neither is squeezed.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    icon
                    labels
                }
            } else {
                icon.frame(width: iconWidth)
                labels
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").foregroundStyle(RelayTheme.textSecondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(RelayTheme.surface))
    }

    private var icon: some View {
        Image(systemName: opponent.symbol)
            .font(.title3)
            .foregroundStyle(RelayTheme.accent)
            .accessibilityHidden(true)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(opponent.title)
                .font(.headline)
                .foregroundStyle(RelayTheme.textPrimary)
            Text(opponent.subtitle)
                .font(.footnote)
                .foregroundStyle(RelayTheme.textSecondary)
        }
    }
}
