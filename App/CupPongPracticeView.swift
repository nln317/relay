import Observation
import RelayCore
import RelayGames
import RelayUI
import SwiftUI

enum CupPongPracticeOpponent: String, CaseIterable, Identifiable, Hashable, PracticeOption {
    case casualBot, standardBot, sharpBot, passAndPlay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .casualBot: "Cup Pong vs Casual bot"
        case .standardBot: "Cup Pong vs Standard bot"
        case .sharpBot: "Cup Pong vs Sharp bot"
        case .passAndPlay: "Cup Pong, pass and play"
        }
    }

    var subtitle: String {
        switch self {
        case .casualBot: "Hits the rim more than the cup."
        case .standardBot: "Sinks a fair share. Keep up."
        case .sharpBot: "Rarely misses. Bring your best arm."
        case .passAndPlay: "Two people, one phone."
        }
    }

    var symbol: String {
        switch self {
        case .casualBot: "tortoise"
        case .standardBot: "cpu"
        case .sharpBot: "bolt"
        case .passAndPlay: "person.2"
        }
    }

    var bot: CupPongBot? {
        switch self {
        case .casualBot: CupPongBot(difficulty: .casual)
        case .standardBot: CupPongBot(difficulty: .standard)
        case .sharpBot: CupPongBot(difficulty: .sharp)
        case .passAndPlay: nil
        }
    }
}

/// Local Cup Pong practice: the same rules, table and throwing as Messages, no ledger.
/// Against a bot the human is always seat one; the bot throws its balls one at a time.
@MainActor
@Observable
final class CupPongPracticeModel {
    let opponent: CupPongPracticeOpponent
    private(set) var match: Match<CupPong>
    /// Balls thrown so far in the turn being played (human or bot).
    private(set) var turnLandings: [CupPong.Landing] = []
    private(set) var botThrowing = false
    @ObservationIgnored private var rng = SystemRandomNumberGenerator()
    @ObservationIgnored private var firstSeat: Seat = .one
    @ObservationIgnored private var generation = 0

    init(opponent: CupPongPracticeOpponent) {
        self.opponent = opponent
        self.match = Self.newMatch(firstSeat: .one)
    }

    private static func newMatch(firstSeat: Seat) -> Match<CupPong> {
        let header = MatchHeader(gameID: CupPong.gameID, rulesVersion: CupPong.rulesVersion, firstSeat: firstSeat)
        guard let match = try? Match<CupPong>(header: header, configuration: .standard) else {
            preconditionFailure("standard Cup Pong configuration rejected")
        }
        return match
    }

    var humanSeat: Seat? { opponent.bot == nil ? nil : .one }

    var progress: CupPong.TurnProgress? {
        guard let seat = match.outcome.seatToAct else { return nil }
        return match.state.progress(of: turnLandings, by: seat)
    }

    var humanCanThrow: Bool {
        guard let seat = match.outcome.seatToAct, !botThrowing else { return false }
        return opponent.bot == nil || seat == .one
    }

    func throwBall(_ landing: CupPong.Landing) {
        guard humanCanThrow, let seat = match.outcome.seatToAct, !(progress?.isComplete ?? true) else { return }
        turnLandings.append(landing)
        if finishTurnIfComplete(seat) { scheduleBotIfNeeded() }
    }

    func playAgain() {
        generation += 1
        botThrowing = false
        firstSeat = firstSeat.opponent
        match = Self.newMatch(firstSeat: firstSeat)
        turnLandings = []
        scheduleBotIfNeeded()
    }

    @discardableResult
    private func finishTurnIfComplete(_ seat: Seat) -> Bool {
        guard match.state.progress(of: turnLandings, by: seat).isComplete,
              let next = try? match.applying(CupPong.Action(landings: turnLandings), by: seat)
        else { return false }
        match = next
        turnLandings = []
        return true
    }

    private func scheduleBotIfNeeded() {
        guard let bot = opponent.bot, match.outcome.seatToAct == .two else { return }
        botThrowing = true
        let generation = generation
        Task { @MainActor in
            // Let the human's last ball land, then throw ball by ball.
            try? await Task.sleep(for: .milliseconds(1_800))
            while generation == self.generation, match.outcome.seatToAct == .two, let progress, !progress.isComplete {
                turnLandings.append(bot.nextLanding(at: progress.cups, using: &rng))
                try? await Task.sleep(for: .milliseconds(1_900))
                guard generation == self.generation else { return }
                if finishTurnIfComplete(.two) { break }
            }
            if generation == self.generation { botThrowing = false }
        }
    }
}

struct CupPongPracticeView: View {
    @State private var model: CupPongPracticeModel
    @Environment(\.dismiss) private var dismiss

    init(opponent: CupPongPracticeOpponent) {
        _model = State(initialValue: CupPongPracticeModel(opponent: opponent))
    }

    var body: some View {
        CupPongTable(
            state: model.match.state,
            cups: cups,
            localSeat: model.humanSeat,
            thrower: toAct,
            canThrow: model.humanCanThrow,
            balls: balls,
            nextBallID: model.match.turnNumber * 20 + model.turnLandings.count,
            ballsLeft: model.progress?.ballsLeft ?? 0,
            status: status,
            banner: banner,
            winner: model.match.outcome.winner,
            onThrow: { model.throwBall($0) },
            menuItems: {
                Button("Play again", systemImage: "arrow.counterclockwise") { model.playAgain() }
                Button("Back to games", systemImage: "chevron.backward") { dismiss() }
            },
            footer: {
                if model.match.outcome.isFinished {
                    VStack(spacing: 8) {
                        Button("Play again") { model.playAgain() }
                            .buttonStyle(GameButtonStyle())
                        Button("Back to games") { dismiss() }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
            }
        )
        .toolbar(.hidden, for: .navigationBar)
    }

    private var toAct: Seat? { model.match.outcome.seatToAct }

    /// The cups the player to throw is aiming at; after a game, the last ones thrown at.
    private var cups: [CupPong.Cup] {
        if let progress = model.progress { return progress.cups }
        return model.match.state.lastTurn?.endCups ?? []
    }

    private var balls: [PongBall] {
        let thisTurn = model.match.turnNumber * 20
        if let progress = model.progress, !progress.balls.isEmpty {
            return PongBall.turn(progress.balls, firstID: thisTurn)
        }
        guard let last = model.match.state.lastTurn else { return [] }
        return PongBall.turn(last.balls, firstID: thisTurn - 20)
    }

    private var status: String? {
        guard let toAct else { return nil }
        if model.progress?.ballsBack == true { return "Balls back!" }
        if model.humanSeat != nil { return toAct == model.humanSeat ? nil : "Bot's turn" }
        return "\(RelayTheme.discName(toAct)) to throw"
    }

    private var banner: DartsBanner? {
        switch model.match.outcome {
        case .won(let winner):
            if model.opponent.bot == nil { return .celebration("\(RelayTheme.discName(winner)) won!") }
            return winner == model.humanSeat ? .celebration("You won!") : .info("The bot won")
        case .draw:
            return .info("Draw")
        case .inProgress:
            return nil
        }
    }
}
