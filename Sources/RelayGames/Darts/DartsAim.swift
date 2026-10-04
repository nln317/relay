import Foundation
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
    ///   - dartX: where the dart rests across the screen, when it is held there rather
    ///     than under the finger: the throw then starts from the dart, carried sideways by
    ///     only part of the finger's drift (`sideFollow`), not from wherever the finger
    ///     happened to touch it.
    public static func flickTarget(start: (x: Double, y: Double), release: (x: Double, y: Double), velocity: (x: Double, y: Double), dartX: Double? = nil) -> (x: Double, y: Double)? {
        let upwardSpeed = -velocity.y
        guard upwardSpeed >= minimumThrowSpeed, start.y > release.y else { return nil }
        // Height follows the ratio of speeds: a moderate flick reaches the bull, and every
        // doubling of speed (or halving) moves the dart the same distance up (or down), so
        // the bottom of the board is as reachable as the top.
        let height = 0.5 - reachPerDoubling * log2(upwardSpeed / bullSpeed)
        // Follow the line of the swipe up to that height. A near-flat swipe would run off
        // to infinity, so the slope is capped (the rules clamp anything off the board).
        let slope = min(max(aimSlope(start: start, release: release, velocity: velocity), -1.5), 1.5)
        let origin = dartX.map { $0 + sideFollow * (release.x - start.x) } ?? release.x
        return (origin + slope * max(0, release.y - height), height)
    }

    /// How much of the finger's sideways drift moves the held dart.
    public static let sideFollow = 0.5

    /// Sideways drift per unit of height, read mostly from the whole swipe (where the
    /// finger started to where it let go) rather than the last instant of it: a thumb
    /// naturally hooks a little as it lets go, and reading only the release velocity
    /// turned that hook into darts that never went straight. A tiny lean is treated as
    /// straight, and anything larger loses that same small amount, so it stays smooth.
    static func aimSlope(start: (x: Double, y: Double), release: (x: Double, y: Double), velocity: (x: Double, y: Double)) -> Double {
        let releaseSlope = velocity.x / -velocity.y
        let rise = start.y - release.y
        let raw: Double
        if rise >= minimumAimRise {
            let swipeSlope = (release.x - start.x) / rise
            raw = swipeSlope * (1 - releaseWeight) + releaseSlope * releaseWeight
        } else {
            // A short flick has no line of its own to read; its velocity is all there is.
            raw = releaseSlope
        }
        let lean = max(0, abs(raw) - straightTolerance)
        return raw < 0 ? -lean : lean
    }

    /// How much the release velocity counts towards the aim, against the whole swipe's line.
    static let releaseWeight = 0.2
    /// Swipes shorter than this (board widths) aim by release velocity alone.
    static let minimumAimRise = 0.06
    /// A lean this small (about 3 degrees) still flies straight.
    static let straightTolerance = 0.05

    /// Slower than this (board widths per second) and the dart is not thrown. The softest
    /// throws fall short of the board, so a feeble flick misses low.
    public static let minimumThrowSpeed = 0.3
    /// Flick speed (board widths per second) that reaches the bull.
    public static let bullSpeed = 3.0
    /// Board widths the dart climbs for each doubling of flick speed. With these, about
    /// 1.4 widths a second reaches the bottom double, 3 the bull, 4.7 the treble 20 and
    /// 6.6 the top double. Tuned on device with Nathan (2026-10-04): a straight-line
    /// mapping made the bull heavy and the top touchy; a square-root one left the bottom
    /// out of reach of soft flicks and the top too heavy.
    public static let reachPerDoubling = 1.0 / 3.0

    /// Scatter grows when the flick is wild (much harder than the top of the board
    /// needs), in tenths of a millimetre.
    public static func scatter(forSpeed speed: Double) -> Double {
        releaseScatter + 30 * max(0, speed - 8)
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
