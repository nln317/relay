import RelayCore

/// Turns an aim into a landing point. This is input, not rules: the sending device
/// decides where its darts land and the rules only score them (docs/ARCHITECTURE.md,
/// "Skill games"). Kept here, pure and seedable, so the practice bot and tests share it.
public enum DartsAim {
    /// Where a flicked dart heads, before scatter. Nil when the gesture was not a throw
    /// (too slow, sideways or downwards), so the dart just goes back to hand.
    ///
    /// Everything is measured in board widths with y growing downwards: the board spans
    /// 0...1 on both axes and the dart is held below it. That keeps the feel identical
    /// on every screen size. Speed sets how high the dart flies (a soft flick drops into
    /// the bottom of the board, a hard one reaches the top); the line of the flick sets
    /// where it goes left to right.
    /// - Parameters:
    ///   - start: where the swipe began.
    ///   - release: where the finger let go.
    ///   - velocity: release velocity in board widths per second.
    public static func flickTarget(start: (x: Double, y: Double), release: (x: Double, y: Double), velocity: (x: Double, y: Double)) -> (x: Double, y: Double)? {
        let upwardSpeed = -velocity.y
        guard upwardSpeed >= minimumThrowSpeed, start.y > release.y else { return nil }
        let height = lowestReach - upwardSpeed * reachPerSpeed
        // Follow the line of the flick up to that height. A near-flat flick would run off
        // to infinity, so the slope is capped (the rules clamp anything off the board).
        let slope = min(max(velocity.x / upwardSpeed, -1.5), 1.5)
        return (release.x + slope * max(0, release.y - height), height)
    }

    /// Slower than this (board widths per second) and the dart is not thrown. The softest
    /// throws fall short of the board, so a feeble flick misses low.
    public static let minimumThrowSpeed = 0.4
    /// Height reached by the softest throw: a little below the board, so it misses.
    public static let lowestReach = 1.05
    /// How much higher each extra board width per second of flick carries the dart.
    /// About 2.9 widths a second (a firm flick) reaches the bull and about 4.2 the
    /// treble 20. Tuned on device with Nathan: 0.2 felt light, 0.175 too heavy.
    public static let reachPerSpeed = 0.1875

    /// Scatter grows when the flick is wild (much harder than the top of the board
    /// needs), in tenths of a millimetre.
    public static func scatter(forSpeed speed: Double) -> Double {
        releaseScatter + 30 * max(0, speed - 6.3)
    }

    /// Release scatter added to every throw, standard deviation in tenths of a millimetre.
    public static let releaseScatter = 45.0

    /// Where a dart aimed at `aim` lands, with normally distributed scatter.
    public static func landing<R: RandomNumberGenerator>(aim: Darts.Hit, scatter: Double, using rng: inout R) -> Darts.Hit {
        let dx = normal(using: &rng) * scatter
        let dy = normal(using: &rng) * scatter
        return clamp(Darts.Hit(x: aim.x + Int(dx.rounded()), y: aim.y + Int(dy.rounded())))
    }

    /// Keeps a landing point inside what the rules accept.
    public static func clamp(_ hit: Darts.Hit) -> Darts.Hit {
        let reach = Darts.maximumReach
        return Darts.Hit(x: min(max(hit.x, -reach), reach), y: min(max(hit.y, -reach), reach))
    }

    /// Standard normal sample from twelve uniforms (Irwin–Hall). Plenty for throw scatter
    /// and avoids needing logarithms.
    static func normal<R: RandomNumberGenerator>(using rng: inout R) -> Double {
        var sum = 0.0
        for _ in 0..<12 { sum += Double.random(in: 0..<1, using: &rng) }
        return sum - 6
    }
}

/// Practice opponent for Darts. Chooses a sensible target and throws at it with
/// scatter that depends on difficulty.
public struct DartsBot: Sendable {
    public enum Difficulty: String, CaseIterable, Codable, Sendable {
        case casual
        case standard
        case sharp
    }

    public let difficulty: Difficulty

    public init(difficulty: Difficulty) {
        self.difficulty = difficulty
    }

    /// Scatter in tenths of a millimetre: casual is all over the board, sharp groups tightly.
    public var scatter: Double {
        switch difficulty {
        case .casual: 260
        case .standard: 150
        case .sharp: 75
        }
    }

    /// Throws a whole visit for the seat to act. Nil when the game is over.
    public func throwVisit<R: RandomNumberGenerator>(in state: Darts.State, using rng: inout R) -> Darts.Action? {
        guard let seat = state.outcome.seatToAct else { return nil }
        var hits: [Darts.Hit] = []
        while true {
            let progress = state.progress(of: hits, by: seat)
            if progress.isComplete { break }
            let aim = DartsBoard.target(for: target(remaining: progress.remainingAfter))
            hits.append(DartsAim.landing(aim: aim, scatter: scatter, using: &rng))
        }
        return Darts.Action(hits: hits)
    }

    /// The segment to aim at with `remaining` points left.
    public func target(remaining: Int) -> DartsBoard.Segment {
        if remaining == 50, difficulty != .casual { return DartsBoard.Segment(ring: .bull, number: 25) }
        if remaining <= 20 { return DartsBoard.Segment(ring: .single, number: remaining) }
        if difficulty != .casual, remaining <= 40, remaining.isMultiple(of: 2) {
            return DartsBoard.Segment(ring: .double, number: remaining / 2)
        }
        if difficulty == .sharp, remaining <= 60, remaining.isMultiple(of: 3) {
            return DartsBoard.Segment(ring: .treble, number: remaining / 3)
        }
        // Leave a number one dart can finish.
        if remaining <= 40 { return DartsBoard.Segment(ring: .single, number: remaining - 20) }
        if remaining <= 60 || difficulty == .casual { return DartsBoard.Segment(ring: .single, number: 20) }
        return DartsBoard.Segment(ring: .treble, number: 20)
    }
}
