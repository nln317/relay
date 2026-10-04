#if canImport(UIKit)
import RelayCore
import RelayGames
import RelayMessages
import SwiftUI

/// "Choose something to play." One tap from opening the drawer to a board.
/// Only playable games are listed; there is no "coming soon" filler.
public struct GamePickerView: View {
    let games: [GameDefinition]
    let onSelect: (GameDefinition) -> Void

    public init(games: [GameDefinition] = GameCatalog.playable, onSelect: @escaping (GameDefinition) -> Void) {
        self.games = games
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pick a game")
                    .font(.headline)
                    .foregroundStyle(RelayTheme.textSecondary)
                    .padding(.horizontal, 4)
                ForEach(games) { game in
                    Button {
                        onSelect(game)
                    } label: {
                        GameTile(game: game)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityHint("Starts a new game in this conversation")
                }
            }
            .padding(16)
        }
        .background(RelayTheme.background)
    }
}

struct GameTile: View {
    let game: GameDefinition

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(RelayTheme.board)
                if game.id == Darts.gameID {
                    DartsBoardView(darts: [], animatesDarts: false).padding(5)
                } else {
                    HStack(spacing: 3) {
                        DiscView(seat: .one).frame(width: 18, height: 18)
                        DiscView(seat: .two).frame(width: 18, height: 18)
                    }
                }
            }
            .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(game.displayName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(RelayTheme.textPrimary)
                Text(game.tagline)
                    .font(.subheadline)
                    .foregroundStyle(RelayTheme.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(RelayTheme.textSecondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(RelayTheme.surface))
        .accessibilityElement(children: .combine)
    }
}

/// Slight press-down for every primary control: cheap, consistent tactility.
public struct PressableStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(RelayTheme.accent))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Chunky yellow game button with dark capitals, for the darts table.
public struct GameButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .black, design: .rounded))
            .textCase(.uppercase)
            .foregroundStyle(Color(white: 0.08))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Capsule().fill(Color(red: 1.0, green: 0.86, blue: 0.1)))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// "You (Red) vs Them (Yellow)" with whose turn it is.
public struct PlayersHeader: View {
    let localSeat: Seat?
    let toAct: Seat?
    let series: SeriesTally
    @Environment(\.seatPalette) private var palette

    public init(localSeat: Seat?, toAct: Seat?, series: SeriesTally) {
        self.localSeat = localSeat
        self.toAct = toAct
        self.series = series
    }

    public var body: some View {
        HStack {
            player(.one)
            Spacer()
            if series.gamesPlayed > 0 {
                Text("\(series.seatOneWins) – \(series.seatTwoWins)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(RelayTheme.textSecondary)
                    .accessibilityLabel(seriesLabel)
            }
            Spacer()
            player(.two)
        }
    }

    private func name(_ seat: Seat) -> String {
        guard let localSeat else { return palette.name(seat) }
        return seat == localSeat ? "You" : "Them"
    }

    private var seriesLabel: String {
        guard let localSeat else { return "Record \(series.seatOneWins) to \(series.seatTwoWins)" }
        return "Record: you \(series.wins(for: localSeat)), them \(series.wins(for: localSeat.opponent))"
    }

    private func player(_ seat: Seat) -> some View {
        HStack(spacing: 8) {
            DiscView(seat: seat).frame(width: 22, height: 22)
            Text(name(seat))
                .font(.subheadline.weight(toAct == seat ? .bold : .regular))
                .foregroundStyle(toAct == seat ? RelayTheme.textPrimary : RelayTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(toAct == seat ? palette.colour(seat).opacity(0.22) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.2), value: toAct)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(toAct == seat ? .isSelected : [])
    }
}

/// Friendly, specific explanation for a message that cannot be opened.
public struct ProblemView: View {
    let error: ProtocolError
    let onNewGame: (() -> Void)?

    public init(error: ProtocolError, onNewGame: (() -> Void)? = nil) {
        self.error = error
        self.onNewGame = onNewGame
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: error.isFixedByUpdating ? "arrow.down.app" : "exclamationmark.bubble")
                .font(.system(size: 40))
                .foregroundStyle(RelayTheme.accent)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(RelayTheme.textPrimary)
            Text(detail)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(RelayTheme.textSecondary)
            // Updating is the fix for newer messages; anything else, offer a fresh start.
            if let onNewGame, !error.isFixedByUpdating {
                Button("New game", action: onNewGame)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RelayTheme.background)
    }

    private var title: String {
        error.isFixedByUpdating ? "Update to play this" : "This game can't be opened"
    }

    private var detail: String {
        switch error {
        case .unknownGame:
            "Your friend is playing a game that this version doesn't have yet. Update the app from the App Store."
        case .unsupportedProtocolVersion, .unsupportedRulesVersion:
            "This message was sent from a newer version. Update the app from the App Store."
        case .obsoleteProtocolVersion:
            "This message is from an old version that is no longer supported. Start a new game instead."
        case .notARelayMessage:
            "This message wasn't created by this app."
        case .illegalHistory:
            "The moves in this message don't follow the rules, so it may have been damaged. Start a new game instead."
        case .missingField, .oversized, .malformedPayload, .inconsistentHeader:
            "This message looks damaged. Start a new game instead."
        }
    }
}
#endif
