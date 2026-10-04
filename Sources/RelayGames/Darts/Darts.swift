import RelayCore

/// Darts, counting down: each player starts on `startingScore` and throws visits of up
/// to three darts; the first to reach exactly zero wins. Going below zero is a bust and
/// the visit scores nothing. Any dart can finish (no "double out"), which keeps the rules
/// explainable in one line. If nobody finishes within `rounds`, the lower score wins.
///
/// An action is one whole visit: the landing points of its darts. The rules score those
/// points with integer maths only, so every device computes the same result. How a
/// landing point is produced (aim, sway, scatter) is input, not rules: see `DartsAim`.
public enum Darts: GameRules {
    public static let gameID = GameID(constant: "darts")
    public static let rulesVersion = RulesVersion(1)
    public static let dartsPerVisit = 3

    public struct Configuration: Codable, Equatable, Sendable {
        public var startingScore: Int
        /// Rounds before the game is decided on the lower score. A round is one visit each.
        public var rounds: Int

        public static let standard = Configuration(startingScore: 201, rounds: 10)
        public static let presets: [Configuration] = [
            Configuration(startingScore: 101, rounds: 6),
            standard,
            Configuration(startingScore: 301, rounds: 12),
        ]

        public init(startingScore: Int, rounds: Int) {
            self.startingScore = startingScore
            self.rounds = rounds
        }

        private enum CodingKeys: String, CodingKey {
            case startingScore = "s"
            case rounds = "r"
        }
    }

    /// Where a dart landed, in tenths of a millimetre from the bullseye, x to the right
    /// and y up. Integers so scoring is identical on every device.
    public struct Hit: Equatable, Hashable, Sendable {
        public var x: Int
        public var y: Int

        public init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }
    }

    /// One visit: up to three darts. Encoded as a flat integer array `[x1, y1, x2, y2, ...]`.
    public struct Action: Codable, Equatable, Hashable, Sendable {
        public var hits: [Hit]

        public init(hits: [Hit]) {
            self.hits = hits
        }

        public init(from decoder: Decoder) throws {
            let numbers = try decoder.singleValueContainer().decode([Int].self)
            guard numbers.count.isMultiple(of: 2) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "odd coordinate count"))
            }
            hits = stride(from: 0, to: numbers.count, by: 2).map { Hit(x: numbers[$0], y: numbers[$0 + 1]) }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(hits.flatMap { [$0.x, $0.y] })
        }
    }

    public enum RuleViolation: Error, Equatable, Sendable {
        case gameOver
        case notYourTurn
        case emptyVisit
        case tooManyDarts(Int)
        /// The visit ended (bust or finish) before its last dart.
        case dartsAfterVisitEnded
        /// Fewer than three darts although the visit had not ended.
        case visitCutShort
        case outOfReach
    }

    /// One scored dart within a visit.
    public struct ScoredDart: Equatable, Sendable {
        public var hit: Hit
        public var segment: DartsBoard.Segment
    }

    public struct Visit: Equatable, Sendable {
        public enum Result: Equatable, Sendable {
            case scored
            case bust
            case finished
        }

        public var seat: Seat
        public var darts: [ScoredDart]
        public var result: Result
        /// Points taken off the score: 0 for a bust.
        public var points: Int
        public var remainingBefore: Int
        public var remainingAfter: Int
    }

    /// How a visit in progress stands after some darts, for showing it live.
    public struct VisitProgress: Equatable, Sendable {
        public var darts: [ScoredDart]
        public var result: Visit.Result
        public var points: Int
        public var remainingAfter: Int
        /// True once no more darts may be thrown in this visit.
        public var isComplete: Bool
    }

    public struct State: Equatable, Sendable {
        public let configuration: Configuration
        public private(set) var remaining: [Seat: Int]
        public private(set) var visits: [Visit]
        public private(set) var outcome: GameOutcome
        let firstSeat: Seat

        init(configuration: Configuration, firstSeat: Seat) {
            self.configuration = configuration
            self.firstSeat = firstSeat
            remaining = [.one: configuration.startingScore, .two: configuration.startingScore]
            visits = []
            outcome = .inProgress(toAct: firstSeat)
        }

        public func remaining(for seat: Seat) -> Int {
            remaining[seat] ?? configuration.startingScore
        }

        public var lastVisit: Visit? { visits.last }

        /// 1-based round being played (or last played when finished).
        public var round: Int {
            min(visits.count / 2 + 1, configuration.rounds)
        }

        public func visits(for seat: Seat) -> [Visit] {
            visits.filter { $0.seat == seat }
        }

        /// Scores `hits` from `seat`'s current score without changing the state.
        public func progress(of hits: [Hit], by seat: Seat) -> VisitProgress {
            let before = remaining(for: seat)
            var running = before
            var darts: [ScoredDart] = []
            var result = Visit.Result.scored
            for hit in hits {
                let segment = DartsBoard.segment(at: hit)
                darts.append(ScoredDart(hit: hit, segment: segment))
                let after = running - segment.points
                if after < 0 {
                    result = .bust
                    break
                }
                running = after
                if running == 0 {
                    result = .finished
                    break
                }
            }
            let ended = result != .scored || darts.count == Darts.dartsPerVisit
            return VisitProgress(
                darts: darts,
                result: result,
                points: result == .bust ? 0 : before - running,
                remainingAfter: result == .bust ? before : running,
                isComplete: ended
            )
        }

        mutating func record(_ progress: VisitProgress, by seat: Seat) {
            let before = remaining(for: seat)
            remaining[seat] = progress.remainingAfter
            visits.append(Visit(
                seat: seat,
                darts: progress.darts,
                result: progress.result,
                points: progress.points,
                remainingBefore: before,
                remainingAfter: progress.remainingAfter
            ))
            if progress.result == .finished {
                outcome = .won(by: seat)
            } else if visits.count >= configuration.rounds * 2 {
                let mine = remaining(for: seat), theirs = remaining(for: seat.opponent)
                outcome = mine == theirs ? .draw : .won(by: mine < theirs ? seat : seat.opponent)
            } else {
                outcome = .inProgress(toAct: seat.opponent)
            }
        }
    }

    /// Darts that land further out than this are rejected as impossible, not scored as misses.
    public static let maximumReach = 4_000

    public static func maximumActions(for configuration: Configuration) -> Int {
        configuration.rounds * 2
    }

    public static func isSupported(_ configuration: Configuration) -> Bool {
        (21...1001).contains(configuration.startingScore) && (1...30).contains(configuration.rounds)
    }

    public static func initialState(for configuration: Configuration, firstSeat: Seat) -> State {
        State(configuration: configuration, firstSeat: firstSeat)
    }

    public static func apply(_ action: Action, by seat: Seat, to state: State) -> Result<State, RuleViolation> {
        guard let toAct = state.outcome.seatToAct else { return .failure(.gameOver) }
        guard toAct == seat else { return .failure(.notYourTurn) }
        guard !action.hits.isEmpty else { return .failure(.emptyVisit) }
        guard action.hits.count <= dartsPerVisit else { return .failure(.tooManyDarts(action.hits.count)) }
        guard action.hits.allSatisfy({ abs($0.x) <= maximumReach && abs($0.y) <= maximumReach }) else {
            return .failure(.outOfReach)
        }
        let progress = state.progress(of: action.hits, by: seat)
        guard progress.darts.count == action.hits.count else { return .failure(.dartsAfterVisitEnded) }
        guard progress.isComplete else { return .failure(.visitCutShort) }
        var next = state
        next.record(progress, by: seat)
        return .success(next)
    }

    public static func outcome(of state: State) -> GameOutcome {
        state.outcome
    }
}
