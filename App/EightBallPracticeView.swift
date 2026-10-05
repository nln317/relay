import Observation
import RelayCore
import RelayGames
import RelayUI
import SwiftUI

enum EightBallPracticeOpponent: String, CaseIterable, Identifiable, Hashable, PracticeOption {
    case casualBot, standardBot, sharpBot, passAndPlay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .casualBot: "8 Ball vs Casual bot"
        case .standardBot: "8 Ball vs Standard bot"
        case .sharpBot: "8 Ball vs Sharp bot"
        case .passAndPlay: "8 Ball, pass and play"
        }
    }

    var subtitle: String {
        switch self {
        case .casualBot: "Misses plenty. Good for learning the cue."
        case .standardBot: "Pots the easy ones and plays safe."
        case .sharpBot: "Runs the table if you leave it open."
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

    var bot: EightBallBot? {
        switch self {
        case .casualBot: EightBallBot(difficulty: .casual)
        case .standardBot: EightBallBot(difficulty: .standard)
        case .sharpBot: EightBallBot(difficulty: .sharp)
        case .passAndPlay: nil
        }
    }
}

/// Local 8-Ball practice: the same rules, physics and table as Messages, no ledger.
/// Against a bot the human is always seat one; the bot takes its shots one at a time,
/// thinking off the main thread, and waits for each to roll out before the next.
@MainActor
@Observable
final class EightBallPracticeModel {
    let opponent: EightBallPracticeOpponent
    private(set) var match: Match<EightBall>
    /// Shots taken so far in the turn being played (human or bot).
    private(set) var turnShots: [EightBall.Shot] = []
    private(set) var botShooting = false
    @ObservationIgnored private var firstSeat: Seat = .one
    /// Bumped by "Play again", so a bot still thinking about the old game stops.
    @ObservationIgnored private var generation = 0

    init(opponent: EightBallPracticeOpponent) {
        self.opponent = opponent
        self.match = Self.newMatch(firstSeat: .one)
    }

    private static func newMatch(firstSeat: Seat) -> Match<EightBall> {
        let header = MatchHeader(gameID: EightBall.gameID, rulesVersion: EightBall.rulesVersion, firstSeat: firstSeat)
        guard let match = try? Match<EightBall>(header: header, configuration: .standard) else {
            preconditionFailure("standard 8-Ball configuration rejected")
        }
        return match
    }

    var humanSeat: Seat? { opponent.bot == nil ? nil : .one }

    var progress: EightBall.TurnProgress? {
        guard let seat = match.outcome.seatToAct else { return nil }
        return match.state.progress(of: turnShots, by: seat)
    }

    var humanCanShoot: Bool {
        guard let seat = match.outcome.seatToAct, !botShooting else { return false }
        return opponent.bot == nil || seat == .one
    }

    func shoot(_ shot: EightBall.Shot) {
        guard humanCanShoot, let seat = match.outcome.seatToAct, let progress, !progress.isComplete,
              EightBall.validate(shot, ballInHand: progress.ballInHand, positions: progress.positions) == nil
        else { return }
        let start = progress.positions
        turnShots.append(shot)
        if finishTurnIfComplete(seat) {
            // Let the human's last shot roll out before the bot steps up.
            scheduleBotIfNeeded(after: rollTime(shot, from: start))
        }
    }

    func playAgain() {
        generation += 1
        botShooting = false
        firstSeat = firstSeat.opponent
        match = Self.newMatch(firstSeat: firstSeat)
        turnShots = []
        scheduleBotIfNeeded(after: .zero)
    }

    /// Applies the turn once it is over. True when it was.
    @discardableResult
    private func finishTurnIfComplete(_ seat: Seat) -> Bool {
        guard match.state.progress(of: turnShots, by: seat).isComplete,
              let next = try? match.applying(EightBall.Action(shots: turnShots), by: seat)
        else { return false }
        match = next
        turnShots = []
        return true
    }

    private func rollTime(_ shot: EightBall.Shot, from positions: [PoolTable.Vector?]) -> Duration {
        let frames = EightBall.animation(of: shot, from: positions).frames.count
        return .milliseconds(frames * 1_000 / 60 + 450)
    }

    private func scheduleBotIfNeeded(after wait: Duration) {
        guard let bot = opponent.bot, match.outcome.seatToAct == .two else { return }
        botShooting = true
        let generation = generation
        Task { @MainActor in
            try? await Task.sleep(for: wait + .milliseconds(500))
            while generation == self.generation, match.outcome.seatToAct == .two {
                guard let progress, !progress.isComplete else { break }
                let isBreak = match.state.isBreak && turnShots.isEmpty
                let shot = await Task.detached(priority: .userInitiated) {
                    var rng = SystemRandomNumberGenerator()
                    return bot.chooseShot(
                        positions: progress.positions,
                        groups: progress.groups,
                        ballInHand: progress.ballInHand,
                        isBreak: isBreak,
                        seat: .two,
                        using: &rng
                    )
                }.value
                guard generation == self.generation else { return }
                turnShots.append(shot)
                // The table shows the shot after a short pause; wait for it to roll out.
                try? await Task.sleep(for: rollTime(shot, from: progress.positions) + .milliseconds(450))
                guard generation == self.generation else { return }
                if finishTurnIfComplete(.two) { break }
            }
            if generation == self.generation { botShooting = false }
        }
    }
}

struct EightBallPracticeView: View {
    @State private var model: EightBallPracticeModel
    @Environment(\.dismiss) private var dismiss

    init(opponent: EightBallPracticeOpponent) {
        _model = State(initialValue: EightBallPracticeModel(opponent: opponent))
    }

    var body: some View {
        EightBallTable(
            state: model.match.state,
            positions: table.positions,
            groups: table.groups,
            ballInHand: table.ballInHand,
            localSeat: model.humanSeat,
            shooter: toAct,
            canShoot: model.humanCanShoot,
            shots: shots,
            nextShotID: model.match.turnNumber * 20 + model.turnShots.count,
            status: status,
            banner: banner,
            winner: model.match.outcome.winner,
            onShoot: { model.shoot($0) },
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

    private var table: (positions: [PoolTable.Vector?], groups: [Seat: EightBall.Group], ballInHand: EightBall.BallInHand) {
        if let progress = model.progress { return (progress.positions, progress.groups, progress.ballInHand) }
        let state = model.match.state
        return (state.positions, state.groups, state.ballInHand)
    }

    private var shots: [PoolShotPlayback] {
        let thisTurn = model.match.turnNumber * 20
        if let progress = model.progress, !progress.results.isEmpty {
            return PoolShotPlayback.turn(progress.results, firstID: thisTurn)
        }
        guard let last = model.match.state.lastTurn else { return [] }
        return PoolShotPlayback.turn(last.shots, firstID: thisTurn - 20)
    }

    private var status: String? {
        guard let toAct else { return nil }
        if model.botShooting || (model.humanSeat != nil && toAct != model.humanSeat) { return "Bot's turn" }
        let line = EightBallText.status(state: model.match.state, progress: model.progress, seat: toAct, isYourTurn: true)
        guard model.humanSeat == nil else { return line }
        // Pass and play: say whose turn it is.
        let name = RelayTheme.discName(toAct)
        return line.map { "\(name): \($0.replacingOccurrences(of: "Your break", with: "break").replacingOccurrences(of: "You're", with: "on"))" } ?? "\(name) to shoot"
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
