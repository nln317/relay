import Observation
import RelayCore
import RelayGames
import RelayUI
import SwiftUI

enum DartsPracticeOpponent: String, CaseIterable, Identifiable, Hashable, PracticeOption {
    case casualBot, standardBot, sharpBot, passAndPlay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .casualBot: "Darts vs Casual bot"
        case .standardBot: "Darts vs Standard bot"
        case .sharpBot: "Darts vs Sharp bot"
        case .passAndPlay: "Darts, pass and play"
        }
    }

    var subtitle: String {
        switch self {
        case .casualBot: "Sprays it around. Good for learning."
        case .standardBot: "Aims for the big numbers and finishes."
        case .sharpBot: "Groups tight. Bring your best arm."
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

    var bot: DartsBot? {
        switch self {
        case .casualBot: DartsBot(difficulty: .casual)
        case .standardBot: DartsBot(difficulty: .standard)
        case .sharpBot: DartsBot(difficulty: .sharp)
        case .passAndPlay: nil
        }
    }
}

/// Local Darts practice: the same rules, board and throwing as Messages, no ledger.
/// Against a bot the human is always seat one; the bot throws its darts one at a time.
@MainActor
@Observable
final class DartsPracticeModel {
    let opponent: DartsPracticeOpponent
    private(set) var match: Match<Darts>
    private(set) var series = SeriesTally.empty
    /// Darts thrown so far in the visit being played (human or bot).
    private(set) var visitHits: [Darts.Hit] = []
    private(set) var botThrowing = false
    @ObservationIgnored private var rng = SystemRandomNumberGenerator()
    @ObservationIgnored private var firstSeat: Seat = .one

    init(opponent: DartsPracticeOpponent) {
        self.opponent = opponent
        self.match = Self.newMatch(firstSeat: .one)
    }

    private static func newMatch(firstSeat: Seat) -> Match<Darts> {
        let header = MatchHeader(gameID: Darts.gameID, rulesVersion: Darts.rulesVersion, firstSeat: firstSeat)
        guard let match = try? Match<Darts>(header: header, configuration: .standard) else {
            preconditionFailure("standard Darts configuration rejected")
        }
        return match
    }

    var humanSeat: Seat? { opponent.bot == nil ? nil : .one }

    var progress: Darts.VisitProgress? {
        guard let seat = match.outcome.seatToAct else { return nil }
        return match.state.progress(of: visitHits, by: seat)
    }

    var humanCanThrow: Bool {
        guard let seat = match.outcome.seatToAct, !botThrowing else { return false }
        return opponent.bot == nil || seat == .one
    }

    func throwDart(_ hit: Darts.Hit) {
        guard humanCanThrow, let seat = match.outcome.seatToAct else { return }
        visitHits.append(hit)
        finishVisitIfComplete(seat)
        scheduleBotIfNeeded()
    }

    func playAgain() {
        firstSeat = firstSeat.opponent
        match = Self.newMatch(firstSeat: firstSeat)
        visitHits = []
        scheduleBotIfNeeded()
    }

    private func finishVisitIfComplete(_ seat: Seat) {
        guard match.state.progress(of: visitHits, by: seat).isComplete,
              let next = try? match.applying(Darts.Action(hits: visitHits), by: seat)
        else { return }
        // Leave the darts on the board until the next visit starts.
        match = next
        visitHits = []
        if match.outcome.isFinished { series = series.recording(match.outcome) }
    }

    private func scheduleBotIfNeeded() {
        guard let bot = opponent.bot, match.outcome.seatToAct == .two else { return }
        botThrowing = true
        Task { @MainActor in
            defer { botThrowing = false }
            // Let the human read their visit, then throw dart by dart.
            try? await Task.sleep(for: .milliseconds(900))
            guard let visit = bot.throwVisit(in: match.state, using: &rng) else { return }
            for hit in visit.hits {
                visitHits.append(hit)
                try? await Task.sleep(for: .milliseconds(650))
            }
            finishVisitIfComplete(.two)
        }
    }
}

struct DartsPracticeView: View {
    @State private var model: DartsPracticeModel
    @Environment(\.dismiss) private var dismiss

    init(opponent: DartsPracticeOpponent) {
        _model = State(initialValue: DartsPracticeModel(opponent: opponent))
    }

    var body: some View {
        VStack(spacing: 12) {
            DartsScoreboard(
                state: model.match.state,
                localSeat: model.humanSeat,
                livePreview: livePreview,
                series: model.series
            )
            DartsThrowView(
                darts: boardDarts,
                canThrow: model.humanCanThrow,
                suggestedTarget: suggestedTarget,
                onThrow: { model.throwDart($0) }
            )
            if let strip {
                DartsVisitStrip(progress: strip.progress, colour: RelayTheme.disc(strip.seat))
            }
            if model.match.outcome.isFinished {
                ResultPanel(
                    outcome: model.match.outcome,
                    localSeat: model.humanSeat,
                    turns: model.match.turnNumber,
                    detail: resultDetail,
                    rematchKnown: false,
                    onRematch: model.playAgain,
                    onNewGame: { dismiss() }
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

    private var toAct: Seat? { model.match.outcome.seatToAct }

    private var livePreview: (seat: Seat, remaining: Int)? {
        guard let toAct, let progress = model.progress, !progress.darts.isEmpty else { return nil }
        return (toAct, progress.remainingAfter)
    }

    private var suggestedTarget: DartsBoard.Segment? {
        guard let toAct else { return nil }
        return DartsBot(difficulty: .sharp).target(remaining: livePreview?.remaining ?? model.match.state.remaining(for: toAct))
    }

    private var boardDarts: [PlacedDart] {
        let thisTurn = model.match.turnNumber * 10
        if let toAct, !model.visitHits.isEmpty {
            return model.visitHits.enumerated().map { PlacedDart(id: thisTurn + $0.offset, hit: $0.element, seat: toAct) }
        }
        guard let last = model.match.state.lastVisit else { return [] }
        return last.darts.enumerated().map { PlacedDart(id: thisTurn - 10 + $0.offset, hit: $0.element.hit, seat: last.seat) }
    }

    private var strip: (progress: Darts.VisitProgress, seat: Seat)? {
        if let toAct, let progress = model.progress, !progress.darts.isEmpty { return (progress, toAct) }
        guard let last = model.match.state.lastVisit else { return nil }
        return (Darts.VisitProgress(last), last.seat)
    }

    private var resultDetail: String {
        guard let last = model.match.state.lastVisit else { return "" }
        if last.result == .finished { return "Checked out from \(last.remainingBefore)" }
        return "Fewest points left after \(model.match.state.configuration.rounds) rounds"
    }

    private var status: String {
        if model.botThrowing { return "Bot is throwing…" }
        guard let toAct else { return "" }
        let thrown = model.progress?.darts.count ?? 0
        let who = model.humanSeat == nil ? "\(RelayTheme.discName(toAct)): " : ""
        return thrown == 0 ? "\(who)Drag on the board to aim. Let go to throw." : "\(who)Dart \(thrown + 1) of \(Darts.dartsPerVisit)."
    }
}
