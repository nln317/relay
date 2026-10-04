import RelayCore
@testable import RelayGames
import Testing

@Suite("Practice bot")
struct FourInARowBotTests {
    @Test(arguments: FourInARowBot.Difficulty.allCases)
    func takesAnImmediateWin(difficulty: FourInARowBot.Difficulty) throws {
        // Seat one has (0,0) (1,0) (2,0); column 3 wins.
        let match = try play([0, 0, 1, 1, 2, 6])
        var rng = SeededGenerator(seed: 1)
        #expect(FourInARowBot(difficulty: difficulty).chooseColumn(in: match.state, using: &rng) == 3)
    }

    @Test(arguments: [FourInARowBot.Difficulty.standard, .sharp])
    func blocksAnImmediateLoss(difficulty: FourInARowBot.Difficulty) throws {
        // Seat one threatens column 3; seat two to act.
        let match = try play([0, 0, 1, 1, 2])
        var rng = SeededGenerator(seed: 2)
        #expect(FourInARowBot(difficulty: difficulty).chooseColumn(in: match.state, using: &rng) == 3)
    }

    @Test func standardAvoidsHandingOverAWin() throws {
        // Seat two (bot) to act in a tactical mid-game position. Seat one has
        // (0,1) (1,1) (2,1) waiting on (3,1), so filling (3,0) would hand it a win.
        let match = try play([1, 0, 0, 2, 2, 6, 1])
        var rng = SeededGenerator(seed: 3)
        let bot = FourInARowBot(difficulty: .standard)
        let choice = try #require(bot.chooseColumn(in: match.state, using: &rng))
        #expect(choice != 3)
        let after = try match.applying(.init(column: choice), by: .two)
        // Whatever it picks, seat one must not have an immediate win afterwards
        // unless every move allows one.
        let allowsWin = after.state.openColumns.contains { bot.wins(column: $0, for: .one, in: after.state) }
        let everyMoveAllowsWin = match.state.openColumns.allSatisfy { column in
            guard let next = try? match.applying(.init(column: column), by: .two) else { return true }
            return next.state.openColumns.contains { bot.wins(column: $0, for: .one, in: next.state) }
        }
        #expect(!allowsWin || everyMoveAllowsWin)
    }

    @Test(arguments: FourInARowBot.Difficulty.allCases)
    func alwaysPlaysLegalMovesToTheEnd(difficulty: FourInARowBot.Difficulty) throws {
        var rng = SeededGenerator(seed: 4)
        let bot = FourInARowBot(difficulty: difficulty)
        for _ in 0..<(difficulty == .sharp ? 5 : 50) {
            var match = try play([])
            while let seat = match.outcome.seatToAct {
                let column = try #require(bot.chooseColumn(in: match.state, using: &rng))
                match = try match.applying(.init(column: column), by: seat)
            }
            #expect(bot.chooseColumn(in: match.state, using: &rng) == nil)
        }
    }

    @Test func strongerLevelsBeatCasual() throws {
        var rng = SeededGenerator(seed: 5)
        var standardWins = 0
        let games = 40
        for game in 0..<games {
            let standardSeat: Seat = game.isMultiple(of: 2) ? .one : .two
            var match = try play([])
            while let seat = match.outcome.seatToAct {
                let bot = FourInARowBot(difficulty: seat == standardSeat ? .standard : .casual)
                let column = try #require(bot.chooseColumn(in: match.state, using: &rng))
                match = try match.applying(.init(column: column), by: seat)
            }
            if match.outcome == .won(by: standardSeat) { standardWins += 1 }
        }
        #expect(standardWins > games * 3 / 4)
    }
}
