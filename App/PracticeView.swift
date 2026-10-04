import Observation
import RelayAnalytics
import RelayCore
import RelayGames
import RelayUI
import SwiftUI

enum PracticeOpponent: String, CaseIterable, Identifiable, Hashable {
    case casualBot, standardBot, sharpBot, passAndPlay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .casualBot: "Four in a Row vs Casual bot"
        case .standardBot: "Four in a Row vs Standard bot"
        case .sharpBot: "Four in a Row vs Sharp bot"
        case .passAndPlay: "Four in a Row, pass and play"
        }
    }

    var subtitle: String {
        switch self {
        case .casualBot: "Relaxed. Good for learning."
        case .standardBot: "Blocks your obvious wins."
        case .sharpBot: "Looks a few moves ahead."
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

    var bot: FourInARowBot? {
        switch self {
        case .casualBot: FourInARowBot(difficulty: .casual)
        case .standardBot: FourInARowBot(difficulty: .standard)
        case .sharpBot: FourInARowBot(difficulty: .sharp)
        case .passAndPlay: nil
        }
    }
}

/// Local practice: the same rules engine and board as Messages, no networking,
/// no ledger. The human is always seat one against a bot.
@MainActor
@Observable
final class PracticeModel {
    let opponent: PracticeOpponent
    private(set) var match: Match<FourInARow>
    private(set) var series = SeriesTally.empty
    private(set) var botThinking = false
    @ObservationIgnored private var rng = SystemRandomNumberGenerator()
    @ObservationIgnored private var firstSeat: Seat = .one

    init(opponent: PracticeOpponent) {
        self.opponent = opponent
        self.match = Self.newMatch(firstSeat: .one)
    }

    private static func newMatch(firstSeat: Seat) -> Match<FourInARow> {
        let header = MatchHeader(gameID: FourInARow.gameID, rulesVersion: FourInARow.rulesVersion, firstSeat: firstSeat)
        // The standard configuration is always supported; failure here is a programming error.
        guard let match = try? Match<FourInARow>(header: header, configuration: .standard) else {
            preconditionFailure("standard Four in a Row configuration rejected")
        }
        return match
    }

    var humanCanMove: Bool {
        guard let toAct = match.outcome.seatToAct, !botThinking else { return false }
        return opponent.bot == nil || toAct == .one
    }

    func tap(column: Int) {
        guard humanCanMove, let seat = match.outcome.seatToAct,
              let next = try? match.applying(.init(column: column), by: seat)
        else { return }
        match = next
        recordIfFinished()
        scheduleBotIfNeeded()
    }

    func playAgain() {
        // Alternate who starts, like a rematch in Messages.
        firstSeat = firstSeat.opponent
        match = Self.newMatch(firstSeat: firstSeat)
        scheduleBotIfNeeded()
    }

    private func recordIfFinished() {
        if match.outcome.isFinished { series = series.recording(match.outcome) }
    }

    private func scheduleBotIfNeeded() {
        guard let bot = opponent.bot, match.outcome.seatToAct == .two else { return }
        botThinking = true
        Task { @MainActor in
            // A short pause reads as "thinking" and lets the human's disc land first.
            try? await Task.sleep(for: .milliseconds(550))
            defer { botThinking = false }
            guard match.outcome.seatToAct == .two,
                  let column = bot.chooseColumn(in: match.state, using: &rng),
                  let next = try? match.applying(.init(column: column), by: .two)
            else { return }
            match = next
            recordIfFinished()
        }
    }
}

struct PracticeView: View {
    @State private var model: PracticeModel

    init(opponent: PracticeOpponent) {
        _model = State(initialValue: PracticeModel(opponent: opponent))
    }

    var body: some View {
        VStack(spacing: 16) {
            PlayersHeader(
                localSeat: model.opponent.bot == nil ? nil : .one,
                toAct: model.match.outcome.seatToAct,
                series: model.series
            )
            FourInARowBoardView(
                state: model.match.state,
                isInteractive: model.humanCanMove,
                onColumnTap: { model.tap(column: $0) }
            )
            if model.match.outcome.isFinished {
                ResultPanel(
                    outcome: model.match.outcome,
                    localSeat: model.opponent.bot == nil ? nil : .one,
                    turns: model.match.turnNumber,
                    rematchKnown: false,
                    onRematch: model.playAgain,
                    onNewGame: model.playAgain
                )
            } else {
                Text(status)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(RelayTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RelayTheme.background.ignoresSafeArea())
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var status: String {
        if model.botThinking { return "Thinking…" }
        guard let toAct = model.match.outcome.seatToAct else { return "" }
        if model.opponent.bot == nil { return "\(RelayTheme.discName(toAct)) to move" }
        return toAct == .one ? "Your move" : "Bot's move"
    }
}
