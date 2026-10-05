import Foundation
import RelayCore
@testable import RelayGames
import Testing

private typealias V = PoolTable.Vector

private func eightBallState(_ positions: [Int: V?] = [:], cue: V? = PoolTable.headSpot, groups: [Seat: EightBall.Group] = [:], ballInHand: EightBall.BallInHand = .none, afterBreak: Bool = true) -> EightBall.State {
    var state = EightBall.initialState(for: .standard, firstSeat: .one)
    if !positions.isEmpty {
        // Only the listed balls are on the table.
        state.positions = [V?](repeating: nil, count: 16)
        for (ball, position) in positions { state.positions[ball] = position }
    }
    state.positions[0] = cue
    state.groups = groups
    state.ballInHand = ballInHand
    if afterBreak {
        state.turns = [EightBall.Turn(seat: .two, shots: [], startPositions: state.positions, startBallInHand: .behindHeadString)]
    }
    return state
}

/// A shot from `from` straight at `to`.
private func shot(from: V, to: V, power: Int, spinX: Int = 0, spinY: Int = 0, placement: EightBall.Shot.Placement? = nil) -> EightBall.Shot {
    let d = to - from
    let scale = Double(EightBall.directionScale) / max(abs(d.x), abs(d.y))
    return EightBall.Shot(dx: Int((d.x * scale).rounded()), dy: Int((d.y * scale).rounded()), power: power, spinX: spinX, spinY: spinY, placement: placement)
}

/// FNV-1a over the exact bits of every ball position, to pin the physics.
private func fingerprint(_ positions: [V?]) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    func mix(_ value: UInt64) {
        hash ^= value
        hash = hash &* 0x0000_0100_0000_01b3
    }
    for position in positions {
        if let position {
            mix(position.x.bitPattern)
            mix(position.y.bitPattern)
        } else {
            mix(0xdead)
        }
    }
    return hash
}

private let breakShot = EightBall.Shot(dx: 7, dy: -4_096, power: 1_000, placement: .init(x: 640, y: 2_025))

@Suite("8-Ball table and physics")
struct PoolTableTests {
    @Test func rackHasFifteenTouchingBallsWithTheEightInTheMiddle() {
        let rack = PoolTable.rack()
        #expect(rack.count == 16)
        #expect(rack.compactMap { $0 }.count == 16)
        let balls = (1...15).compactMap { rack[$0] }
        for i in balls.indices {
            for j in balls.indices where j > i {
                #expect((balls[i] - balls[j]).length >= PoolTable.ballRadius * 2)
            }
        }
        // Third row, middle: straight above the apex, two rows up.
        let eight = try! #require(rack[8])
        #expect(abs(eight.x - PoolTable.footSpot.x) < 0.001)
        #expect(eight.y < PoolTable.footSpot.y - 90)
    }

    @Test func aStraightShotSinksTheBallInTheCornerPocket() {
        // Ball on the diagonal into the top-left pocket, cue ball behind it.
        let ball = V(x: 400, y: 400)
        let cue = V(x: 700, y: 700)
        var positions = [V?](repeating: nil, count: 16)
        positions[0] = cue
        positions[1] = ball
        let result = PoolTable.simulate(positions: positions, velocity: (ball - cue) * (1 / (ball - cue).length) * 2_500, follow: 0, side: 0, recordFrames: true)
        #expect(result.pocketed == [1])
        #expect(result.firstContact == 1)
        #expect(result.positions[0] != nil)
        #expect(result.frames.count > 10)
        #expect(result.events.contains { if case .pocketed(_, 1, 0) = $0 { true } else { false } })
    }

    @Test func ballsComeToRestAndStayOnTheCloth() {
        var positions = PoolTable.rack()
        positions[0] = PoolTable.Vector(x: 640, y: 2_025)
        let result = PoolTable.simulate(positions: positions, velocity: V(x: 0, y: -6_000), follow: 0, side: 0, recordFrames: false)
        for (index, position) in result.positions.enumerated() {
            guard let position else { #expect(result.pocketed.contains(index)); continue }
            #expect(PoolTable.isOnCloth(V(x: position.x, y: position.y)) || abs(position.x - PoolTable.width / 2) < PoolTable.width)
        }
        #expect(!result.pocketed.isEmpty || result.positions.compactMap { $0 }.count == 16)
    }

    @Test func followAndDrawChangeWhereTheCueBallEndsUp() {
        var positions = [V?](repeating: nil, count: 16)
        positions[0] = V(x: 635, y: 1_800)
        positions[5] = V(x: 635, y: 1_300)
        let velocity = V(x: 0, y: -2_500)
        let plain = PoolTable.simulate(positions: positions, velocity: velocity, follow: 0, side: 0, recordFrames: false)
        let follow = PoolTable.simulate(positions: positions, velocity: velocity, follow: 1, side: 0, recordFrames: false)
        let draw = PoolTable.simulate(positions: positions, velocity: velocity, follow: -1, side: 0, recordFrames: false)
        let plainY = try! #require(plain.positions[0]).y
        #expect(try! #require(follow.positions[0]).y < plainY - 100)
        #expect(try! #require(draw.positions[0]).y > plainY + 100)
    }

    /// The physics must give bit-identical results on every device. If this fails after a
    /// deliberate physics change, update the number (and the rules version: old messages
    /// would replay differently).
    @Test func theBreakIsBitForBitReproducible() {
        let state = EightBall.initialState(for: .standard, firstSeat: .one)
        let first = state.progress(of: [breakShot], by: .one)
        let second = state.progress(of: [breakShot], by: .one)
        #expect(first == second)
        #expect(fingerprint(first.positions) == 18_392_159_876_349_401_478)
    }
}

@Suite("8-Ball rules")
struct EightBallRulesTests {
    @Test func theBreakNeedsTheCueBallPlacedBehindTheHeadString() {
        let state = EightBall.initialState(for: .standard, firstSeat: .one)
        #expect(state.ballInHand == .behindHeadString)
        var unplaced = breakShot
        unplaced.placement = nil
        #expect(EightBall.validate(unplaced, ballInHand: state.ballInHand, positions: state.positions) == .placementMismatch)
        var tooFar = breakShot
        tooFar.placement = .init(x: 640, y: 1_200)
        #expect(EightBall.validate(tooFar, ballInHand: state.ballInHand, positions: state.positions) == .badPlacement)
        #expect(EightBall.validate(breakShot, ballInHand: state.ballInHand, positions: state.positions) == nil)
    }

    @Test func pottingYourOwnBallKeepsTheTurnAndSettlesAnOpenTable() {
        let ball = V(x: 400, y: 400)
        let cue = V(x: 700, y: 700)
        let state = eightBallState([3: ball, 12: V(x: 900, y: 1_800), 8: V(x: 1_000, y: 2_000)], cue: cue)
        let progress = state.progress(of: [shot(from: cue, to: ball, power: 450)], by: .one)
        let result = try! #require(progress.results.first)
        #expect(result.pocketed == [3])
        #expect(result.foul == nil)
        #expect(result.assignedGroup == .solids)
        #expect(result.ending == .continues)
        #expect(progress.groups == [.one: .solids, .two: .stripes])
        #expect(!progress.isComplete)
    }

    @Test func missingPassesTheTurnWithoutBallInHand() {
        let cue = V(x: 635, y: 1_800)
        let state = eightBallState([3: V(x: 635, y: 1_200), 12: V(x: 300, y: 600), 8: V(x: 1_000, y: 2_000)], cue: cue, groups: [.one: .solids, .two: .stripes])
        let progress = state.progress(of: [shot(from: cue, to: V(x: 635, y: 1_200), power: 150)], by: .one)
        let result = try! #require(progress.results.first)
        #expect(result.foul == nil)
        #expect(result.ending == .turnOver)
        #expect(progress.ballInHand == .none)
        #expect(progress.outcome == .inProgress(toAct: .two))
    }

    @Test func hittingTheWrongGroupFirstIsAFoulAndGivesBallInHand() {
        let cue = V(x: 635, y: 1_800)
        let state = eightBallState([3: V(x: 300, y: 600), 12: V(x: 635, y: 1_300), 8: V(x: 1_000, y: 2_000)], cue: cue, groups: [.one: .solids, .two: .stripes])
        let progress = state.progress(of: [shot(from: cue, to: V(x: 635, y: 1_300), power: 300)], by: .one)
        let result = try! #require(progress.results.first)
        #expect(result.firstContact == 12)
        #expect(result.foul == .wrongBallFirst)
        #expect(progress.ballInHand == .anywhere)
        #expect(progress.outcome == .inProgress(toAct: .two))
    }

    @Test func aScratchTakesTheCueBallOffAndTheOpponentMustPlaceIt() throws {
        // Straight at the bottom-right pocket with nothing in the way.
        let cue = V(x: 900, y: 2_200)
        let state = eightBallState([3: V(x: 300, y: 600), 12: V(x: 300, y: 900), 8: V(x: 600, y: 300)], cue: cue, groups: [.one: .solids, .two: .stripes])
        let pocket = PoolTable.pockets[2].target
        let action = EightBall.Action(shots: [shot(from: cue, to: pocket, power: 400)])
        let next = try EightBall.apply(action, by: .one, to: state).get()
        #expect(next.positions[0] == nil)
        #expect(next.ballInHand == .anywhere)
        #expect(next.lastTurn?.shots.first?.foul == .scratch)
        // The other player must put the cue ball down first.
        let unplaced = EightBall.Action(shots: [EightBall.Shot(dx: 0, dy: -4_096, power: 300)])
        #expect(EightBall.apply(unplaced, by: .two, to: next) == .failure(.placementMismatch))
        let onABall = EightBall.Shot(dx: 0, dy: -4_096, power: 300, placement: .init(x: 300, y: 900))
        #expect(EightBall.apply(EightBall.Action(shots: [onABall]), by: .two, to: next) == .failure(.badPlacement))
    }

    @Test func pottingTheEightEarlyLosesAndAfterClearingWins() {
        let eight = V(x: 400, y: 400)
        let cue = V(x: 700, y: 700)
        let early = eightBallState([3: V(x: 1_000, y: 2_000), 12: V(x: 900, y: 1_800), 8: eight], cue: cue, groups: [.one: .solids, .two: .stripes])
        let lost = early.progress(of: [shot(from: cue, to: eight, power: 450)], by: .one)
        #expect(lost.results.first?.ending == .lost)
        #expect(lost.outcome == .won(by: .two))

        let cleared = eightBallState([12: V(x: 900, y: 1_800), 8: eight], cue: cue, groups: [.one: .solids, .two: .stripes])
        let won = cleared.progress(of: [shot(from: cue, to: eight, power: 450)], by: .one)
        #expect(won.results.first?.ending == .won)
        #expect(won.outcome == .won(by: .one))
    }

    @Test func aTurnMustEndOnItsLastShotAndNotBefore() {
        let ball = V(x: 400, y: 400)
        let cue = V(x: 700, y: 700)
        let state = eightBallState([3: ball, 5: V(x: 635, y: 1_500), 12: V(x: 900, y: 1_800), 8: V(x: 1_000, y: 2_000)], cue: cue, groups: [.one: .solids, .two: .stripes])
        let pot = shot(from: cue, to: ball, power: 450)
        #expect(EightBall.apply(EightBall.Action(shots: [pot]), by: .one, to: state) == .failure(.turnCutShort))
        let miss = EightBall.Shot(dx: 0, dy: 4_096, power: 50)
        let tooMany = EightBall.Action(shots: [miss, miss])
        #expect(EightBall.apply(tooMany, by: .one, to: state) == .failure(.shotsAfterTurnEnded))
        #expect(EightBall.apply(EightBall.Action(shots: []), by: .one, to: state) == .failure(.emptyTurn))
        #expect(EightBall.apply(EightBall.Action(shots: [miss]), by: .two, to: state) == .failure(.notYourTurn))
    }

    @Test func shotNumbersAreChecked() {
        let positions = PoolTable.rack()
        #expect(EightBall.validate(EightBall.Shot(dx: 0, dy: 0, power: 10), ballInHand: .none, positions: positions) == .badDirection)
        #expect(EightBall.validate(EightBall.Shot(dx: 5_000, dy: 0, power: 10), ballInHand: .none, positions: positions) == .badDirection)
        #expect(EightBall.validate(EightBall.Shot(dx: 1, dy: 0, power: 0), ballInHand: .none, positions: positions) == .badPower)
        #expect(EightBall.validate(EightBall.Shot(dx: 1, dy: 0, power: 10, spinX: 8, spinY: 8), ballInHand: .none, positions: positions) == .badSpin)
    }

    @Test func turnsEncodeAsFlatIntegers() throws {
        let action = EightBall.Action(shots: [
            EightBall.Shot(dx: 12, dy: -4_096, power: 999, spinX: -3, spinY: 4, placement: .init(x: 640, y: 2_000)),
            EightBall.Shot(dx: -4_096, dy: 77, power: 5),
        ])
        let data = try JSONEncoder().encode(action)
        #expect(String(decoding: data, as: UTF8.self) == "[12,-4096,999,-3,4,1,640,2000,-4096,77,5,0,0,0]")
        #expect(try JSONDecoder().decode(EightBall.Action.self, from: data) == action)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(EightBall.Action.self, from: Data("[1,2,3]".utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(EightBall.Action.self, from: Data("[1,2,3,0,0,2]".utf8)) }
    }
}

@Suite("8-Ball bot")
struct EightBallBotTests {
    @Test(arguments: [EightBallBot.Difficulty.standard, .sharp])
    func botsPlayAWholeGameToAResult(difficulty: EightBallBot.Difficulty) throws {
        var rng = SeededGenerator(seed: 8)
        let bot = EightBallBot(difficulty: difficulty)
        let header = MatchHeader(gameID: EightBall.gameID, rulesVersion: EightBall.rulesVersion)
        var match = try Match<EightBall>(header: header, configuration: .standard)
        var turns = 0
        while let seat = match.outcome.seatToAct, turns < 120 {
            let action = try #require(bot.takeTurn(in: match.state, using: &rng))
            match = try match.applying(action, by: seat)
            turns += 1
        }
        #expect(match.outcome.isFinished)
        // The whole history replays to the same table, as a receiving device would.
        let replayed = try Match<EightBall>.replay(header: header, configuration: .standard, actions: match.actions)
        #expect(replayed.state == match.state)
    }

    @Test func theBotSinksAnEasyBall() throws {
        var rng = SeededGenerator(seed: 1)
        let ball = V(x: 400, y: 400)
        let state = eightBallState([3: ball, 12: V(x: 900, y: 1_800), 8: V(x: 1_000, y: 2_000)], cue: V(x: 700, y: 700), groups: [.two: .solids, .one: .stripes])
        var twoToAct = state
        twoToAct.outcome = .inProgress(toAct: .two)
        let action = try #require(EightBallBot(difficulty: .sharp).takeTurn(in: twoToAct, using: &rng))
        let first = try #require(twoToAct.progress(of: action.shots, by: .two).results.first)
        #expect(first.pocketed.contains(3))
    }
}

/// Small deterministic generator for tests (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
