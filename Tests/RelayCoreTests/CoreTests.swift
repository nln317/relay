import Foundation
import RelayCore
import Testing

@Suite("Identifiers")
struct IdentifierTests {
    @Test(arguments: ["four-in-a-row", "darts", "8-ball", "a", String(repeating: "x", count: 32)])
    func validGameIDs(value: String) {
        #expect(GameID(value)?.rawValue == value)
    }

    @Test(arguments: ["", "Four", "four in a row", "darts/../x", "émoji", "a_b", String(repeating: "x", count: 33), "<script>"])
    func invalidGameIDs(value: String) {
        #expect(GameID(value) == nil)
    }

    @Test func gameIDDecodingValidates() throws {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([GameID].self, from: Data(#"["BAD ID"]"#.utf8)) }
        let ok = try JSONDecoder().decode([GameID].self, from: Data(#"["darts"]"#.utf8))
        #expect(ok == [GameID(constant: "darts")])
    }

    @Test func matchIDRoundTripsAndRejectsGarbage() throws {
        let id = MatchID()
        let data = try JSONEncoder().encode([id])
        #expect(try JSONDecoder().decode([MatchID].self, from: data) == [id])
        #expect(MatchID(string: "not-a-uuid") == nil)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([MatchID].self, from: Data(#"["nope"]"#.utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([MatchID].self, from: Data("[42]".utf8)) }
    }

    @Test func rulesVersionsOrder() {
        #expect(RulesVersion(1) < RulesVersion(2))
    }
}

@Suite("Seats and tallies")
struct SeatTests {
    @Test func opponents() {
        #expect(Seat.one.opponent == .two)
        #expect(Seat.two.opponent == .one)
    }

    @Test func tallyRecordsAndSwaps() {
        let tally = SeriesTally.empty
            .recording(.won(by: .one))
            .recording(.won(by: .one))
            .recording(.won(by: .two))
            .recording(.draw)
            .recording(.inProgress(toAct: .one))
        #expect(tally == SeriesTally(seatOneWins: 2, seatTwoWins: 1, draws: 1))
        #expect(tally.swapped == SeriesTally(seatOneWins: 1, seatTwoWins: 2, draws: 1))
        #expect(tally.wins(for: .one) == 2)
        #expect(tally.gamesPlayed == 4)
    }

    @Test func invalidTallies() {
        #expect(!SeriesTally(seatOneWins: -1, seatTwoWins: 0, draws: 0).isValid)
        #expect(!SeriesTally(seatOneWins: 10_001, seatTwoWins: 0, draws: 0).isValid)
        #expect(SeriesTally(seatOneWins: 3, seatTwoWins: 4, draws: 0).isValid)
    }

    @Test func outcomeHelpers() {
        #expect(GameOutcome.inProgress(toAct: .two).seatToAct == .two)
        #expect(GameOutcome.won(by: .one).winner == .one)
        #expect(GameOutcome.draw.isFinished)
        #expect(!GameOutcome.inProgress(toAct: .one).isFinished)
    }

    @Test func loadoutLimits() {
        let ok = CosmeticLoadout(items: ["disc": CosmeticID("neon-disc")!])
        #expect(ok.isWithinLimits)
        var tooMany: [String: CosmeticID] = [:]
        for index in 0..<13 { tooMany["slot-\(index)"] = CosmeticID("x")! }
        #expect(!CosmeticLoadout(items: tooMany).isWithinLimits)
        #expect(!CosmeticLoadout(items: ["Bad Slot": CosmeticID("x")!]).isWithinLimits)
    }
}
