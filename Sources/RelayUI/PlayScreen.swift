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
    /// 8-Ball: one shot.
    case shot(EightBall.Shot)
    /// Darts and 8-Ball: put the already committed turn back in the message box.
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
        case .eightBall(let snapshot):
            EightBallPlayContent(session: session, match: snapshot.match, onInput: onInput, onRematch: onRematch, onNewGame: onNewGame)
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
private struct TableIdentity: Hashable {
    let match: MatchID
    let seat: Seat
}

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
        // A fresh table per match and per player, so opening the other phone's view (or
        // another game) replays its darts instead of inheriting this one's.
        .id(TableIdentity(match: match.header.matchID, seat: session.localSeat))
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

/// 8-Ball inside a conversation. Shots are numbered per turn (20 a turn), so a shot keeps
/// its identity from taken to sent to opened, and only the other player's are replayed.
struct EightBallPlayContent: View {
    let session: PlaySession
    let match: Match<EightBall>
    let onInput: (PlayInput) -> Void
    let onRematch: () -> Void
    let onNewGame: () -> Void

    var body: some View {
        EightBallTable(
            state: match.state,
            positions: table.positions,
            groups: table.groups,
            ballInHand: table.ballInHand,
            localSeat: session.localSeat,
            shooter: session.localSeat,
            canShoot: canShoot,
            shots: shots,
            replaysShots: replaysOpponentTurn,
            nextShotID: match.turnNumber * 20 + (ownProgress?.results.count ?? 0),
            status: EightBallText.status(state: match.state, progress: ownProgress, seat: session.localSeat, isYourTurn: isYourTurn),
            banner: banner,
            winner: match.outcome.winner,
            notices: session.notices.map(\.text),
            onShoot: { onInput(.shot($0)) },
            menuItems: {
                if match.outcome.isFinished, session.knownRematch == nil {
                    Button("Rematch", systemImage: "arrow.counterclockwise", action: onRematch)
                }
                Button("New game", systemImage: "plus", action: onNewGame)
            },
            footer: { footer }
        )
        .id(TableIdentity(match: match.header.matchID, seat: session.localSeat))
        .task(id: match.turnNumber) { announceOpponentTurn() }
    }

    private var isYourTurn: Bool {
        if case .yourTurn = session.mode { return true }
        return false
    }

    /// This turn's shots so far (committed in the ledger), when it is our turn.
    private var ownProgress: EightBall.TurnProgress? {
        guard isYourTurn else { return nil }
        return session.eightBallProgress
    }

    /// The table after the turn waiting in the message box.
    private var pendingState: EightBall.State? {
        guard case .readyToSend(let pending) = session.mode, case .eightBall(let snapshot) = pending else { return nil }
        return snapshot.match.state
    }

    private var table: (positions: [PoolTable.Vector?], groups: [Seat: EightBall.Group], ballInHand: EightBall.BallInHand) {
        if let ownProgress { return (ownProgress.positions, ownProgress.groups, ownProgress.ballInHand) }
        let state = pendingState ?? match.state
        return (state.positions, state.groups, state.ballInHand)
    }

    private var canShoot: Bool {
        guard isYourTurn, session.canMove else { return false }
        return !(ownProgress?.isComplete ?? false)
    }

    private var shots: [PoolShotPlayback] {
        let thisTurn = match.turnNumber * 20
        if let ownProgress, !ownProgress.results.isEmpty {
            return PoolShotPlayback.turn(ownProgress.results, firstID: thisTurn)
        }
        if let pending = pendingState?.lastTurn {
            return PoolShotPlayback.turn(pending.shots, firstID: thisTurn)
        }
        guard let last = match.state.lastTurn else { return [] }
        return PoolShotPlayback.turn(last.shots, firstID: thisTurn - 20)
    }

    /// Opening the other player's turn plays their shots first.
    private var replaysOpponentTurn: Bool {
        guard isYourTurn, ownProgress?.results.isEmpty ?? true else { return false }
        return match.state.lastTurn?.seat == session.localSeat.opponent
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
                Button("Send your turn") { onInput(.sendCommitted) }
                    .buttonStyle(GameButtonStyle())
                    .accessibilityHint("Puts the shots you already took back in the message box")
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

    private func announceOpponentTurn() {
        guard isYourTurn, let last = match.state.lastTurn, last.seat != session.localSeat else { return }
        AccessibilityNotification.Announcement(EightBallText.spoken(last)).post()
    }
}

/// Words for the 8-Ball table: the status line and what VoiceOver says about a turn.
public enum EightBallText {
    public static func foul(_ foul: EightBall.Foul) -> String {
        switch foul {
        case .scratch: "Scratch"
        case .noContact: "No ball hit"
        case .wrongBallFirst: "Wrong ball first"
        }
    }

    /// The line under the players while it is `seat`'s turn: the break, a foul that gave
    /// them the cue ball, or which group they are on.
    public static func status(state: EightBall.State, progress: EightBall.TurnProgress?, seat: Seat, isYourTurn: Bool) -> String? {
        guard isYourTurn, !(progress?.isComplete ?? false) else { return nil }
        let shotsTaken = progress?.results.count ?? 0
        if state.isBreak, shotsTaken == 0 { return "Your break" }
        let ballInHand = progress?.ballInHand ?? state.ballInHand
        let groups = progress?.groups ?? state.groups
        if ballInHand != .none {
            if shotsTaken == 0, let foul = state.lastTurn?.shots.last?.foul {
                return "\(Self.foul(foul)): ball in hand"
            }
            return "Ball in hand"
        }
        if let group = groups[seat] {
            if let progress, progress.results.last?.assignedGroup != nil {
                return group == .solids ? "You're solids" : "You're stripes"
            }
            let positions = progress?.positions ?? state.positions
            if group.balls.allSatisfy({ positions[$0] == nil }) { return "Sink the 8" }
            return nil
        }
        return "Table open"
    }

    public static func spoken(_ turn: EightBall.Turn) -> String {
        let potted = turn.shots.flatMap(\.pocketed).filter { $0 != 0 }
        var parts: [String] = []
        parts.append(potted.isEmpty ? "They potted nothing." : "They potted \(potted.map(String.init).joined(separator: ", ")).")
        if let foul = turn.shots.last?.foul { parts.append("Foul: \(Self.foul(foul)). Ball in hand.") }
        return parts.joined(separator: " ")
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

/// The bubble picture for any game's snapshot, as a live view (the compact drawer shows it).
public struct GameSnapshotArt: View {
    let snapshot: AnyMatchSnapshot

    public init(snapshot: AnyMatchSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        switch snapshot {
        case .fourInARow(let snapshot):
            FourInARowBubbleArt(state: snapshot.match.state, palette: SeatPalette(coloursSwapped: snapshot.match.header.coloursSwapped))
        case .darts(let snapshot):
            DartsBubbleArt(state: snapshot.match.state, palette: SeatPalette(coloursSwapped: snapshot.match.header.coloursSwapped))
        case .eightBall(let snapshot):
            EightBallBubbleArt(state: snapshot.match.state)
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
        case .eightBall(let snapshot):
            let renderer = ImageRenderer(content: EightBallBubbleArt(state: snapshot.match.state))
            renderer.scale = 3
            return renderer.uiImage
        }
    }
}
#endif
