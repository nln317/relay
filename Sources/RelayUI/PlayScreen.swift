#if canImport(UIKit)
import RelayCore
import RelayGames
import RelayMessages
import SwiftUI

/// The in-conversation game screen for one resolved `PlaySession`.
public struct PlayScreen: View {
    let session: PlaySession
    let onColumn: (Int) -> Void
    let onRematch: () -> Void
    let onNewGame: () -> Void

    public init(session: PlaySession, onColumn: @escaping (Int) -> Void, onRematch: @escaping () -> Void, onNewGame: @escaping () -> Void) {
        self.session = session
        self.onColumn = onColumn
        self.onRematch = onRematch
        self.onNewGame = onNewGame
    }

    public var body: some View {
        switch session.snapshot {
        case .fourInARow(let snapshot):
            content(snapshot.match)
        }
    }

    private func content(_ match: Match<FourInARow>) -> some View {
        VStack(spacing: 14) {
            PlayersHeader(localSeat: session.localSeat, toAct: match.outcome.seatToAct, series: match.header.series)

            ForEach(Array(session.notices.enumerated()), id: \.offset) { _, notice in
                NoticeBanner(notice: notice)
            }

            FourInARowBoardView(
                state: match.state,
                ghost: ghost(for: match),
                isInteractive: session.canMove,
                animatesLastMove: true,
                onColumnTap: onColumn
            )
            .padding(.horizontal, 4)

            footer(match)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RelayTheme.background)
    }

    private func ghost(for match: Match<FourInARow>) -> (cell: FourInARow.Cell, seat: Seat)? {
        guard case .readyToSend(let pending) = session.mode,
              case .fourInARow(let pendingSnapshot) = pending,
              pendingSnapshot.match.turnNumber > match.turnNumber,
              let cell = pendingSnapshot.match.state.lastMove
        else { return nil }
        return (cell, session.localSeat)
    }

    @ViewBuilder
    private func footer(_ match: Match<FourInARow>) -> some View {
        switch session.mode {
        case .yourTurn:
            StatusLine(symbol: "hand.tap", text: match.turnNumber == 0 ? "You go first. Tap a column." : "Your move. Tap a column.")
        case .waitingForOpponent:
            StatusLine(symbol: "hourglass", text: "Their move. Their reply will show up in this chat.")
        case .readyToSend:
            StatusLine(symbol: "arrow.up.circle", text: "Your move is in the message box. Tap send, or tap another column to change it.")
        case .finished:
            ResultPanel(outcome: match.outcome, localSeat: session.localSeat, series: match.header.series.recording(match.outcome), turns: match.turnNumber, rematchKnown: session.knownRematch != nil, onRematch: onRematch, onNewGame: onNewGame)
        }
    }
}

struct StatusLine: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(RelayTheme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }
}

struct NoticeBanner: View {
    let notice: PlaySession.Notice

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(RelayTheme.textPrimary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RelayTheme.surface))
    }

    private var text: String {
        switch notice {
        case .openedOlderTurn(let turn):
            "That was move \(turn). Showing the latest position."
        case .historyDiverged:
            "Two different versions of this game were sent. Showing the first one received."
        }
    }
}

/// End-of-game card: who won, the rematch record, and one obvious next action.
public struct ResultPanel: View {
    let outcome: GameOutcome
    let localSeat: Seat?
    let series: SeriesTally
    let turns: Int
    let rematchKnown: Bool
    let onRematch: () -> Void
    let onNewGame: () -> Void
    @State private var appeared = false

    public init(outcome: GameOutcome, localSeat: Seat?, series: SeriesTally, turns: Int, rematchKnown: Bool, onRematch: @escaping () -> Void, onNewGame: @escaping () -> Void) {
        self.outcome = outcome
        self.localSeat = localSeat
        self.series = series
        self.turns = turns
        self.rematchKnown = rematchKnown
        self.onRematch = onRematch
        self.onNewGame = onNewGame
    }

    public var body: some View {
        VStack(spacing: 10) {
            Text(headline)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(headlineColor)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(RelayTheme.textSecondary)
            if rematchKnown {
                Label("Rematch already started. Open the newest game bubble.", systemImage: "arrow.uturn.forward")
                    .font(.footnote)
                    .foregroundStyle(RelayTheme.textSecondary)
            } else {
                Button("Rematch", action: onRematch)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityHint("Starts a new game against the same player")
            }
            Button("Play something else", action: onNewGame)
                .font(.subheadline)
                .foregroundStyle(RelayTheme.accent)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(RelayTheme.surface))
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { appeared = true }
        }
        .accessibilityElement(children: .contain)
    }

    private var headline: String {
        switch outcome {
        case .won(let winner):
            guard let localSeat else { return "\(RelayTheme.discName(winner)) wins" }
            return winner == localSeat ? "You win!" : "They win"
        case .draw:
            return "Draw"
        case .inProgress:
            return ""
        }
    }

    private var headlineColor: Color {
        if let winner = outcome.winner { return RelayTheme.disc(winner) }
        return RelayTheme.textPrimary
    }

    private var detail: String {
        let record: String
        if let localSeat, series.gamesPlayed > 1 {
            record = " · Record \(series.wins(for: localSeat))–\(series.wins(for: localSeat.opponent))"
        } else {
            record = ""
        }
        return "\(turns) moves\(record)"
    }
}
#endif
