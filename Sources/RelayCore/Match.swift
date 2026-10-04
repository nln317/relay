import Foundation

/// Everything about a match that is fixed when it is created.
public struct MatchHeader: Codable, Equatable, Sendable {
    public var matchID: MatchID
    public var gameID: GameID
    public var rulesVersion: RulesVersion
    /// Which seat makes the first move. Seat one is always the challenger.
    public var firstSeat: Seat
    /// Set when this match is a rematch, linking the chain.
    public var previousMatchID: MatchID?
    /// Results of earlier matches in this rematch chain, in this match's seat numbering.
    public var series: SeriesTally
    /// Reserved for Rivalry Sets (Milestone 5). Always nil in Milestone 1.
    public var rivalryID: RivalryID?
    /// Seat one wears seat two's colour and mark. Rematches renumber seats (the
    /// initiator becomes seat one); this keeps each person's colour across the chain.
    public var coloursSwapped: Bool

    public init(
        matchID: MatchID = MatchID(),
        gameID: GameID,
        rulesVersion: RulesVersion,
        firstSeat: Seat = .one,
        previousMatchID: MatchID? = nil,
        series: SeriesTally = .empty,
        rivalryID: RivalryID? = nil,
        coloursSwapped: Bool = false
    ) {
        self.matchID = matchID
        self.gameID = gameID
        self.rulesVersion = rulesVersion
        self.firstSeat = firstSeat
        self.previousMatchID = previousMatchID
        self.series = series
        self.rivalryID = rivalryID
        self.coloursSwapped = coloursSwapped
    }
}

/// Why a match could not be built or advanced.
public enum MatchError<Violation: Error & Equatable & Sendable>: Error, Equatable, Sendable {
    case gameMismatch(expected: GameID, found: GameID)
    case unsupportedRulesVersion(RulesVersion)
    case unsupportedConfiguration
    case tooManyActions(count: Int, limit: Int)
    case gameAlreadyFinished
    case notYourTurn(expected: Seat, found: Seat)
    /// An action in the history broke the rules. `index` is zero-based.
    case illegalAction(index: Int, violation: Violation)
}

/// A match of one game: its header, configuration and full action history.
/// The game state is always derived by replaying the history through the rules,
/// so a received match is verified rather than trusted.
public struct Match<Rules: GameRules>: Equatable, Sendable {
    public let header: MatchHeader
    public let configuration: Rules.Configuration
    public private(set) var actions: [Rules.Action]
    public private(set) var state: Rules.State

    /// A new match with no moves yet.
    public init(header: MatchHeader, configuration: Rules.Configuration) throws(MatchError<Rules.RuleViolation>) {
        guard header.gameID == Rules.gameID else {
            throw .gameMismatch(expected: Rules.gameID, found: header.gameID)
        }
        guard header.rulesVersion == Rules.rulesVersion else {
            throw .unsupportedRulesVersion(header.rulesVersion)
        }
        guard Rules.isSupported(configuration) else { throw .unsupportedConfiguration }
        self.header = header
        self.configuration = configuration
        self.actions = []
        self.state = Rules.initialState(for: configuration, firstSeat: header.firstSeat)
    }

    /// Rebuilds a match from an untrusted action history, checking every action.
    public static func replay(
        header: MatchHeader,
        configuration: Rules.Configuration,
        actions: [Rules.Action]
    ) throws(MatchError<Rules.RuleViolation>) -> Match {
        var match = try Match(header: header, configuration: configuration)
        let limit = Rules.maximumActions(for: configuration)
        guard actions.count <= limit else { throw .tooManyActions(count: actions.count, limit: limit) }
        for (index, action) in actions.enumerated() {
            guard let seat = match.outcome.seatToAct else { throw .gameAlreadyFinished }
            switch Rules.apply(action, by: seat, to: match.state) {
            case .success(let next):
                match.state = next
                match.actions.append(action)
            case .failure(let violation):
                throw .illegalAction(index: index, violation: violation)
            }
        }
        return match
    }

    public var outcome: GameOutcome { Rules.outcome(of: state) }

    /// Number of actions taken so far. Turn 0 is a fresh challenge.
    public var turnNumber: Int { actions.count }

    /// The seat that took the most recent action, or nil before the first move.
    public var lastActor: Seat? {
        guard !actions.isEmpty else { return nil }
        // Turn-based two-player games alternate strictly in protocol v1.
        return actions.count % 2 == 1 ? header.firstSeat : header.firstSeat.opponent
    }

    /// The seat whose device produced this snapshot: the last actor, or the
    /// challenger (seat one) when no move has been made yet.
    public var producedBy: Seat { lastActor ?? .one }

    /// Returns a new match with `action` applied for `seat`.
    public func applying(_ action: Rules.Action, by seat: Seat) throws(MatchError<Rules.RuleViolation>) -> Match {
        guard let toAct = outcome.seatToAct else { throw .gameAlreadyFinished }
        guard toAct == seat else { throw .notYourTurn(expected: toAct, found: seat) }
        switch Rules.apply(action, by: seat, to: state) {
        case .success(let next):
            var copy = self
            copy.state = next
            copy.actions.append(action)
            return copy
        case .failure(let violation):
            throw .illegalAction(index: actions.count, violation: violation)
        }
    }

    /// True when `other` is this match continued by zero or more further actions.
    public func isPrefix(of other: Match) -> Bool {
        header == other.header
            && configuration == other.configuration
            && actions.count <= other.actions.count
            && Array(other.actions.prefix(actions.count)) == actions
    }

    /// Creates the next match in a rematch chain, from the point of view of the
    /// player starting it (`initiator`, a seat in this match). The initiator
    /// becomes seat one of the new match; whoever moved first this time moves
    /// second next time; the series tally carries over in the new numbering; each
    /// person keeps their colour.
    public func rematchHeader(initiator: Seat, newMatchID: MatchID = MatchID()) -> MatchHeader {
        let tallyAfterThis = header.series.recording(outcome)
        let tally = initiator == .one ? tallyAfterThis : tallyAfterThis.swapped
        let initiatorMovedFirst = header.firstSeat == initiator
        return MatchHeader(
            matchID: newMatchID,
            gameID: header.gameID,
            rulesVersion: header.rulesVersion,
            firstSeat: initiatorMovedFirst ? .two : .one,
            previousMatchID: header.matchID,
            series: tally,
            rivalryID: header.rivalryID,
            // A seat-two initiator moves to seat one, so the colours flip with them.
            coloursSwapped: header.coloursSwapped != (initiator == .two)
        )
    }
}
