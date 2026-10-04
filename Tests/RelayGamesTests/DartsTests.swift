import Foundation
import RelayCore
@testable import RelayGames
import Testing

private func hit(_ segment: DartsBoard.Segment) -> Darts.Hit { DartsBoard.target(for: segment) }
private func single(_ n: Int) -> Darts.Hit { hit(.init(ring: .single, number: n)) }
private func treble(_ n: Int) -> Darts.Hit { hit(.init(ring: .treble, number: n)) }
private func double(_ n: Int) -> Darts.Hit { hit(.init(ring: .double, number: n)) }
private let missHit = Darts.Hit(x: 0, y: 2_500)

private func dartsHeader(firstSeat: Seat = .one) -> MatchHeader {
    MatchHeader(gameID: Darts.gameID, rulesVersion: Darts.rulesVersion, firstSeat: firstSeat)
}

private func dartsMatch(_ visits: [[Darts.Hit]], configuration: Darts.Configuration = .standard) throws -> Match<Darts> {
    try Match<Darts>.replay(header: dartsHeader(), configuration: configuration, actions: visits.map { Darts.Action(hits: $0) })
}

@Suite("Dartboard scoring")
struct DartsBoardTests {
    @Test func everySegmentCentreScoresItself() {
        for number in DartsBoard.numbers {
            for ring in [DartsBoard.Ring.single, .double, .treble] {
                let segment = DartsBoard.Segment(ring: ring, number: number)
                #expect(DartsBoard.segment(at: DartsBoard.target(for: segment)) == segment, "\(segment.shortName)")
            }
        }
        #expect(DartsBoard.segment(at: .init(x: 0, y: 0)).points == 50)
        #expect(DartsBoard.segment(at: .init(x: 100, y: 0)).points == 25)
        #expect(DartsBoard.segment(at: missHit) == .miss)
    }

    @Test func numbersRunClockwiseFromTwentyAtTheTop() {
        #expect(DartsBoard.segment(at: .init(x: 0, y: 1_300)).number == 20)
        #expect(DartsBoard.segment(at: .init(x: 1_300, y: 0)).number == 6)
        #expect(DartsBoard.segment(at: .init(x: 0, y: -1_300)).number == 3)
        #expect(DartsBoard.segment(at: .init(x: -1_300, y: 0)).number == 11)
    }

    @Test func ringEdgesAreInclusiveOfTheInnerRing() {
        #expect(DartsBoard.segment(at: .init(x: 0, y: DartsBoard.trebleInnerRadius)).ring == .single)
        #expect(DartsBoard.segment(at: .init(x: 0, y: DartsBoard.trebleInnerRadius + 1)).ring == .treble)
        #expect(DartsBoard.segment(at: .init(x: 0, y: DartsBoard.trebleOuterRadius)).ring == .treble)
        #expect(DartsBoard.segment(at: .init(x: 0, y: DartsBoard.doubleOuterRadius)).ring == .double)
        #expect(DartsBoard.segment(at: .init(x: 0, y: DartsBoard.doubleOuterRadius + 1)) == .miss)
    }

    /// Every point gets exactly one sector, matching a floating-point reference away from edges.
    @Test func sectorsMatchAnAngleReference() {
        var rng = SeededGenerator(seed: 7)
        for _ in 0..<20_000 {
            let x = Int.random(in: -1_600...1_600, using: &rng)
            let y = Int.random(in: -1_600...1_600, using: &rng)
            guard x != 0 || y != 0 else { continue }
            var degrees = atan2(Double(x), Double(y)) * 180 / .pi // clockwise from up
            if degrees < 0 { degrees += 360 }
            let offset = (degrees + 9).truncatingRemainder(dividingBy: 18)
            guard offset > 0.01, offset < 17.99 else { continue } // too close to an edge to judge
            let expected = DartsBoard.numbers[Int((degrees + 9) / 18) % 20]
            #expect(DartsBoard.numbers[DartsBoard.sectorIndex(x: Int64(x), y: Int64(y))] == expected)
        }
    }
}

@Suite("Darts rules")
struct DartsRulesTests {
    @Test func visitsCountDownAndAlternate() throws {
        let match = try dartsMatch([[treble(20), treble(20), single(1)], [single(5), single(5), single(5)]])
        #expect(match.state.remaining(for: .one) == 201 - 121)
        #expect(match.state.remaining(for: .two) == 201 - 15)
        #expect(match.outcome == .inProgress(toAct: .one))
        #expect(match.lastActor == .two)
    }

    @Test func exactZeroWinsAndEndsTheVisitEarly() throws {
        let opening = [[treble(20), treble(20), treble(20)], [single(1), single(1), single(1)]]
        // 201 - 180 = 21: single 1 then single 20 finishes on the second dart.
        let match = try dartsMatch(opening + [[single(1), single(20)]])
        #expect(match.outcome == .won(by: .one))
        #expect(match.state.lastVisit?.result == .finished)
        // A third dart after the finish is rejected.
        #expect(throws: MatchError<Darts.RuleViolation>.illegalAction(index: 2, violation: .dartsAfterVisitEnded)) {
            try dartsMatch(opening + [[single(1), single(20), single(5)]])
        }
    }

    @Test func goingBelowZeroIsABustThatScoresNothing() throws {
        let opening = [[treble(20), treble(20), treble(20)], [single(1), single(1), single(1)]]
        // 21 left: 20 then 5 goes below zero, so the visit busts on its second dart.
        let match = try dartsMatch(opening + [[single(20), single(5)]])
        #expect(match.state.lastVisit?.result == .bust)
        #expect(match.state.lastVisit?.points == 0)
        #expect(match.state.remaining(for: .one) == 21)
        #expect(match.outcome == .inProgress(toAct: .two))
    }

    @Test func aVisitMustUseAllThreeDartsUnlessItEnds() throws {
        #expect(throws: MatchError<Darts.RuleViolation>.illegalAction(index: 0, violation: .visitCutShort)) {
            try dartsMatch([[single(20), single(20)]])
        }
        #expect(throws: MatchError<Darts.RuleViolation>.illegalAction(index: 0, violation: .emptyVisit)) {
            try dartsMatch([[]])
        }
        #expect(throws: MatchError<Darts.RuleViolation>.illegalAction(index: 0, violation: .tooManyDarts(4))) {
            try dartsMatch([[missHit, missHit, missHit, missHit]])
        }
        #expect(throws: MatchError<Darts.RuleViolation>.illegalAction(index: 0, violation: .outOfReach)) {
            try dartsMatch([[missHit, missHit, Darts.Hit(x: 99_999, y: 0)]])
        }
    }

    @Test func afterTheLastRoundTheLowerScoreWins() throws {
        let short = Darts.Configuration(startingScore: 301, rounds: 2)
        let match = try dartsMatch([
            [single(20), single(20), single(20)], [single(1), single(1), single(1)],
            [single(20), missHit, missHit], [single(1), single(1), single(1)],
        ], configuration: short)
        #expect(match.outcome == .won(by: .one))
        let level = try dartsMatch([
            [single(5), missHit, missHit], [single(5), missHit, missHit],
            [missHit, missHit, missHit], [missHit, missHit, missHit],
        ], configuration: short)
        #expect(level.outcome == .draw)
    }

    @Test func progressScoresAPartialVisit() throws {
        let match = try dartsMatch([])
        let progress = match.state.progress(of: [treble(20)], by: .one)
        #expect(progress.points == 60)
        #expect(progress.remainingAfter == 141)
        #expect(!progress.isComplete)
    }

    @Test func actionsEncodeAsAFlatIntegerArray() throws {
        let action = Darts.Action(hits: [Darts.Hit(x: 1, y: -2), Darts.Hit(x: 300, y: 4)])
        let json = String(decoding: try JSONEncoder().encode(action), as: UTF8.self)
        #expect(json == "[1,-2,300,4]")
        #expect(try JSONDecoder().decode(Darts.Action.self, from: Data(json.utf8)) == action)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Darts.Action.self, from: Data("[1,2,3]".utf8)) }
    }
}

@Suite("Darts practice bot")
struct DartsBotTests {
    @Test(arguments: DartsBot.Difficulty.allCases)
    func playsLegalGamesToTheEnd(difficulty: DartsBot.Difficulty) throws {
        let bot = DartsBot(difficulty: difficulty)
        var rng = SeededGenerator(seed: 11)
        for _ in 0..<40 {
            var match = try Match<Darts>(header: dartsHeader(), configuration: .standard)
            while let seat = match.outcome.seatToAct {
                let visit = try #require(bot.throwVisit(in: match.state, using: &rng))
                match = try match.applying(visit, by: seat)
            }
            #expect(match.outcome.isFinished)
        }
    }

    @Test func sharperBotsFinishFaster() throws {
        func averageVisits(_ difficulty: DartsBot.Difficulty) throws -> Double {
            let bot = DartsBot(difficulty: difficulty)
            var rng = SeededGenerator(seed: 3)
            var total = 0
            for _ in 0..<60 {
                var match = try Match<Darts>(header: dartsHeader(), configuration: Darts.Configuration(startingScore: 201, rounds: 30))
                while let seat = match.outcome.seatToAct {
                    match = try match.applying(try #require(bot.throwVisit(in: match.state, using: &rng)), by: seat)
                }
                total += match.state.visits.count
            }
            return Double(total) / 60
        }
        let casual = try averageVisits(.casual), sharp = try averageVisits(.sharp)
        #expect(sharp < casual)
    }

    @Test func aimsAtACheckoutWhenOneIsAvailable() {
        let bot = DartsBot(difficulty: .standard)
        #expect(bot.target(remaining: 32) == .init(ring: .double, number: 16))
        #expect(bot.target(remaining: 17) == .init(ring: .single, number: 17))
        #expect(bot.target(remaining: 37) == .init(ring: .single, number: 17))
        #expect(bot.target(remaining: 50) == .init(ring: .bull, number: 25))
        #expect(bot.target(remaining: 150) == .init(ring: .treble, number: 20))
    }

    @Test func flickSpeedSetsHeightAndItsLineSetsDirection() throws {
        let start = (x: 0.5, y: 1.3)
        let release = (x: 0.5, y: 1.0)
        // A firm, straight flick from the middle reaches the bull.
        let firm = try #require(DartsAim.flickTarget(start: start, release: release, velocity: (0, -2.75)))
        #expect(abs(firm.x - 0.5) < 0.001)
        #expect(abs(firm.y - 0.5) < 0.01)
        // Harder flies higher (smaller y), softer drops lower.
        let hard = try #require(DartsAim.flickTarget(start: start, release: release, velocity: (0, -3.9)))
        #expect(hard.y < firm.y)
        let soft = try #require(DartsAim.flickTarget(start: start, release: release, velocity: (0, -1.5)))
        #expect(soft.y > firm.y)
        // A flick angled left lands left; releasing off-centre lands off-centre.
        let left = try #require(DartsAim.flickTarget(start: start, release: release, velocity: (-0.6, -2.75)))
        #expect(left.x < 0.45)
        let offCentre = try #require(DartsAim.flickTarget(start: (0.7, 1.3), release: (0.7, 1.0), velocity: (0, -2.75)))
        #expect(abs(offCentre.x - 0.7) < 0.001)
        // A tap, a downward drag, or stopping before letting go is not a throw.
        #expect(DartsAim.flickTarget(start: start, release: start, velocity: (0, 0)) == nil)
        #expect(DartsAim.flickTarget(start: start, release: (0.5, 1.4), velocity: (0, 2)) == nil)
        #expect(DartsAim.flickTarget(start: start, release: release, velocity: (0, -0.2)) == nil)
    }

    @Test func aFlickLandsOnTheBoardSegmentItWasAimedAt() throws {
        // Board widths to board units, as the throw view converts them.
        func hit(_ target: (x: Double, y: Double)) -> Darts.Hit {
            Darts.Hit(x: Int(((target.x - 0.5) * 4_500).rounded()), y: Int(((0.5 - target.y) * 4_500).rounded()))
        }
        let up = try #require(DartsAim.flickTarget(start: (0.5, 1.3), release: (0.5, 1.0), velocity: (0, -3.9)))
        #expect(DartsBoard.segment(at: hit(up)).number == 20)
        // A feeble flick falls short of the board.
        let feeble = try #require(DartsAim.flickTarget(start: (0.5, 1.3), release: (0.5, 1.2), velocity: (0, -0.6)))
        #expect(DartsBoard.segment(at: hit(feeble)) == .miss)
    }

    @Test func wildFlicksScatterMore() {
        #expect(DartsAim.scatter(forSpeed: 3) == DartsAim.releaseScatter)
        #expect(DartsAim.scatter(forSpeed: 10) > DartsAim.releaseScatter)
    }
}
