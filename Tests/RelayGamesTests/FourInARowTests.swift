import Foundation
import RelayCore
@testable import RelayGames
import Testing

typealias C4 = FourInARow

func header(firstSeat: Seat = .one) -> MatchHeader {
    MatchHeader(gameID: C4.gameID, rulesVersion: C4.rulesVersion, firstSeat: firstSeat)
}

func play(_ columns: [Int], firstSeat: Seat = .one, configuration: C4.Configuration = .standard) throws -> Match<C4> {
    try Match<C4>.replay(header: header(firstSeat: firstSeat), configuration: configuration, actions: columns.map(C4.Action.init(column:)))
}

func cells(_ pairs: [(Int, Int)]) -> Set<C4.Cell> {
    Set(pairs.map { C4.Cell(column: $0.0, row: $0.1) })
}

/// Independent oracle: scans the whole board for any line, with no incremental tricks.
func naiveWinner(_ state: C4.State) -> (Seat, Set<C4.Cell>)? {
    let config = state.configuration
    var found: (Seat, Set<C4.Cell>)?
    for column in 0..<config.columns {
        for row in 0..<config.rows {
            for (dc, dr) in [(1, 0), (0, 1), (1, 1), (1, -1)] {
                let window = (0..<config.connect).map { C4.Cell(column: column + $0 * dc, row: row + $0 * dr) }
                guard window.allSatisfy({ state.contains($0) }),
                      let seat = state.disc(at: window[0]),
                      window.allSatisfy({ state.disc(at: $0) == seat })
                else { continue }
                if let existing = found {
                    #expect(existing.0 == seat, "two different winners on one board")
                    found = (seat, existing.1.union(window))
                } else {
                    found = (seat, Set(window))
                }
            }
        }
    }
    return found
}

@Suite("Four in a Row rules")
struct FourInARowRuleTests {
    @Test func newGameIsEmptyAndFirstSeatActs() throws {
        let match = try play([])
        #expect(match.outcome == .inProgress(toAct: .one))
        #expect(match.state.openColumns == Array(0..<7))
        #expect(match.turnNumber == 0)
        #expect(match.lastActor == nil)
        #expect(match.producedBy == .one)
        let other = try play([], firstSeat: .two)
        #expect(other.outcome == .inProgress(toAct: .two))
    }

    @Test func discsStackFromTheBottom() throws {
        let match = try play([3, 3, 3])
        #expect(match.state.disc(at: .init(column: 3, row: 0)) == .one)
        #expect(match.state.disc(at: .init(column: 3, row: 1)) == .two)
        #expect(match.state.disc(at: .init(column: 3, row: 2)) == .one)
        #expect(match.state.height(ofColumn: 3) == 3)
        #expect(match.state.lastMove == .init(column: 3, row: 2))
        #expect(match.lastActor == .one)
        #expect(match.outcome == .inProgress(toAct: .two))
    }

    @Test func turnsAlternate() throws {
        var match = try play([])
        for (index, column) in [0, 1, 2, 3, 4, 5].enumerated() {
            let seat: Seat = index.isMultiple(of: 2) ? .one : .two
            #expect(match.outcome.seatToAct == seat)
            match = try match.applying(.init(column: column), by: seat)
        }
    }

    @Test func horizontalWin() throws {
        let match = try play([0, 0, 1, 1, 2, 2, 3])
        #expect(match.outcome == .won(by: .one))
        #expect(match.state.winningCells == cells([(0, 0), (1, 0), (2, 0), (3, 0)]))
    }

    @Test func verticalWin() throws {
        let match = try play([4, 5, 4, 5, 4, 5, 4])
        #expect(match.outcome == .won(by: .one))
        #expect(match.state.winningCells == cells([(4, 0), (4, 1), (4, 2), (4, 3)]))
    }

    @Test func risingDiagonalWin() throws {
        // Seat one builds (0,0) (1,1) (2,2) (3,3).
        let match = try play([0, 1, 1, 2, 2, 3, 2, 3, 3, 6, 3])
        #expect(match.outcome == .won(by: .one))
        #expect(match.state.winningCells == cells([(0, 0), (1, 1), (2, 2), (3, 3)]))
    }

    @Test func fallingDiagonalWin() throws {
        // Seat one builds (3,0) (2,1) (1,2) (0,3).
        let match = try play([3, 2, 2, 1, 1, 0, 1, 0, 0, 6, 0])
        #expect(match.outcome == .won(by: .one))
        #expect(match.state.winningCells == cells([(3, 0), (2, 1), (1, 2), (0, 3)]))
    }

    @Test func secondSeatCanWin() throws {
        let match = try play([0, 6, 0, 6, 1, 6, 1, 6])
        #expect(match.outcome == .won(by: .two))
        #expect(match.lastActor == .two)
    }

    @Test func fiveInARowHighlightsAllFive() throws {
        // Seat one: 0,1,  3,4 then fills 2.
        let match = try play([0, 0, 1, 1, 3, 3, 4, 4, 2])
        #expect(match.outcome == .won(by: .one))
        #expect(match.state.winningCells == cells([(0, 0), (1, 0), (2, 0), (3, 0), (4, 0)]))
    }

    @Test func crossingLinesFromOneDisc() {
        // Seat one owns (0,0) (1,0) (2,0) and (4,1) (5,2) (6,3); the disc at (3,0)
        // completes a horizontal and a diagonal line at once.
        var state = C4.initialState(for: .standard, firstSeat: .one)
        for column in [0, 1, 2] { _ = state.place(.one, inColumn: column) }
        // Diagonal (3,0) (4,1) (5,2) (6,3) for seat one with seat-two padding underneath.
        _ = state.place(.two, inColumn: 4)
        _ = state.place(.one, inColumn: 4) // (4,1)
        _ = state.place(.two, inColumn: 5)
        _ = state.place(.two, inColumn: 5)
        _ = state.place(.one, inColumn: 5) // (5,2)
        _ = state.place(.two, inColumn: 6)
        _ = state.place(.two, inColumn: 6)
        _ = state.place(.two, inColumn: 6)
        _ = state.place(.one, inColumn: 6) // (6,3)
        #expect(state.outcome.isFinished == false)
        _ = state.place(.one, inColumn: 3) // (3,0): completes horizontal and diagonal
        #expect(state.outcome == .won(by: .one))
        #expect(state.winningCells == cells([(0, 0), (1, 0), (2, 0), (3, 0), (4, 1), (5, 2), (6, 3)]))
    }

    @Test func fullBoardWithoutLineIsADraw() throws {
        let sequence = [3, 4, 4, 6, 0, 3, 5, 2, 6, 5, 0, 6, 5, 0, 3, 6, 5, 6, 1, 3, 1, 3, 6, 5, 2, 0, 5, 3, 4, 4, 0, 1, 1, 1, 0, 1, 4, 2, 4, 2, 2, 2]
        let beforeLast = try play(Array(sequence.dropLast()))
        #expect(beforeLast.outcome.isFinished == false)
        let match = try play(sequence)
        #expect(match.outcome == .draw)
        #expect(match.state.openColumns.isEmpty)
        #expect(match.state.winningCells.isEmpty)
        #expect(naiveWinner(match.state) == nil)
    }

    @Test func winOnTheFinalCellIsAWinNotADraw() throws {
        let sequence = [1, 2, 4, 6, 5, 2, 1, 0, 2, 5, 4, 0, 6, 5, 4, 1, 5, 2, 1, 6, 3, 4, 0, 4, 5, 2, 5, 4, 6, 2, 6, 3, 6, 0, 1, 1, 0, 0, 3, 3, 3, 3]
        let match = try play(sequence)
        #expect(sequence.count == 42)
        #expect(match.outcome == .won(by: .two))
        #expect(match.state.openColumns.isEmpty)
    }

    @Test func fullColumnIsRejected() throws {
        let match = try play([2, 2, 2, 2, 2, 2])
        #expect(match.state.isColumnOpen(2) == false)
        #expect(throws: MatchError<C4.RuleViolation>.illegalAction(index: 6, violation: .columnFull(2))) {
            try match.applying(.init(column: 2), by: .one)
        }
    }

    @Test(arguments: [-1, 7, 100, Int.min, Int.max])
    func outOfRangeColumnIsRejected(column: Int) throws {
        let match = try play([])
        #expect(throws: MatchError<C4.RuleViolation>.illegalAction(index: 0, violation: .columnOutOfRange(column))) {
            try match.applying(.init(column: column), by: .one)
        }
    }

    @Test func wrongSeatIsRejected() throws {
        let match = try play([3])
        #expect(throws: MatchError<C4.RuleViolation>.notYourTurn(expected: .two, found: .one)) {
            try match.applying(.init(column: 3), by: .one)
        }
        #expect(C4.apply(.init(column: 0), by: .one, to: match.state) == .failure(.notYourTurn))
    }

    @Test func noMovesAfterAWin() throws {
        let match = try play([0, 0, 1, 1, 2, 2, 3])
        #expect(throws: MatchError<C4.RuleViolation>.gameAlreadyFinished) {
            try match.applying(.init(column: 5), by: .two)
        }
        #expect(C4.apply(.init(column: 5), by: .two, to: match.state) == .failure(.gameOver))
        #expect(throws: MatchError<C4.RuleViolation>.gameAlreadyFinished) {
            try play([0, 0, 1, 1, 2, 2, 3, 5])
        }
    }

    @Test func replayRejectsIllegalHistoryWithItsIndex() {
        #expect(throws: MatchError<C4.RuleViolation>.illegalAction(index: 6, violation: .columnFull(0))) {
            try play([0, 0, 0, 0, 0, 0, 0])
        }
    }

    @Test func replayRejectsOverlongHistory() {
        #expect(throws: MatchError<C4.RuleViolation>.tooManyActions(count: 43, limit: 42)) {
            try play(Array(repeating: 0, count: 43))
        }
    }

    @Test func replayRejectsWrongGameAndVersion() {
        let wrongGame = MatchHeader(gameID: GameID(constant: "darts"), rulesVersion: C4.rulesVersion)
        #expect(throws: MatchError<C4.RuleViolation>.gameMismatch(expected: C4.gameID, found: GameID(constant: "darts"))) {
            try Match<C4>(header: wrongGame, configuration: .standard)
        }
        let futureRules = MatchHeader(gameID: C4.gameID, rulesVersion: RulesVersion(99))
        #expect(throws: MatchError<C4.RuleViolation>.unsupportedRulesVersion(RulesVersion(99))) {
            try Match<C4>(header: futureRules, configuration: .standard)
        }
    }

    @Test(arguments: [
        C4.Configuration(columns: 3, rows: 6, connect: 3),
        C4.Configuration(columns: 7, rows: 13, connect: 4),
        C4.Configuration(columns: 7, rows: 6, connect: 7),
        C4.Configuration(columns: 7, rows: 6, connect: 2),
        C4.Configuration(columns: -7, rows: 6, connect: 4),
    ])
    func unsupportedConfigurationsAreRejected(configuration: C4.Configuration) {
        #expect(throws: MatchError<C4.RuleViolation>.unsupportedConfiguration) {
            try Match<C4>(header: header(), configuration: configuration)
        }
    }

    @Test func variantBoardsWork() throws {
        let small = C4.Configuration(columns: 5, rows: 4, connect: 3)
        let match = try play([0, 0, 1, 1, 2], configuration: small)
        #expect(match.outcome == .won(by: .one))
        #expect(try play([0, 0, 0, 0], configuration: small).state.isColumnOpen(0) == false)
    }

    @Test func replayIsDeterministic() throws {
        let sequence = [3, 4, 4, 6, 0, 3, 5, 2, 6, 5, 0, 6].map(C4.Action.init(column:))
        let fixed = header()
        let first = try Match<C4>.replay(header: fixed, configuration: .standard, actions: sequence)
        let second = try Match<C4>.replay(header: fixed, configuration: .standard, actions: sequence)
        #expect(first == second)
    }

    @Test func actionsEncodeAsBareIntegers() throws {
        let data = try JSONEncoder().encode([C4.Action(column: 3), C4.Action(column: 0)])
        #expect(String(decoding: data, as: UTF8.self) == "[3,0]")
        #expect(try JSONDecoder().decode([C4.Action].self, from: data) == [.init(column: 3), .init(column: 0)])
    }
}

@Suite("Four in a Row randomized oracle")
struct FourInARowOracleTests {
    /// Plays many random games and checks the incremental win detection against
    /// a naive whole-board scan after every single move. Also proves every one of
    /// the 69 possible winning windows on a standard board is detected for both seats.
    @Test func incrementalDetectionMatchesNaiveScan() throws {
        var rng = SeededGenerator(seed: 0xC4C4)
        var windowsSeen: [Seat: Set<[C4.Cell]>] = [.one: [], .two: []]
        var outcomes: [String: Int] = [:]
        for _ in 0..<15_000 {
            var match = try play([], firstSeat: Bool.random(using: &rng) ? .one : .two)
            while let seat = match.outcome.seatToAct {
                let column = match.state.openColumns.randomElement(using: &rng)!
                match = try match.applying(.init(column: column), by: seat)
                let naive = naiveWinner(match.state)
                switch match.outcome {
                case .won(let winner):
                    #expect(naive?.0 == winner)
                    #expect(naive?.1 == match.state.winningCells)
                    #expect(match.state.winningCells.contains(match.state.lastMove!))
                case .draw:
                    #expect(naive == nil)
                    #expect(match.turnNumber == 42)
                case .inProgress:
                    #expect(naive == nil)
                }
            }
            switch match.outcome {
            case .won(let winner):
                outcomes["win", default: 0] += 1
                for window in allWindows() where window.allSatisfy({ match.state.winningCells.contains($0) }) {
                    windowsSeen[winner, default: []].insert(window)
                }
            case .draw: outcomes["draw", default: 0] += 1
            case .inProgress: Issue.record("game ended in progress")
            }
        }
        #expect(allWindows().count == 69)
        #expect(windowsSeen[.one]?.count == 69)
        #expect(windowsSeen[.two]?.count == 69)
        #expect((outcomes["draw"] ?? 0) > 0)
    }

    func allWindows() -> [[C4.Cell]] {
        var windows: [[C4.Cell]] = []
        for column in 0..<7 {
            for row in 0..<6 {
                for (dc, dr) in [(1, 0), (0, 1), (1, 1), (1, -1)] {
                    let window = (0..<4).map { C4.Cell(column: column + $0 * dc, row: row + $0 * dr) }
                    if window.allSatisfy({ (0..<7).contains($0.column) && (0..<6).contains($0.row) }) {
                        windows.append(window)
                    }
                }
            }
        }
        return windows
    }
}

@Suite("Rematch headers")
struct RematchTests {
    @Test func rematchAlternatesFirstMoverAndCarriesTheTally() throws {
        // Seat one moved first and won.
        let finished = try play([0, 0, 1, 1, 2, 2, 3])
        #expect(finished.outcome == .won(by: .one))

        // Seat two (the loser) starts the rematch: becomes seat one of the new match.
        let byLoser = finished.rematchHeader(initiator: .two)
        #expect(byLoser.previousMatchID == finished.header.matchID)
        #expect(byLoser.matchID != finished.header.matchID)
        // The loser did not move first last time, so they move first now.
        #expect(byLoser.firstSeat == .one)
        // The old seat-one win now belongs to new seat two.
        #expect(byLoser.series == SeriesTally(seatOneWins: 0, seatTwoWins: 1, draws: 0))

        // Seat one (the winner, who moved first) starts it instead.
        let byWinner = finished.rematchHeader(initiator: .one)
        #expect(byWinner.firstSeat == .two)
        #expect(byWinner.series == SeriesTally(seatOneWins: 1, seatTwoWins: 0, draws: 0))
    }

    @Test func everyoneKeepsTheirColourAcrossRematches() throws {
        // Game 1: Ava is seat one (Ember), Ben seat two (Tide). Ava wins.
        let game1 = try play([0, 0, 1, 1, 2, 2, 3])
        #expect(game1.header.coloursSwapped == false)

        // Ben starts the rematch and becomes seat one, so seat one now wears Tide.
        let game2Header = game1.rematchHeader(initiator: .two)
        #expect(game2Header.coloursSwapped)

        // Ava (now seat two) starts game 3 and is seat one again, back in Ember.
        let game2 = try Match<FourInARow>.replay(header: game2Header, configuration: .standard, actions: [0, 1, 0, 1, 0, 1, 0].map(FourInARow.Action.init(column:)))
        #expect(game2.rematchHeader(initiator: .two).coloursSwapped == false)
        // Ben (seat one, wearing Tide) starts game 3 instead: still Tide.
        #expect(game2.rematchHeader(initiator: .one).coloursSwapped)
    }

    @Test func drawsAreCounted() throws {
        let sequence = [3, 4, 4, 6, 0, 3, 5, 2, 6, 5, 0, 6, 5, 0, 3, 6, 5, 6, 1, 3, 1, 3, 6, 5, 2, 0, 5, 3, 4, 4, 0, 1, 1, 1, 0, 1, 4, 2, 4, 2, 2, 2]
        let match = try play(sequence)
        #expect(match.rematchHeader(initiator: .one).series.draws == 1)
    }
}
