import Foundation
import RelayCore

/// Turns a swipe into where the ball comes down. Input, not rules: the thrower's device
/// decides the landing and the rules only judge it (docs/ARCHITECTURE.md, "Skill games").
public enum CupPongAim {
    /// Where a flicked ball lands, or nil when the gesture was not a throw (too slow,
    /// sideways or downwards).
    ///
    /// Measured in screen widths with y growing downwards, so the feel is the same on every
    /// phone. Speed sets how far the ball flies: each doubling of speed carries it the same
    /// distance further, so short and long throws are equally controllable. The line of
    /// the swipe sets how far it drifts left or right, more the further it flies.
    public static func flickLanding(start: (x: Double, y: Double), release: (x: Double, y: Double), velocity: (x: Double, y: Double)) -> CupPong.Landing? {
        let upwardSpeed = -velocity.y
        guard upwardSpeed >= minimumThrowSpeed, start.y > release.y else { return nil }
        let depth = Double(rackCentreY) + log2(upwardSpeed / rackSpeed) * depthPerDoubling
        let slope = min(max(DartsAim.aimSlope(start: start, release: release, velocity: velocity), -1.5), 1.5)
        let across = slope * max(0, depth) * drift
        return CupPong.Landing(x: Int(across.rounded()), y: Int(depth.rounded()))
    }

    /// Slower than this (screen widths per second) and the ball is not thrown.
    public static let minimumThrowSpeed = 0.3
    /// Swipe speed (screen widths per second) that lands in the middle of the full rack.
    public static let rackSpeed = 2.6
    /// Millimetres further the ball flies for each doubling of swipe speed.
    public static let depthPerDoubling = 420.0
    /// Sideways millimetres per millimetre of flight for each unit of swipe slope.
    public static let drift = 0.4
    /// Middle of the full rack, from the thrower's edge.
    public static let rackCentreY = CupPong.Table.backRowY - CupPong.Table.rowStep * 3 / 2

    /// Swipe speed that carries the ball `depth` millimetres, the inverse of the above.
    public static func speed(forDepth depth: Double) -> Double {
        rackSpeed * pow(2, (depth - Double(rackCentreY)) / depthPerDoubling)
    }
}

/// Practice opponent: picks a cup and throws at it with a scatter that depends on
/// difficulty.
public struct CupPongBot: Sendable {
    public enum Difficulty: String, CaseIterable, Codable, Sendable {
        case casual
        case standard
        case sharp
    }

    public let difficulty: Difficulty

    public init(difficulty: Difficulty) {
        self.difficulty = difficulty
    }

    /// Standard deviation of the landing across and along the table, in millimetres.
    var scatter: (across: Double, along: Double) {
        switch difficulty {
        case .casual: (62, 85)
        case .standard: (40, 55)
        case .sharp: (26, 34)
        }
    }

    /// One ball at the cups standing now.
    public func nextLanding<R: RandomNumberGenerator>(at cups: [CupPong.Cup], using rng: inout R) -> CupPong.Landing {
        guard !cups.isEmpty else { return CupPong.Landing(x: 0, y: CupPongAim.rackCentreY) }
        let cup = cups[Int.random(in: 0..<cups.count, using: &rng)]
        let x = Double(cup.x) + DartsAim.normal(using: &rng) * scatter.across
        let y = Double(cup.y) + DartsAim.normal(using: &rng) * scatter.along
        return CupPong.Landing(x: Int(x.rounded()), y: Int(y.rounded()))
    }

    /// A whole turn for the seat to act. Nil when the game is over.
    public func takeTurn<R: RandomNumberGenerator>(in state: CupPong.State, using rng: inout R) -> CupPong.Action? {
        guard let seat = state.outcome.seatToAct else { return nil }
        var landings: [CupPong.Landing] = []
        while true {
            let progress = state.progress(of: landings, by: seat)
            if progress.isComplete { break }
            landings.append(nextLanding(at: progress.cups, using: &rng))
        }
        return CupPong.Action(landings: landings)
    }
}
