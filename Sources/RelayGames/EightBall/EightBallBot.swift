import RelayCore

/// Practice opponent for 8-Ball. For each shot it tries every legal ball into every pocket
/// with the real physics, keeps the one that plays best, then strikes it with a little
/// error that depends on difficulty.
public struct EightBallBot: Sendable {
    public enum Difficulty: String, CaseIterable, Codable, Sendable {
        case casual
        case standard
        case sharp
    }

    public let difficulty: Difficulty

    public init(difficulty: Difficulty) {
        self.difficulty = difficulty
    }

    /// Sideways aim error per unit of direction (roughly radians).
    var aimError: Double {
        switch difficulty {
        case .casual: 0.03
        case .standard: 0.012
        case .sharp: 0.004
        }
    }

    var powerError: Double {
        switch difficulty {
        case .casual: 0.12
        case .standard: 0.06
        case .sharp: 0.03
        }
    }

    /// Plays a whole turn for the seat to act. Nil when the game is over.
    public func takeTurn<R: RandomNumberGenerator>(in state: EightBall.State, using rng: inout R) -> EightBall.Action? {
        guard let seat = state.outcome.seatToAct else { return nil }
        var shots: [EightBall.Shot] = []
        while shots.count < EightBall.maximumShotsPerTurn {
            let progress = state.progress(of: shots, by: seat)
            if progress.isComplete { break }
            shots.append(chooseShot(
                positions: progress.positions,
                groups: progress.groups,
                ballInHand: progress.ballInHand,
                isBreak: state.isBreak && shots.isEmpty,
                seat: seat,
                using: &rng
            ))
        }
        return EightBall.Action(shots: shots)
    }

    /// One shot from the given table.
    public func chooseShot<R: RandomNumberGenerator>(
        positions: [PoolTable.Vector?],
        groups: [Seat: EightBall.Group],
        ballInHand: EightBall.BallInHand,
        isBreak: Bool,
        seat: Seat,
        using rng: inout R
    ) -> EightBall.Shot {
        if isBreak {
            let offset = Int((DartsAim.normal(using: &rng) * 40).rounded())
            let placement = EightBall.Shot.Placement(x: Int(PoolTable.headSpot.x) + offset, y: Int(PoolTable.headSpot.y))
            let cue = placement.vector
            return strike(from: cue, towards: PoolTable.footSpot, power: difficulty == .casual ? 850 : 1_000, placement: placement, using: &rng)
        }

        let targets = legalTargets(positions: positions, group: groups[seat])
        var best: (score: Double, shot: EightBall.Shot)?
        for target in targets {
            guard let ball = positions[target] else { continue }
            for pocket in PoolTable.pockets {
                guard let candidate = potAttempt(ball: ball, pocket: pocket, positions: positions, ballInHand: ballInHand) else { continue }
                let score = evaluate(candidate.shot, positions: positions, groups: groups, ballInHand: ballInHand, seat: seat) + candidate.ease
                if score > (best?.score ?? -.greatestFiniteMagnitude) { best = (score, candidate.shot) }
            }
        }
        if best == nil || best!.score < 50 {
            // Nothing pots cleanly: at least hit a legal ball and avoid a foul.
            for target in targets {
                guard let ball = positions[target] else { continue }
                let (cue, placement) = cuePosition(behind: ball, from: ball + PoolTable.Vector(x: 0, y: -1), positions: positions, ballInHand: ballInHand)
                guard let cue else { continue }
                let shot = shotNumbers(from: cue, towards: ball, power: 420, placement: placement)
                let score = evaluate(shot, positions: positions, groups: groups, ballInHand: ballInHand, seat: seat)
                if score > (best?.score ?? -.greatestFiniteMagnitude) { best = (score, shot) }
            }
        }
        guard let chosen = best?.shot else {
            // Should not happen; shoot at the middle of the table.
            let placement = ballInHand == .none ? nil : EightBall.Shot.Placement(x: Int(PoolTable.headSpot.x), y: Int(PoolTable.headSpot.y))
            return EightBall.Shot(dx: 0, dy: -EightBall.directionScale, power: 400, placement: placement)
        }
        return withError(chosen, using: &rng)
    }

    func legalTargets(positions: [PoolTable.Vector?], group: EightBall.Group?) -> [Int] {
        let onTable = (1...15).filter { positions[$0] != nil }
        guard let group else { return onTable.filter { $0 != 8 } }
        let mine = onTable.filter { EightBall.Group.of($0) == group }
        return mine.isEmpty ? [8] : mine
    }

    /// Aims `ball` at `pocket` with the ghost-ball method. Nil for cuts too thin to play.
    func potAttempt(ball: PoolTable.Vector, pocket: PoolTable.Pocket, positions: [PoolTable.Vector?], ballInHand: EightBall.BallInHand) -> (shot: EightBall.Shot, ease: Double)? {
        let toPocket = pocket.target - ball
        let pocketDistance = toPocket.length
        guard pocketDistance > 1 else { return nil }
        let line = toPocket * (1 / pocketDistance)
        let ghost = ball - line * (PoolTable.ballRadius * 2)
        let (cueOrNil, placement) = cuePosition(behind: ghost, from: ghost + line, positions: positions, ballInHand: ballInHand)
        guard let cue = cueOrNil else { return nil }
        let aim = ghost - cue
        let aimDistance = aim.length
        guard aimDistance > 1 else { return nil }
        let cut = (aim * (1 / aimDistance)).dot(line)
        guard cut > 0.3 else { return nil }
        // Speed for the object ball to reach the pocket with some to spare, then for the
        // cue ball to arrive with that, allowing for the cut and the cloth.
        let objectSpeed = PoolTable.speedDrag * (pocketDistance + 250) + PoolTable.constantDrag
        let impactSpeed = objectSpeed / (cut * (1 + PoolTable.ballRestitution) / 2)
        let startSpeed = impactSpeed + PoolTable.speedDrag * aimDistance + PoolTable.constantDrag
        let fraction = (startSpeed - PoolTable.minimumCueSpeed) / (PoolTable.maximumCueSpeed - PoolTable.minimumCueSpeed)
        let power = min(EightBall.maximumPower, max(80, Int((fraction * Double(EightBall.maximumPower)).rounded())))
        let shot = shotNumbers(from: cue, towards: ghost, power: power, placement: placement)
        // Prefer straighter, shorter shots when the outcome is otherwise equal.
        return (shot, cut * 20 - (aimDistance + pocketDistance) / 400)
    }

    /// Where the cue ball is, or where to put it when in hand: a little behind `point`,
    /// away from `ahead`.
    func cuePosition(behind point: PoolTable.Vector, from ahead: PoolTable.Vector, positions: [PoolTable.Vector?], ballInHand: EightBall.BallInHand) -> (PoolTable.Vector?, EightBall.Shot.Placement?) {
        guard ballInHand != .none else { return (positions[0], nil) }
        let back = point - ahead
        let unit = back * (1 / max(back.length, 1e-9))
        for distance in [260.0, 400, 180, 600, 120] {
            let spot = point + unit * distance
            let placement = EightBall.Shot.Placement(x: Int(spot.x.rounded()), y: Int(spot.y.rounded()))
            if EightBall.isLegalPlacement(placement, ballInHand: ballInHand, positions: positions) {
                return (placement.vector, placement)
            }
        }
        // Fall back to the head spot area.
        for dx in stride(from: 0, through: 500, by: 50) {
            for sign in [1, -1] {
                let placement = EightBall.Shot.Placement(x: Int(PoolTable.headSpot.x) + sign * dx, y: Int(PoolTable.headSpot.y))
                if EightBall.isLegalPlacement(placement, ballInHand: ballInHand, positions: positions) {
                    return (placement.vector, placement)
                }
            }
        }
        return (nil, nil)
    }

    func shotNumbers(from cue: PoolTable.Vector, towards target: PoolTable.Vector, power: Int, placement: EightBall.Shot.Placement?) -> EightBall.Shot {
        let direction = target - cue
        let scale = Double(EightBall.directionScale) / max(abs(direction.x), abs(direction.y), 1e-9)
        return EightBall.Shot(
            dx: Int((direction.x * scale).rounded()),
            dy: Int((direction.y * scale).rounded()),
            power: power,
            placement: placement
        )
    }

    func strike<R: RandomNumberGenerator>(from cue: PoolTable.Vector, towards target: PoolTable.Vector, power: Int, placement: EightBall.Shot.Placement?, using rng: inout R) -> EightBall.Shot {
        withError(shotNumbers(from: cue, towards: target, power: power, placement: placement), using: &rng)
    }

    /// The rules' verdict on a shot, as a score.
    func evaluate(_ shot: EightBall.Shot, positions: [PoolTable.Vector?], groups: [Seat: EightBall.Group], ballInHand: EightBall.BallInHand, seat: Seat) -> Double {
        guard EightBall.validate(shot, ballInHand: ballInHand, positions: positions) == nil else { return -10_000 }
        var positions = positions
        var groups = groups
        var ballInHand = ballInHand
        let result = EightBall.judge(shot, by: seat, positions: &positions, groups: &groups, ballInHand: &ballInHand, isBreak: false)
        switch result.ending {
        case .won: return 1_000
        case .lost: return -1_000
        case .continues: return 100
        case .turnOver: return result.foul == nil ? 0 : -150
        }
    }

    func withError<R: RandomNumberGenerator>(_ shot: EightBall.Shot, using rng: inout R) -> EightBall.Shot {
        let direction = PoolTable.Vector(x: Double(shot.dx), y: Double(shot.dy))
        let unit = direction * (1 / direction.length)
        let nudged = unit + unit.right * (DartsAim.normal(using: &rng) * aimError)
        let scale = Double(EightBall.directionScale) / max(abs(nudged.x), abs(nudged.y))
        var result = shot
        result.dx = Int((nudged.x * scale).rounded())
        result.dy = Int((nudged.y * scale).rounded())
        let power = Double(shot.power) * (1 + DartsAim.normal(using: &rng) * powerError)
        result.power = min(EightBall.maximumPower, max(1, Int(power.rounded())))
        return result
    }
}
