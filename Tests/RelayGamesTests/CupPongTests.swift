import Foundation
import RelayCore
@testable import RelayGames
import Testing

private struct Mixer: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private typealias L = CupPong.Landing

private func cup(_ state: CupPong.State, for seat: Seat, _ id: Int) -> CupPong.Cup {
    state.targets(for: seat).first { $0.id == id }!
}

private func on(_ cup: CupPong.Cup, dx: Int = 0, dy: Int = 0) -> L {
    L(x: cup.x + dx, y: cup.y + dy)
}

private let wide = L(x: 2_000, y: 1_000)

@Suite("Cup Pong rules")
struct CupPongRulesTests {
    let start = CupPong.initialState(for: .standard, firstSeat: .one)

    @Test func theRackIsATightTriangleWithThePointTowardsTheThrower() {
        let rack = CupPong.Table.rack(10)
        #expect(rack.count == 10)
        #expect(rack.filter { $0.y == CupPong.Table.backRowY }.count == 4)
        let front = rack.max { $0.y > $1.y }!
        #expect(front.x == 0)
        #expect(front.y == CupPong.Table.backRowY - 3 * CupPong.Table.rowStep)
        // Neighbours in a row touch.
        let back = rack.filter { $0.y == CupPong.Table.backRowY }.map(\.x).sorted()
        #expect(back == [-144, -48, 48, 144])
        #expect(CupPong.Table.rack(6).count == 6)
        #expect(CupPong.Table.rack(3).count == 3)
        #expect(CupPong.Table.rack(1) == [CupPong.Cup(id: 0, x: 0, y: CupPong.Table.backRowY)])
    }

    @Test func aBallNearACupCentreSinksItAndOnTheEdgeClipsTheRim() {
        let target = cup(start, for: .one, 9)
        #expect(CupPong.result(of: on(target, dx: 30), against: start.targets(for: .one)) == .sunk(cup: 9))
        #expect(CupPong.result(of: on(target, dx: 0, dy: -60), against: start.targets(for: .one)) == .rim(cup: 9))
        #expect(CupPong.result(of: L(x: 0, y: 1_200), against: start.targets(for: .one)) == .table)
        #expect(CupPong.result(of: L(x: 400, y: 1_200), against: start.targets(for: .one)) == .missed)
    }

    @Test func oneSinkOfTwoTakesACupAndPassesTheTurn() throws {
        let target = cup(start, for: .one, 9)
        let next = try CupPong.apply(CupPong.Action(landings: [on(target), wide]), by: .one, to: start).get()
        #expect(next.cupsLeft(for: .two) == 9)
        #expect(next.cupsLeft(for: .one) == 10)
        #expect(next.outcome == .inProgress(toAct: .two))
        #expect(next.lastTurn?.sunk == 1)
    }

    @Test func sinkingBothGivesTheBallsBack() throws {
        let a = cup(start, for: .one, 9), b = cup(start, for: .one, 8)
        let progress = start.progress(of: [on(a), on(b)], by: .one)
        #expect(progress.ballsBack)
        #expect(!progress.isComplete)
        #expect(progress.ballsLeft == 2)
        // Two short throws ends it.
        #expect(throws: Never.self) { try CupPong.apply(CupPong.Action(landings: [on(a), on(b), wide, wide]), by: .one, to: start).get() }
        #expect(CupPong.apply(CupPong.Action(landings: [on(a), on(b)]), by: .one, to: start) == .failure(.turnCutShort))
    }

    @Test func aTurnCannotCarryOnAfterItEnded() {
        #expect(CupPong.apply(CupPong.Action(landings: [wide, wide, wide]), by: .one, to: start) == .failure(.throwsAfterTurnEnded))
        #expect(CupPong.apply(CupPong.Action(landings: [wide]), by: .one, to: start) == .failure(.turnCutShort))
        #expect(CupPong.apply(CupPong.Action(landings: []), by: .one, to: start) == .failure(.emptyTurn))
        #expect(CupPong.apply(CupPong.Action(landings: [wide, wide]), by: .two, to: start) == .failure(.notYourTurn))
        #expect(CupPong.apply(CupPong.Action(landings: [L(x: 9_000, y: 0), wide]), by: .one, to: start) == .failure(.outOfReach))
    }

    @Test func theSameCupCannotBeSunkTwice() {
        let a = cup(start, for: .one, 9)
        let progress = start.progress(of: [on(a), on(a)], by: .one)
        #expect(progress.balls[0].result == .sunk(cup: 9))
        #expect(progress.balls[1].result != .sunk(cup: 9))
        #expect(progress.isComplete)
    }

    @Test func downToSixTheCupsAreReracked() throws {
        var state = start
        // Player one sinks the front four cups over two turns of balls back.
        let ids = [9, 8, 7, 6]
        var landings: [L] = []
        for id in ids { landings.append(on(cup(state, for: .one, id))) }
        landings += [wide, wide]
        state = try CupPong.apply(CupPong.Action(landings: landings), by: .one, to: state).get()
        #expect(state.cupsLeft(for: .two) == 6)
        #expect(state.lastTurn?.reracked == true)
        #expect(state.targets(for: .one) == CupPong.Table.rack(6))
    }

    @Test func clearingTheLastCupWinsAtOnce() throws {
        var state = start
        var turns = 0
        while state.outcome.seatToAct != nil, turns < 40 {
            let seat = state.outcome.seatToAct!
            var landings: [L] = []
            if seat == .one {
                // Player one never misses.
                while true {
                    let progress = state.progress(of: landings, by: seat)
                    if progress.isComplete { break }
                    landings.append(on(progress.cups[0]))
                }
            } else {
                landings = [wide, wide]
            }
            state = try CupPong.apply(CupPong.Action(landings: landings), by: seat, to: state).get()
            turns += 1
        }
        #expect(state.outcome == .won(by: .one))
        #expect(state.cupsLeft(for: .two) == 0)
        // Ten cups in one turn: five pairs.
        #expect(turns == 1)
        #expect(state.lastTurn?.balls.count == 10)
    }

    @Test func theTurnLimitGoesToMoreCupsStanding() throws {
        var state = start
        state = try CupPong.apply(CupPong.Action(landings: [on(cup(state, for: .one, 0)), wide]), by: .one, to: state).get()
        while let seat = state.outcome.seatToAct {
            state = try CupPong.apply(CupPong.Action(landings: [wide, wide]), by: seat, to: state).get()
        }
        #expect(state.turns.count == CupPong.maximumTurns)
        #expect(state.outcome == .won(by: .one))
    }

    @Test func actionsTravelAsFlatNumbers() throws {
        let action = CupPong.Action(landings: [L(x: -12, y: 2_200), L(x: 40, y: 2_390)])
        let data = try JSONEncoder().encode(action)
        #expect(String(decoding: data, as: UTF8.self) == "[-12,2200,40,2390]")
        #expect(try JSONDecoder().decode(CupPong.Action.self, from: data) == action)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(CupPong.Action.self, from: Data("[1,2,3]".utf8)) }
    }
}

@Suite("Cup Pong aim and bot")
struct CupPongAimTests {
    @Test func aStraightSwipeAtRackSpeedLandsInTheMiddleOfTheRack() throws {
        let landing = try #require(CupPongAim.flickLanding(start: (0.5, 0.9), release: (0.5, 0.6), velocity: (0, -CupPongAim.rackSpeed)))
        #expect(landing.x == 0)
        #expect(landing.y == CupPongAim.rackCentreY)
    }

    @Test func fasterGoesFurtherAndLeaningDrifts() throws {
        let soft = try #require(CupPongAim.flickLanding(start: (0.5, 0.9), release: (0.5, 0.6), velocity: (0, -2.0)))
        let hard = try #require(CupPongAim.flickLanding(start: (0.5, 0.9), release: (0.5, 0.6), velocity: (0, -3.4)))
        #expect(soft.y < CupPongAim.rackCentreY)
        #expect(hard.y > CupPongAim.rackCentreY)
        let right = try #require(CupPongAim.flickLanding(start: (0.5, 0.9), release: (0.56, 0.6), velocity: (0.4, -2.6)))
        #expect(right.x > 20)
        #expect(CupPongAim.flickLanding(start: (0.5, 0.9), release: (0.5, 0.95), velocity: (0, 1)) == nil)
        #expect(CupPongAim.flickLanding(start: (0.5, 0.9), release: (0.5, 0.88), velocity: (0, -0.1)) == nil)
    }

    @Test(arguments: CupPongBot.Difficulty.allCases)
    func botsPlayWholeGamesToAResult(difficulty: CupPongBot.Difficulty) throws {
        var rng = Mixer(state: 7)
        let bot = CupPongBot(difficulty: difficulty)
        var state = CupPong.initialState(for: .standard, firstSeat: .one)
        while let seat = state.outcome.seatToAct {
            let action = try #require(bot.takeTurn(in: state, using: &rng))
            state = try CupPong.apply(action, by: seat, to: state).get()
        }
        #expect(state.outcome.isFinished)
    }

    @Test func sharperBotsSinkMore() {
        func rate(_ difficulty: CupPongBot.Difficulty) -> Double {
            var rng = Mixer(state: 3)
            let bot = CupPongBot(difficulty: difficulty)
            let cups = CupPong.Table.rack(10)
            let sunk = (0..<2_000).filter { _ in CupPong.result(of: bot.nextLanding(at: cups, using: &rng), against: cups).isSink }.count
            return Double(sunk) / 2_000
        }
        let casual = rate(.casual), standard = rate(.standard), sharp = rate(.sharp)
        #expect(casual < standard)
        #expect(standard < sharp)
        #expect(casual > 0.1)
        #expect(sharp < 0.85)
    }
}
