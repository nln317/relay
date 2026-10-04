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
        FourInARowTable(
            state: match.state,
            localSeat: session.localSeat,
            ghost: ghost(for: match),
            canMove: session.canMove,
            banner: banner(for: match),
            notices: session.notices.map(\.text),
            onColumnTap: onColumn,
            menuItems: {
                if match.outcome.isFinished, session.knownRematch == nil {
                    Button("Rematch", systemImage: "arrow.counterclockwise", action: onRematch)
                }
                Button("New game", systemImage: "plus", action: onNewGame)
            },
            footer: {
                if case .finished = session.mode {
                    if session.knownRematch != nil {
                        Text("Rematch started. Open the newest game bubble.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(white: 0.2))
                    } else {
                        Button("Rematch", action: onRematch)
                            .buttonStyle(GameButtonStyle())
                            .accessibilityHint("Starts a new game against the same player")
                    }
                }
            }
        )
        .task(id: match.turnNumber) { announceOpponentMove(in: match) }
        .environment(\.seatPalette, SeatPalette(coloursSwapped: match.header.coloursSwapped))
    }

    private func banner(for match: Match<FourInARow>) -> DartsBanner? {
        switch session.mode {
        case .yourTurn: return nil
        case .waitingForOpponent: return .info("Waiting for opponent...")
        case .readyToSend: return .info("Tap send, or pick another column")
        case .finished:
            switch match.outcome {
            case .won(let winner): return winner == session.localSeat ? .celebration("You won!") : .info("You lost")
            case .draw: return .info("Draw")
            case .inProgress: return nil
            }
        }
    }

    /// Tells VoiceOver users what the opponent just did, since the falling disc is silent.
    private func announceOpponentMove(in match: Match<FourInARow>) {
        guard let last = match.state.lastMove, match.lastActor == session.localSeat.opponent else { return }
        var text = "They played column \(last.column + 1)."
        if match.outcome.winner == session.localSeat.opponent { text += " They win." }
        if case .draw = match.outcome { text += " It's a draw." }
        AccessibilityNotification.Announcement(text).post()
    }

    private func ghost(for match: Match<FourInARow>) -> (cell: FourInARow.Cell, seat: Seat)? {
        guard case .readyToSend(let pending) = session.mode,
              case .fourInARow(let pendingSnapshot) = pending,
              pendingSnapshot.match.turnNumber > match.turnNumber,
              let cell = pendingSnapshot.match.state.lastMove
        else { return nil }
        return (cell, session.localSeat)
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

    private var text: String { notice.text }
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

/// Darts inside a conversation, on the full-screen darts table.
struct DartsPlayContent: View {
    let session: PlaySession
    let match: Match<Darts>
    let onInput: (PlayInput) -> Void
    let onRematch: () -> Void
    let onNewGame: () -> Void

    var body: some View {
        DartsTable(
            state: match.state,
            localSeat: session.localSeat,
            thrower: session.localSeat,
            canThrow: canThrow,
            darts: boardDarts,
            visit: shownVisit,
            livePreview: livePreview,
            dartsLeft: dartsLeft,
            banner: banner,
            winner: match.outcome.winner,
            replaysDarts: replaysOpponentVisit,
            notices: session.notices.map(\.text),
            onThrow: { onInput(.dart($0)) },
            menuItems: {
                if match.outcome.isFinished, session.knownRematch == nil {
                    Button("Rematch", systemImage: "arrow.counterclockwise", action: onRematch)
                }
                Button("New game", systemImage: "plus", action: onNewGame)
            },
            footer: { footer }
        )
        .task(id: match.turnNumber) { announceOpponentVisit() }
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

    private var dartsLeft: Int {
        guard case .yourTurn = session.mode else { return 0 }
        return Darts.dartsPerVisit - (ownProgress?.darts.count ?? 0)
    }

    private var livePreview: (seat: Seat, remaining: Int)? {
        if let ownProgress, !ownProgress.darts.isEmpty { return (session.localSeat, ownProgress.remainingAfter) }
        if let pendingVisit { return (pendingVisit.seat, pendingVisit.remainingAfter) }
        return nil
    }

    /// How the darts on the board scored.
    private var shownVisit: Darts.VisitProgress? {
        if let ownProgress, !ownProgress.darts.isEmpty { return ownProgress }
        if let pendingVisit { return Darts.VisitProgress(pendingVisit) }
        return match.state.lastVisit.map { Darts.VisitProgress($0) }
    }

    /// Opening the other player's visit flies their darts in first.
    private var replaysOpponentVisit: Bool {
        guard case .yourTurn = session.mode, ownProgress?.darts.isEmpty ?? true else { return false }
        return match.state.lastVisit?.seat == session.localSeat.opponent
    }

    private var boardDarts: [PlacedDart] {
        // Ids are per turn, so a dart keeps its identity from thrown to staged, and a new
        // visit's darts fly in rather than slide from the old ones.
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

    private var banner: DartsBanner? {
        switch session.mode {
        case .yourTurn: return nil
        case .waitingForOpponent: return .info("Waiting for opponent...")
        case .readyToSend: return .info("Tap send to finish your turn")
        case .finished:
            switch match.outcome {
            case .won(let winner): return winner == session.localSeat ? .celebration("You won!") : .info("You lost")
            case .draw: return .info("Draw")
            case .inProgress: return nil
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch session.mode {
        case .yourTurn:
            if let ownProgress, ownProgress.isComplete {
                Button("Send your darts") { onInput(.sendCommitted) }
                    .buttonStyle(GameButtonStyle())
                    .accessibilityHint("Puts the darts you already threw back in the message box")
            }
        case .waitingForOpponent, .readyToSend:
            EmptyView()
        case .finished:
            if session.knownRematch != nil {
                Text("Rematch started. Open the newest game bubble.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            } else {
                Button("Rematch", action: onRematch)
                    .buttonStyle(GameButtonStyle())
                    .accessibilityHint("Starts a new game against the same player")
            }
        }
    }

    private func announceOpponentVisit() {
        guard case .yourTurn = session.mode, let last = match.state.lastVisit, last.seat != session.localSeat else { return }
        let darts = last.darts.map(\.segment.spokenName).joined(separator: ", ")
        let result = last.result == .bust ? "Bust." : "\(last.points) points, \(last.remainingAfter) left."
        AccessibilityNotification.Announcement("They threw \(darts). \(result)").post()
    }
}

extension PlaySession.Notice {
    var text: String {
        switch self {
        case .openedOlderTurn(let turn):
            "That was move \(turn). Showing the latest position."
        case .historyDiverged:
            "Two different versions of this game were sent. Showing the first one received."
        }
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
