#if canImport(UIKit)
import RelayCore
import RelayGames
import RelayMessages
import SwiftUI

/// What the player did on the play screen.
public enum PlayInput: Equatable, Sendable {
    /// Four in a Row: drop a disc in this column.
    case column(Int)
    /// Darts: a dart landed here.
    case dart(Darts.Hit)
    /// Darts: put the already committed visit back in the message box.
    case sendCommitted
}

/// The in-conversation game screen for one resolved `PlaySession`.
public struct PlayScreen: View {
    let session: PlaySession
    let onInput: (PlayInput) -> Void
    let onRematch: () -> Void
    let onNewGame: () -> Void

    public init(session: PlaySession, onInput: @escaping (PlayInput) -> Void, onRematch: @escaping () -> Void, onNewGame: @escaping () -> Void) {
        self.session = session
        self.onInput = onInput
        self.onRematch = onRematch
        self.onNewGame = onNewGame
    }

    private func onColumn(_ column: Int) { onInput(.column(column)) }

    public var body: some View {
        switch session.snapshot {
        case .fourInARow(let snapshot):
            content(snapshot.match)
        case .darts(let snapshot):
            DartsPlayContent(session: session, match: snapshot.match, onInput: onInput, onRematch: onRematch, onNewGame: onNewGame)
                .environment(\.seatPalette, SeatPalette(coloursSwapped: snapshot.match.header.coloursSwapped))
        }
    }

    private func content(_ match: Match<FourInARow>) -> some View {
        VStack(spacing: 14) {
            PlayersHeader(localSeat: session.localSeat, toAct: match.outcome.seatToAct, series: seriesIncludingThisGame(match))

            ForEach(Array(session.notices.enumerated()), id: \.offset) { _, notice in
                NoticeBanner(notice: notice)
            }

            FourInARowBoardView(
                state: match.state,
                ghost: ghost(for: match),
                isInteractive: session.canMove,
                animatesLastMove: true,
                localSeat: session.localSeat,
                onColumnTap: onColumn
            )
            .padding(.horizontal, 4)
            .task(id: match.turnNumber) { announceOpponentMove(in: match) }

            footer(match)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RelayTheme.background)
        .environment(\.seatPalette, SeatPalette(coloursSwapped: match.header.coloursSwapped))
    }

    /// Tells VoiceOver users what the opponent just did, since the falling disc is silent.
    private func announceOpponentMove(in match: Match<FourInARow>) {
        guard let last = match.state.lastMove, match.lastActor == session.localSeat.opponent else { return }
        var text = "They played column \(last.column + 1)."
        if match.outcome.winner == session.localSeat.opponent { text += " They win." }
        if case .draw = match.outcome { text += " It's a draw." }
        AccessibilityNotification.Announcement(text).post()
    }

    /// The header's tally covers earlier games only; once this one ends, count it too.
    private func seriesIncludingThisGame(_ match: Match<FourInARow>) -> SeriesTally {
        match.outcome.isFinished ? match.header.series.recording(match.outcome) : match.header.series
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
            ResultPanel(outcome: match.outcome, localSeat: session.localSeat, turns: match.turnNumber, rematchKnown: session.knownRematch != nil, onRematch: onRematch, onNewGame: onNewGame)
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

/// End-of-game card: who won, how long it took, and one obvious next action.
public struct ResultPanel: View {
    let outcome: GameOutcome
    let localSeat: Seat?
    let turns: Int
    let detailText: String?
    let rematchKnown: Bool
    let onRematch: () -> Void
    let onNewGame: () -> Void
    @State private var appeared = false
    @Environment(\.seatPalette) private var palette

    public init(outcome: GameOutcome, localSeat: Seat?, turns: Int, detail: String? = nil, rematchKnown: Bool, onRematch: @escaping () -> Void, onNewGame: @escaping () -> Void) {
        self.outcome = outcome
        self.localSeat = localSeat
        self.turns = turns
        self.detailText = detail
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
            guard let localSeat else { return "\(palette.name(winner)) wins" }
            return winner == localSeat ? "You win!" : "They win"
        case .draw:
            return "Draw"
        case .inProgress:
            return ""
        }
    }

    private var headlineColor: Color {
        if let winner = outcome.winner { return palette.colour(winner) }
        return RelayTheme.textPrimary
    }

    /// The record lives in the players header above, so the card only adds the length.
    private var detail: String {
        detailText ?? "\(turns) moves"
    }
}

/// Darts inside a conversation: scores, the board to throw at, this visit's darts.
struct DartsPlayContent: View {
    let session: PlaySession
    let match: Match<Darts>
    let onInput: (PlayInput) -> Void
    let onRematch: () -> Void
    let onNewGame: () -> Void
    @Environment(\.seatPalette) private var palette

    var body: some View {
        VStack(spacing: 12) {
            DartsScoreboard(state: match.state, localSeat: session.localSeat, livePreview: livePreview, series: series)
            ForEach(Array(session.notices.enumerated()), id: \.offset) { _, notice in
                NoticeBanner(notice: notice)
            }
            DartsThrowView(
                darts: boardDarts,
                seat: session.localSeat,
                canThrow: canThrow,
                suggestedTarget: DartsBot(difficulty: .sharp).target(remaining: livePreview?.remaining ?? match.state.remaining(for: session.localSeat)),
                onThrow: { onInput(.dart($0)) }
            )
            .padding(.horizontal, 8)
            if let shown = stripProgress {
                DartsVisitStrip(progress: shown.progress, colour: palette.colour(shown.seat))
                    .padding(.horizontal, 4)
            }
            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RelayTheme.background)
        .task(id: match.turnNumber) { announceOpponentVisit() }
    }

    private var series: SeriesTally {
        match.outcome.isFinished ? match.header.series.recording(match.outcome) : match.header.series
    }

    /// This turn's darts so far (committed in the ledger), when it is our turn.
    private var ownProgress: Darts.VisitProgress? {
        guard case .yourTurn = session.mode else { return nil }
        return session.dartsProgress
    }

    private var pendingVisit: Darts.Visit? {
        guard case .readyToSend(let pending) = session.mode, case .darts(let snapshot) = pending else { return nil }
        return snapshot.match.state.lastVisit
    }

    private var canThrow: Bool {
        guard case .yourTurn = session.mode, session.canMove else { return false }
        return !(ownProgress?.isComplete ?? false)
    }

    private var livePreview: (seat: Seat, remaining: Int)? {
        if let ownProgress, !ownProgress.darts.isEmpty { return (session.localSeat, ownProgress.remainingAfter) }
        if let pendingVisit { return (pendingVisit.seat, pendingVisit.remainingAfter) }
        return nil
    }

    /// What the strip under the board describes, and whose colour it wears.
    private var stripProgress: (progress: Darts.VisitProgress, seat: Seat)? {
        if let ownProgress, !ownProgress.darts.isEmpty { return (ownProgress, session.localSeat) }
        if let pendingVisit { return (Darts.VisitProgress(pendingVisit), pendingVisit.seat) }
        if let last = match.state.lastVisit { return (Darts.VisitProgress(last), last.seat) }
        return nil
    }

    private var boardDarts: [PlacedDart] {
        // Ids are per turn, so a dart keeps its identity from thrown to staged, and a new
        // visit's darts animate in rather than slide from the old ones.
        let thisTurn = match.turnNumber * 10
        if let ownProgress, !ownProgress.darts.isEmpty {
            return ownProgress.darts.enumerated().map { PlacedDart(id: thisTurn + $0.offset, hit: $0.element.hit, seat: session.localSeat) }
        }
        if let pendingVisit {
            return pendingVisit.darts.enumerated().map { PlacedDart(id: thisTurn + $0.offset, hit: $0.element.hit, seat: pendingVisit.seat) }
        }
        guard let last = match.state.lastVisit else { return [] }
        return last.darts.enumerated().map { PlacedDart(id: thisTurn - 10 + $0.offset, hit: $0.element.hit, seat: last.seat) }
    }

    @ViewBuilder
    private var footer: some View {
        switch session.mode {
        case .yourTurn:
            if let ownProgress, ownProgress.isComplete {
                Button("Send your darts") { onInput(.sendCommitted) }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityHint("Puts the darts you already threw back in the message box")
            } else if let ownProgress, !ownProgress.darts.isEmpty {
                StatusLine(symbol: "scope", text: "Dart \(ownProgress.darts.count + 1) of \(Darts.dartsPerVisit).")
            } else {
                StatusLine(symbol: "hand.draw", text: "Swipe the dart up at the board.")
            }
        case .waitingForOpponent:
            StatusLine(symbol: "hourglass", text: "Their throw. Their reply will show up in this chat.")
        case .readyToSend:
            StatusLine(symbol: "arrow.up.circle", text: "Your darts are in the message box. Tap send.")
        case .finished:
            ResultPanel(
                outcome: match.outcome,
                localSeat: session.localSeat,
                turns: match.turnNumber,
                detail: resultDetail,
                rematchKnown: session.knownRematch != nil,
                onRematch: onRematch,
                onNewGame: onNewGame
            )
        }
    }

    private var resultDetail: String {
        guard let last = match.state.lastVisit else { return "" }
        if last.result == .finished {
            return "Checked out from \(last.remainingBefore) in round \((match.state.visits.count - 1) / 2 + 1)"
        }
        return "Fewest points left after \(match.state.configuration.rounds) rounds"
    }

    private func announceOpponentVisit() {
        guard case .yourTurn = session.mode, let last = match.state.lastVisit, last.seat != session.localSeat else { return }
        let darts = last.darts.map(\.segment.spokenName).joined(separator: ", ")
        let result = last.result == .bust ? "Bust." : "\(last.points) points, \(last.remainingAfter) left."
        AccessibilityNotification.Announcement("They threw \(darts). \(result)").post()
    }
}

extension BubbleImageRenderer {
    /// The bubble image for any game's snapshot.
    @MainActor
    public static func image(for snapshot: AnyMatchSnapshot) -> UIImage? {
        switch snapshot {
        case .fourInARow(let snapshot):
            return image(for: snapshot.match)
        case .darts(let snapshot):
            let palette = SeatPalette(coloursSwapped: snapshot.match.header.coloursSwapped)
            let renderer = ImageRenderer(content: DartsBubbleArt(state: snapshot.match.state, palette: palette))
            renderer.scale = 3
            return renderer.uiImage
        }
    }
}
#endif
