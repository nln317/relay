import RelayCore

/// Turns an aim into a landing point. This is input, not rules: the sending device
/// decides where its darts land and the rules only score them (docs/ARCHITECTURE.md,
/// "Skill games"). Kept here, pure and seedable, so the practice bot and tests share it.
public enum DartsAim {
    /// How far the aim drifts while the player holds the dart, in tenths of a millimetre.
    /// It starts steady and grows the longer they hold, which rewards a decisive throw.
    public static func swayAmplitude(heldFor seconds: Double) -> Double {
        60 + 45 * min(max(seconds, 0), 3)
    }

    /// Hand sway at `seconds` after picking up the dart: a slow, smooth wander.
    /// `phase` varies it per dart so no two throws drift identically.
    public static func sway(heldFor seconds: Double, phase: Double) -> (x: Int, y: Int) {
        let amplitude = swayAmplitude(heldFor: seconds)
        let x = amplitude * sine(2 * .pi * seconds / 1.3 + phase)
        let y = amplitude * 0.8 * sine(2 * .pi * seconds / 1.75 + phase * 1.7)
        return (Int(x.rounded()), Int(y.rounded()))
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
