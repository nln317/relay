import RelayCore

/// Practice opponent for the containing app. Pure and deterministic for a given
/// random source, so it is unit tested like the rules.
public struct FourInARowBot: Sendable {
    public enum Difficulty: String, CaseIterable, Codable, Sendable {
        /// Takes a win when it sees one, otherwise mostly random.
        case casual
        /// Wins, blocks, avoids handing over a win, prefers the centre.
        case standard
        /// Shallow alpha-beta search.
        case sharp
    }

    public let difficulty: Difficulty

    public init(difficulty: Difficulty) {
        self.difficulty = difficulty
    }

    /// Chooses a legal column for the seat to act. Returns nil when the game is over.
    public func chooseColumn<R: RandomNumberGenerator>(in state: FourInARow.State, using rng: inout R) -> Int? {
        guard let me = state.outcome.seatToAct else { return nil }
        let open = state.openColumns
        guard !open.isEmpty else { return nil }

        if let win = open.first(where: { wins(column: $0, for: me, in: state) }) { return win }
        if difficulty == .casual { return open.randomElement(using: &rng) }

        if let block = open.first(where: { wins(column: $0, for: me.opponent, in: state) }) { return block }

        switch difficulty {
        case .casual:
            return open.randomElement(using: &rng)
        case .standard:
            let safe = open.filter { !handsOverWin(column: $0, for: me, in: state) }
            let candidates = safe.isEmpty ? open : safe
            return preferCentre(candidates, columns: state.configuration.columns, using: &rng)
        case .sharp:
            let depth = 5
            var best: [Int] = []
            var bestScore = Int.min
            for column in orderedByCentre(open, columns: state.configuration.columns) {
                guard case .success(let next) = FourInARow.apply(.init(column: column), by: me, to: state) else { continue }
                let score = -negamax(next, depth: depth - 1, alpha: -Int.max, beta: Int.max, me: me.opponent)
                if score > bestScore {
                    bestScore = score
                    best = [column]
                } else if score == bestScore {
                    best.append(column)
                }
            }
            return preferCentre(best.isEmpty ? open : best, columns: state.configuration.columns, using: &rng)
        }
    }

    func wins(column: Int, for seat: Seat, in state: FourInARow.State) -> Bool {
        var probe = state
        // Evaluate as if `seat` were to act, regardless of whose turn it is.
        guard probe.isColumnOpen(column) else { return false }
        let cell = probe.place(seat, inColumn: column)
        return !FourInARow.winningCells(through: cell, for: seat, in: probe).isEmpty
    }

    func handsOverWin(column: Int, for seat: Seat, in state: FourInARow.State) -> Bool {
        guard case .success(let next) = FourInARow.apply(.init(column: column), by: seat, to: state) else { return true }
        guard !next.outcome.isFinished else { return false }
        return next.openColumns.contains { wins(column: $0, for: seat.opponent, in: next) }
    }

    func preferCentre<R: RandomNumberGenerator>(_ columns: [Int], columns width: Int, using rng: inout R) -> Int? {
        let centre = Double(width - 1) / 2
        let bestDistance = columns.map { abs(Double($0) - centre) }.min()
        let closest = columns.filter { abs(Double($0) - centre) == bestDistance }
        return closest.randomElement(using: &rng)
    }

    func orderedByCentre(_ columns: [Int], columns width: Int) -> [Int] {
        let centre = Double(width - 1) / 2
        return columns.sorted { abs(Double($0) - centre) < abs(Double($1) - centre) }
    }

    /// Score from the point of view of `me`, the seat to act in `state`.
    func negamax(_ state: FourInARow.State, depth: Int, alpha: Int, beta: Int, me: Seat) -> Int {
        switch state.outcome {
        case .won(let winner):
            // The previous mover won; prefer faster wins and slower losses.
            let magnitude = 1_000_000 + depth
            return winner == me ? magnitude : -magnitude
        case .draw:
            return 0
        case .inProgress:
            break
        }
        if depth == 0 { return heuristic(state, for: me) }
        var alpha = alpha
        var best = -Int.max
        for column in orderedByCentre(state.openColumns, columns: state.configuration.columns) {
            guard case .success(let next) = FourInARow.apply(.init(column: column), by: me, to: state) else { continue }
            let score = -negamax(next, depth: depth - 1, alpha: -beta, beta: -alpha, me: me.opponent)
            best = max(best, score)
            alpha = max(alpha, score)
            if alpha >= beta { break }
        }
        return best
    }

    /// Counts open windows weighted by how full they are.
    func heuristic(_ state: FourInARow.State, for seat: Seat) -> Int {
        let config = state.configuration
        var score = 0
        for column in 0..<config.columns {
            for row in 0..<config.rows {
                for direction in FourInARow.directions {
                    var mine = 0
                    var theirs = 0
                    var valid = true
                    for step in 0..<config.connect {
                        let cell = FourInARow.Cell(column: column + step * direction.dc, row: row + step * direction.dr)
                        guard state.contains(cell) else { valid = false; break }
                        switch state.disc(at: cell) {
                        case seat: mine += 1
                        case seat.opponent: theirs += 1
                        default: break
                        }
                    }
                    guard valid else { continue }
                    if theirs == 0 { score += mine * mine }
                    if mine == 0 { score -= theirs * theirs }
                }
            }
        }
        return score
    }
}

/// Small seedable generator (SplitMix64) for deterministic tests and replays.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
