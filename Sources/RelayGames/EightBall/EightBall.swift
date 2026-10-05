import RelayCore

/// 8-Ball pool, played the way the classic iMessage version plays it.
///
/// - The first player breaks with the cue ball anywhere behind the head string.
/// - The table is open until someone legally pots only solids (1–7) or only stripes
///   (9–15) after the break; that is their group, the other is their opponent's.
/// - You keep shooting while you legally pot one of your own balls (any ball while the
///   table is open). Otherwise the turn passes.
/// - A foul (the cue ball dropping, hitting nothing, or hitting a ball outside your group
///   first) gives the other player the cue ball in hand anywhere.
/// - Pot the 8 after clearing your group to win. Potting it early, or fouling on the shot
///   that pots it, loses. An 8 potted on the break goes back on the foot spot.
///
/// An action is one whole turn: every shot taken until it ended. A shot is integers only
/// (direction, power, spin, cue ball placement), and the rules replay each shot through
/// the deterministic simulation in `PoolTable`, so every device reaches the same table.
/// That is a stronger guarantee than trusting a list of final ball positions, and it
/// keeps messages small.
public enum EightBall: GameRules {
    public static let gameID = GameID(constant: "eight-ball")
    public static let rulesVersion = RulesVersion(1)

    public struct Configuration: Codable, Equatable, Sendable {
        /// Reserved for variants; only the standard game exists.
        public var variant: Int

        public static let standard = Configuration(variant: 0)

        public init(variant: Int) {
            self.variant = variant
        }

        private enum CodingKeys: String, CodingKey {
            case variant = "v"
        }
    }

    public enum Group: Int, Codable, Equatable, Sendable {
        case solids = 1
        case stripes = 2

        public var other: Group { self == .solids ? .stripes : .solids }

        public var balls: ClosedRange<Int> { self == .solids ? 1...7 : 9...15 }

        public static func of(_ ball: Int) -> Group? {
            switch ball {
            case 1...7: .solids
            case 9...15: .stripes
            default: nil
            }
        }
    }

    /// Where the player may put the cue ball before shooting.
    public enum BallInHand: Equatable, Sendable {
        case none
        /// Behind the head string: the break.
        case behindHeadString
        /// Anywhere on the cloth: after the other player fouled.
        case anywhere
    }

    // MARK: Shots

    /// Scale of a shot's direction vector: each component is in -directionScale...directionScale.
    public static let directionScale = 4_096
    public static let maximumPower = 1_000
    /// Spin is a point on the cue ball's face within a circle of this radius.
    public static let maximumSpin = 10

    /// One stroke of the cue. Integers, so every device simulates exactly the same shot.
    public struct Shot: Equatable, Hashable, Sendable {
        /// Direction the cue ball is struck in (need not be normalised), y down the table.
        public var dx: Int
        public var dy: Int
        /// 1...maximumPower.
        public var power: Int
        /// Where the cue tip meets the ball: positive x is right (side spin), positive y is
        /// high (follow), negative y low (draw).
        public var spinX: Int
        public var spinY: Int
        /// Where the cue ball was placed first, in whole millimetres, when in hand.
        public var placement: Placement?

        public struct Placement: Equatable, Hashable, Sendable {
            public var x: Int
            public var y: Int

            public init(x: Int, y: Int) {
                self.x = x
                self.y = y
            }

            var vector: PoolTable.Vector { PoolTable.Vector(x: Double(x), y: Double(y)) }
        }

        public init(dx: Int, dy: Int, power: Int, spinX: Int = 0, spinY: Int = 0, placement: Placement? = nil) {
            self.dx = dx
            self.dy = dy
            self.power = power
            self.spinX = spinX
            self.spinY = spinY
            self.placement = placement
        }

        /// The cue ball's starting velocity.
        var velocity: PoolTable.Vector {
            let direction = PoolTable.Vector(x: Double(dx), y: Double(dy))
            let unit = direction * (1 / direction.length)
            let fraction = Double(power) / Double(EightBall.maximumPower)
            return unit * (PoolTable.minimumCueSpeed + (PoolTable.maximumCueSpeed - PoolTable.minimumCueSpeed) * fraction)
        }
    }

    /// One turn: the shots taken until it ended. Encoded as a flat integer array, six or
    /// eight numbers per shot: `[dx, dy, power, spinX, spinY, placed, (x, y)]` where
    /// `placed` is 1 when a placement follows.
    public struct Action: Codable, Equatable, Hashable, Sendable {
        public var shots: [Shot]

        public init(shots: [Shot]) {
            self.shots = shots
        }

        public init(from decoder: Decoder) throws {
            let numbers = try decoder.singleValueContainer().decode([Int].self)
            var shots: [Shot] = []
            var index = 0
            func corrupt(_ reason: String) -> DecodingError {
                DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: reason))
            }
            while index < numbers.count {
                guard index + 6 <= numbers.count else { throw corrupt("truncated shot") }
                let n = Array(numbers[index..<(index + 6)])
                index += 6
                var placement: Shot.Placement?
                switch n[5] {
                case 0: break
                case 1:
                    guard index + 2 <= numbers.count else { throw corrupt("truncated placement") }
                    placement = Shot.Placement(x: numbers[index], y: numbers[index + 1])
                    index += 2
                default: throw corrupt("bad placement flag")
                }
                shots.append(Shot(dx: n[0], dy: n[1], power: n[2], spinX: n[3], spinY: n[4], placement: placement))
            }
            self.shots = shots
        }

        public func encode(to encoder: Encoder) throws {
            var numbers: [Int] = []
            for shot in shots {
                numbers += [shot.dx, shot.dy, shot.power, shot.spinX, shot.spinY, shot.placement == nil ? 0 : 1]
                if let placement = shot.placement { numbers += [placement.x, placement.y] }
            }
            var container = encoder.singleValueContainer()
            try container.encode(numbers)
        }
    }

    public enum RuleViolation: Error, Equatable, Sendable {
        case gameOver
        case notYourTurn
        case emptyTurn
        case tooManyShots
        case badDirection
        case badPower
        case badSpin
        /// The cue ball was in hand but the shot did not place it, or placed it when it
        /// was not in hand.
        case placementMismatch
        case badPlacement
        /// The turn had ended (miss, foul or game over) before its last shot.
        case shotsAfterTurnEnded
        /// Fewer shots than the turn allowed: it had not ended.
        case turnCutShort
    }

    // MARK: State

    public enum Foul: Equatable, Sendable {
        case scratch
        case noContact
        case wrongBallFirst
    }

    /// What one shot did, judged by the rules.
    public struct ShotResult: Equatable, Sendable {
        public enum Ending: Equatable, Sendable {
            /// The shooter goes again.
            case continues
            /// The turn passes.
            case turnOver
            case won
            case lost
        }

        public var shot: Shot
        /// The table as the shot was struck (cue ball already placed), for replaying it.
        public var startPositions: [PoolTable.Vector?]
        public var pocketed: [Int]
        public var firstContact: Int?
        public var foul: Foul?
        /// The group this shot gave the shooter, when it settled an open table.
        public var assignedGroup: Group?
        public var ending: Ending
    }

    /// One recorded turn.
    public struct Turn: Equatable, Sendable {
        public var seat: Seat
        public var shots: [ShotResult]
        /// The table before the turn's first shot, so a turn can be replayed for viewing.
        public var startPositions: [PoolTable.Vector?]
        public var startBallInHand: BallInHand
    }

    /// A turn in progress, for showing it live and for validating a whole turn.
    public struct TurnProgress: Equatable, Sendable {
        public var results: [ShotResult]
        public var positions: [PoolTable.Vector?]
        public var groups: [Seat: Group]
        public var ballInHand: BallInHand
        /// True once no more shots may be taken this turn.
        public var isComplete: Bool
        public var outcome: GameOutcome
    }

    public struct State: Equatable, Sendable {
        public let configuration: Configuration
        /// Ball centres; nil once pocketed (or the cue ball while it is in hand). Index 0
        /// is the cue ball, 1...15 the object balls.
        public internal(set) var positions: [PoolTable.Vector?]
        public internal(set) var groups: [Seat: Group]
        public internal(set) var ballInHand: BallInHand
        public internal(set) var turns: [Turn]
        public internal(set) var outcome: GameOutcome

        init(configuration: Configuration, firstSeat: Seat) {
            self.configuration = configuration
            positions = PoolTable.rack()
            groups = [:]
            ballInHand = .behindHeadString
            turns = []
            outcome = .inProgress(toAct: firstSeat)
        }

        public var isBreak: Bool { turns.isEmpty }
        public var isTableOpen: Bool { groups.isEmpty }
        public var lastTurn: Turn? { turns.last }

        public func group(for seat: Seat) -> Group? { groups[seat] }

        /// Balls of `seat`'s group still on the table.
        public func remaining(for seat: Seat) -> [Int] {
            guard let group = groups[seat] else { return [] }
            return group.balls.filter { positions[$0] != nil }
        }

        /// Plays `shots` for `seat` from the current table without changing the state.
        /// Stops at the shot that ends the turn; later shots are not simulated.
        public func progress(of shots: [Shot], by seat: Seat) -> TurnProgress {
            var positions = self.positions
            var groups = self.groups
            var ballInHand = self.ballInHand
            var results: [ShotResult] = []
            var outcome = self.outcome
            var isBreakShot = isBreak
            for shot in shots {
                let result = EightBall.judge(shot, by: seat, positions: &positions, groups: &groups, ballInHand: &ballInHand, isBreak: isBreakShot)
                isBreakShot = false
                results.append(result)
                switch result.ending {
                case .continues: continue
                case .turnOver: outcome = .inProgress(toAct: seat.opponent)
                case .won: outcome = .won(by: seat)
                case .lost: outcome = .won(by: seat.opponent)
                }
                break
            }
            let complete = results.last.map { $0.ending != .continues } ?? false
            return TurnProgress(results: results, positions: positions, groups: groups, ballInHand: ballInHand, isComplete: complete, outcome: outcome)
        }
    }

    // MARK: Judging a shot

    /// Simulates `shot` and applies the rules to it, updating the table in place.
    /// Assumes the shot was validated.
    static func judge(_ shot: Shot, by seat: Seat, positions: inout [PoolTable.Vector?], groups: inout [Seat: Group], ballInHand: inout BallInHand, isBreak: Bool) -> ShotResult {
        if let placement = shot.placement { positions[0] = placement.vector }
        let simulated = PoolTable.simulate(
            positions: positions,
            velocity: shot.velocity,
            follow: Double(shot.spinY) / Double(maximumSpin),
            side: Double(shot.spinX) / Double(maximumSpin),
            recordFrames: false
        )
        return rule(shot, outcome: simulated, by: seat, positions: &positions, groups: &groups, ballInHand: &ballInHand, isBreak: isBreak)
    }

    /// The rules part of `judge`, given what the physics did.
    static func rule(_ shot: Shot, outcome simulated: PoolTable.ShotOutcome, by seat: Seat, positions: inout [PoolTable.Vector?], groups: inout [Seat: Group], ballInHand: inout BallInHand, isBreak: Bool) -> ShotResult {
        let before = positions
        positions = simulated.positions
        let pocketed = simulated.pocketed
        let scratched = pocketed.contains(0)
        let objectBalls = pocketed.filter { $0 != 0 && $0 != 8 }
        let mine = groups[seat]
        let clearedBefore = mine.map { group in group.balls.allSatisfy { before[$0] == nil } } ?? false

        // Was the first ball hit a legal one?
        var foul: Foul?
        if scratched {
            foul = .scratch
        } else if simulated.firstContact == nil {
            foul = .noContact
        } else if !isBreak, let first = simulated.firstContact {
            if let mine {
                let legal = clearedBefore ? first == 8 : Group.of(first) == mine
                if !legal { foul = .wrongBallFirst }
            } else if first == 8 {
                foul = .wrongBallFirst
            }
        }

        // The 8.
        if pocketed.contains(8) {
            if isBreak {
                positions[8] = freeSpot(near: PoolTable.footSpot, in: positions)
            } else {
                let won = clearedBefore && foul == nil
                if scratched { positions[0] = nil }
                return ShotResult(shot: shot, startPositions: before, pocketed: pocketed, firstContact: simulated.firstContact, foul: foul, assignedGroup: nil, ending: won ? .won : .lost)
            }
        }

        // Settling an open table: only after the break, only on a clean shot that potted
        // balls of one group.
        var assigned: Group?
        if groups.isEmpty, !isBreak, foul == nil, !objectBalls.isEmpty {
            let kinds = Set(objectBalls.compactMap(Group.of))
            if kinds.count == 1, let group = kinds.first {
                groups[seat] = group
                groups[seat.opponent] = group.other
                assigned = group
            }
        }

        let ending: ShotResult.Ending
        if foul != nil {
            if scratched { positions[0] = nil }
            ballInHand = .anywhere
            ending = .turnOver
        } else {
            ballInHand = .none
            let pottedOwn: Bool
            if let group = groups[seat] {
                pottedOwn = objectBalls.contains { Group.of($0) == group }
            } else {
                pottedOwn = !objectBalls.isEmpty || (isBreak && pocketed.contains(8))
            }
            ending = pottedOwn ? .continues : .turnOver
        }
        return ShotResult(shot: shot, startPositions: before, pocketed: pocketed, firstContact: simulated.firstContact, foul: foul, assignedGroup: assigned, ending: ending)
    }

    /// Plays `shot` from `positions` with every frame recorded, for showing it. The same
    /// simulation the rules use, so the picture always matches the result.
    public static func animation(of shot: Shot, from positions: [PoolTable.Vector?]) -> PoolTable.ShotOutcome {
        var start = positions
        if let placement = shot.placement { start[0] = placement.vector }
        return PoolTable.simulate(
            positions: start,
            velocity: shot.velocity,
            follow: Double(shot.spinY) / Double(maximumSpin),
            side: Double(shot.spinX) / Double(maximumSpin),
            recordFrames: true
        )
    }

    /// The point nearest `spot` (moving up the table, then down) where a ball fits.
    static func freeSpot(near spot: PoolTable.Vector, in positions: [PoolTable.Vector?]) -> PoolTable.Vector {
        let clearance = PoolTable.ballRadius * 2 + 0.5
        func isFree(_ point: PoolTable.Vector) -> Bool {
            positions.allSatisfy { other in
                guard let other else { return true }
                return (other - point).lengthSquared >= clearance * clearance
            }
        }
        for offset in 0..<200 {
            for sign in [-1.0, 1.0] {
                let point = PoolTable.Vector(x: spot.x, y: spot.y + sign * Double(offset) * 6)
                if PoolTable.isOnCloth(point), isFree(point) { return point }
            }
        }
        return spot
    }

    /// Whether the cue ball may be placed at `placement` in this situation.
    public static func isLegalPlacement(_ placement: Shot.Placement, ballInHand: BallInHand, positions: [PoolTable.Vector?]) -> Bool {
        let point = placement.vector
        guard PoolTable.isOnCloth(point) else { return false }
        if ballInHand == .behindHeadString, point.y < PoolTable.headString { return false }
        let clearance = PoolTable.ballRadius * 2
        for (index, other) in positions.enumerated() where index != 0 {
            if let other, (other - point).lengthSquared < clearance * clearance { return false }
        }
        return true
    }

    /// Checks a shot's numbers and placement before it is simulated.
    public static func validate(_ shot: Shot, ballInHand: BallInHand, positions: [PoolTable.Vector?]) -> RuleViolation? {
        guard abs(shot.dx) <= directionScale, abs(shot.dy) <= directionScale, shot.dx != 0 || shot.dy != 0 else { return .badDirection }
        guard (1...maximumPower).contains(shot.power) else { return .badPower }
        guard shot.spinX * shot.spinX + shot.spinY * shot.spinY <= maximumSpin * maximumSpin else { return .badSpin }
        switch (ballInHand, shot.placement) {
        case (.none, nil): return positions[0] == nil ? .placementMismatch : nil
        case (.none, .some): return .placementMismatch
        case (_, nil): return .placementMismatch
        case (_, .some(let placement)):
            return isLegalPlacement(placement, ballInHand: ballInHand, positions: positions) ? nil : .badPlacement
        }
    }

    // MARK: GameRules

    /// A turn ends at the latest when every ball has gone, so this is generous.
    public static let maximumShotsPerTurn = 16

    public static func maximumActions(for configuration: Configuration) -> Int { 400 }

    public static func isSupported(_ configuration: Configuration) -> Bool {
        configuration.variant == 0
    }

    public static func initialState(for configuration: Configuration, firstSeat: Seat) -> State {
        State(configuration: configuration, firstSeat: firstSeat)
    }

    public static func apply(_ action: Action, by seat: Seat, to state: State) -> Result<State, RuleViolation> {
        guard let toAct = state.outcome.seatToAct else { return .failure(.gameOver) }
        guard toAct == seat else { return .failure(.notYourTurn) }
        guard !action.shots.isEmpty else { return .failure(.emptyTurn) }
        guard action.shots.count <= maximumShotsPerTurn else { return .failure(.tooManyShots) }

        var positions = state.positions
        var groups = state.groups
        var ballInHand = state.ballInHand
        var results: [ShotResult] = []
        var isBreakShot = state.isBreak
        var outcome = state.outcome
        for (index, shot) in action.shots.enumerated() {
            if let violation = validate(shot, ballInHand: ballInHand, positions: positions) {
                return .failure(violation)
            }
            let result = judge(shot, by: seat, positions: &positions, groups: &groups, ballInHand: &ballInHand, isBreak: isBreakShot)
            isBreakShot = false
            results.append(result)
            let isLast = index == action.shots.count - 1
            switch result.ending {
            case .continues:
                if isLast { return .failure(.turnCutShort) }
            case .turnOver, .won, .lost:
                guard isLast else { return .failure(.shotsAfterTurnEnded) }
                switch result.ending {
                case .won: outcome = .won(by: seat)
                case .lost: outcome = .won(by: seat.opponent)
                default: outcome = .inProgress(toAct: seat.opponent)
                }
            }
        }
        var next = state
        next.turns.append(Turn(seat: seat, shots: results, startPositions: state.positions, startBallInHand: state.ballInHand))
        next.positions = positions
        next.groups = groups
        next.ballInHand = ballInHand
        next.outcome = outcome
        return .success(next)
    }

    public static func outcome(of state: State) -> GameOutcome {
        state.outcome
    }
}
