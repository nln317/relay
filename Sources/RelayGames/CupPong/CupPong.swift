import RelayCore

/// Cup Pong: each player has a triangle of cups at their end of the table and takes turns
/// throwing two balls at the other player's cups. A ball that lands in a cup takes that cup
/// away. Sink both balls of a turn and you get them back for two more ("balls back").
/// When a side is down to 6, 3 or 1 cups at the end of a turn they are re-racked into a
/// tight triangle. The first to clear the other side wins; if the throw limit is reached,
/// whoever has more of their own cups standing wins.
///
/// An action is one whole turn: where each ball came down, in whole millimetres on the
/// target side's table. The rules decide with integer maths alone which cup, if any, each
/// ball fell into, so every device agrees. How a swipe becomes a landing point is input,
/// not rules: see `CupPongAim`.
public enum CupPong: GameRules {
    public static let gameID = GameID(constant: "cup-pong")
    public static let rulesVersion = RulesVersion(1)
    public static let ballsPerTurn = 2

    public struct Configuration: Codable, Equatable, Sendable {
        /// Cups per side: 10 (4-3-2-1) or 6 (3-2-1).
        public var cups: Int

        public static let standard = Configuration(cups: 10)

        public init(cups: Int) {
            self.cups = cups
        }

        private enum CodingKeys: String, CodingKey {
            case cups = "c"
        }
    }

    // MARK: Table

    /// Table size and cup layout, in millimetres. x runs across the table from its centre
    /// line (right positive, as the thrower sees it); y runs away from the thrower's edge.
    public enum Table {
        public static let length = 2_440
        public static let halfWidth = 305
        public static let cupRadius = 47
        public static let cupHeight = 120
        public static let ballRadius = 20
        /// Centre of the back row of cups, from the thrower's edge.
        public static let backRowY = 2_370
        /// Cups in a row stand touching.
        public static let cupSpacing = 96
        /// Distance between rows of touching cups (spacing × √3 / 2, rounded).
        public static let rowStep = 83
        /// A ball whose centre comes down this close to a cup's centre drops in.
        public static let sinkRadius = 36
        /// Further out than `sinkRadius` but this close and it clips the rim and bounces out.
        public static let rimRadius = cupRadius + ballRadius

        /// Cups in a tight triangle with the point towards the thrower, `count` being 10,
        /// 6, 3 or 1. Ids number them back row first, left to right.
        public static func rack(_ count: Int) -> [Cup] {
            var rows = 1
            while rows * (rows + 1) / 2 < count { rows += 1 }
            var cups: [Cup] = []
            for row in 0..<rows {
                let inRow = rows - row
                for column in 0..<inRow {
                    // Half a spacing between neighbouring rows, so the offsets stay integers.
                    let x = (2 * column - (inRow - 1)) * cupSpacing / 2
                    cups.append(Cup(id: cups.count, x: x, y: backRowY - row * rowStep))
                }
            }
            return Array(cups.prefix(count))
        }
    }

    public struct Cup: Equatable, Hashable, Sendable {
        public var id: Int
        public var x: Int
        public var y: Int

        public init(id: Int, x: Int, y: Int) {
            self.id = id
            self.x = x
            self.y = y
        }
    }

    /// Where a ball came down, in millimetres on the target side (see `Table`).
    public struct Landing: Equatable, Hashable, Sendable {
        public var x: Int
        public var y: Int

        public init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }
    }

    /// One turn: every ball thrown, `[x1, y1, x2, y2, ...]` on the wire.
    public struct Action: Codable, Equatable, Hashable, Sendable {
        public var landings: [Landing]

        public init(landings: [Landing]) {
            self.landings = landings
        }

        public init(from decoder: Decoder) throws {
            let numbers = try decoder.singleValueContainer().decode([Int].self)
            guard numbers.count.isMultiple(of: 2) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "odd coordinate count"))
            }
            landings = stride(from: 0, to: numbers.count, by: 2).map { Landing(x: numbers[$0], y: numbers[$0 + 1]) }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(landings.flatMap { [$0.x, $0.y] })
        }
    }

    public enum RuleViolation: Error, Equatable, Sendable {
        case gameOver
        case notYourTurn
        case emptyTurn
        case tooManyThrows(Int)
        /// The turn ended before its last ball.
        case throwsAfterTurnEnded
        /// The turn stopped although the thrower still had a ball.
        case turnCutShort
        case outOfReach
    }

    /// What became of one ball.
    public enum BallResult: Equatable, Hashable, Sendable {
        /// Dropped into this cup, which is taken away.
        case sunk(cup: Int)
        /// Clipped this cup's rim and bounced out.
        case rim(cup: Int)
        /// Bounced on the table and away.
        case table
        /// Missed the table altogether.
        case missed

        public var isSink: Bool {
            if case .sunk = self { return true }
            return false
        }
    }

    public struct ThrowResult: Equatable, Sendable {
        public var landing: Landing
        public var result: BallResult
        /// The target cups when this ball was thrown.
        public var cupsBefore: [Cup]
    }

    public struct Turn: Equatable, Sendable {
        public var seat: Seat
        public var balls: [ThrowResult]
        /// The target cups when the turn began.
        public var startCups: [Cup]
        /// The target cups after the turn, after any re-rack.
        public var endCups: [Cup]
        /// True when the target was re-racked at the end of this turn.
        public var reracked: Bool

        public var sunk: Int { balls.filter(\.result.isSink).count }
    }

    /// A turn in progress, for showing it live.
    public struct TurnProgress: Equatable, Sendable {
        public var balls: [ThrowResult]
        /// The target cups now (no re-rack until the turn is over).
        public var cups: [Cup]
        /// Balls left before the turn ends, counting a pair given back.
        public var ballsLeft: Int
        /// True once both balls of the last pair went in, so the thrower has them back.
        public var ballsBack: Bool
        public var isComplete: Bool
        public var cleared: Bool
    }

    public struct State: Equatable, Sendable {
        public let configuration: Configuration
        /// The cups standing at each seat's end: the other player throws at them.
        public private(set) var cups: [Seat: [Cup]]
        public private(set) var turns: [Turn]
        public private(set) var outcome: GameOutcome

        init(configuration: Configuration, firstSeat: Seat) {
            self.configuration = configuration
            cups = [.one: Table.rack(configuration.cups), .two: Table.rack(configuration.cups)]
            turns = []
            outcome = .inProgress(toAct: firstSeat)
        }

        /// The cups `seat` throws at.
        public func targets(for seat: Seat) -> [Cup] {
            cups[seat.opponent] ?? []
        }

        /// The cups standing at `seat`'s own end.
        public func cupsLeft(for seat: Seat) -> Int {
            cups[seat]?.count ?? 0
        }

        public var lastTurn: Turn? { turns.last }

        /// Throws `landings` for `seat` without changing the state.
        public func progress(of landings: [Landing], by seat: Seat) -> TurnProgress {
            var targets = self.targets(for: seat)
            var results: [ThrowResult] = []
            var inPair = 0
            var sunkInPair = 0
            var ballsBack = false
            var complete = false
            for landing in landings {
                let result = CupPong.result(of: landing, against: targets)
                results.append(ThrowResult(landing: landing, result: result, cupsBefore: targets))
                if case .sunk(let id) = result {
                    targets.removeAll { $0.id == id }
                    sunkInPair += 1
                }
                inPair += 1
                ballsBack = false
                if targets.isEmpty {
                    complete = true
                    break
                }
                if inPair == CupPong.ballsPerTurn {
                    if sunkInPair == CupPong.ballsPerTurn {
                        ballsBack = true
                        inPair = 0
                        sunkInPair = 0
                    } else {
                        complete = true
                        break
                    }
                }
            }
            return TurnProgress(
                balls: results,
                cups: targets,
                ballsLeft: complete ? 0 : CupPong.ballsPerTurn - inPair,
                ballsBack: ballsBack,
                isComplete: complete,
                cleared: targets.isEmpty
            )
        }

        mutating func record(_ progress: TurnProgress, by seat: Seat) {
            let target = seat.opponent
            let start = cups[target] ?? []
            var end = progress.cups
            var reracked = false
            if CupPong.rerackCounts.contains(end.count), end != Table.rack(end.count), end.count < start.count {
                end = Table.rack(end.count)
                reracked = true
            }
            cups[target] = end
            turns.append(Turn(seat: seat, balls: progress.balls, startCups: start, endCups: end, reracked: reracked))
            if progress.cleared {
                outcome = .won(by: seat)
            } else if turns.count >= CupPong.maximumTurns {
                let mine = cupsLeft(for: seat), theirs = cupsLeft(for: target)
                outcome = mine == theirs ? .draw : .won(by: mine > theirs ? seat : target)
            } else {
                outcome = .inProgress(toAct: target)
            }
        }
    }

    /// Cup counts that get re-racked into a tight triangle at the end of a turn.
    public static let rerackCounts: Set<Int> = [6, 3, 1]
    /// After this many turns (both players together) more cups still standing wins.
    public static let maximumTurns = 80
    /// Landings further out than this are rejected as impossible, not scored as misses.
    public static let maximumReach = 6_000

    /// The cup a ball lands in or clips, by squared distance to the nearest cup centre.
    public static func result(of landing: Landing, against cups: [Cup]) -> BallResult {
        var nearest: (cup: Cup, distance: Int)?
        for cup in cups {
            let dx = landing.x - cup.x, dy = landing.y - cup.y
            let distance = dx * dx + dy * dy
            if distance < (nearest?.distance ?? .max) { nearest = (cup, distance) }
        }
        if let nearest {
            if nearest.distance <= Table.sinkRadius * Table.sinkRadius { return .sunk(cup: nearest.cup.id) }
            if nearest.distance <= Table.rimRadius * Table.rimRadius { return .rim(cup: nearest.cup.id) }
        }
        if abs(landing.x) <= Table.halfWidth, (0...Table.length).contains(landing.y) { return .table }
        return .missed
    }

    public static func maximumActions(for configuration: Configuration) -> Int {
        maximumTurns
    }

    public static func isSupported(_ configuration: Configuration) -> Bool {
        configuration.cups == 10 || configuration.cups == 6
    }

    public static func initialState(for configuration: Configuration, firstSeat: Seat) -> State {
        State(configuration: configuration, firstSeat: firstSeat)
    }

    public static func apply(_ action: Action, by seat: Seat, to state: State) -> Result<State, RuleViolation> {
        guard let toAct = state.outcome.seatToAct else { return .failure(.gameOver) }
        guard toAct == seat else { return .failure(.notYourTurn) }
        guard !action.landings.isEmpty else { return .failure(.emptyTurn) }
        // Every pair given back removes two cups, so a turn can't run longer than this.
        let limit = state.configuration.cups + ballsPerTurn
        guard action.landings.count <= limit else { return .failure(.tooManyThrows(action.landings.count)) }
        guard action.landings.allSatisfy({ abs($0.x) <= maximumReach && abs($0.y) <= maximumReach }) else {
            return .failure(.outOfReach)
        }
        let progress = state.progress(of: action.landings, by: seat)
        guard progress.balls.count == action.landings.count else { return .failure(.throwsAfterTurnEnded) }
        guard progress.isComplete else { return .failure(.turnCutShort) }
        var next = state
        next.record(progress, by: seat)
        return .success(next)
    }

    public static func outcome(of state: State) -> GameOutcome {
        state.outcome
    }
}
