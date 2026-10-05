/// The pool table and the physics that moves the balls.
///
/// Every shot is replayed by every device from its integer inputs (EightBall.Shot), so the
/// simulation must give bit-identical results everywhere. It therefore uses only
/// addition, subtraction, multiplication, division and square roots on `Double`, which
/// IEEE 754 rounds identically on every platform. No trigonometry, no randomness, a fixed
/// time step and a fixed order of operations. A golden test pins the result of a break.
///
/// Units are millimetres and seconds. The table is seen from above in portrait: x runs
/// across (0 at the left cushion), y runs down the length (0 at the top cushion). The
/// cue ball breaks from the bottom; the rack sits at the top.
public enum PoolTable {
    /// Playing surface between the cushion noses: a 9-foot table.
    public static let width = 1_270.0
    public static let length = 2_540.0
    public static let ballRadius = 28.575

    /// The line the cue ball is placed behind for the break (the "kitchen" is below it).
    public static let headString = length * 0.75
    /// Where the front ball of the rack (and a re-spotted 8) sits.
    public static let footSpot = Vector(x: width / 2, y: length * 0.25)
    /// Where the cue ball starts.
    public static let headSpot = Vector(x: width / 2, y: length * 0.75 + 120)

    /// Fastest cue ball, for a full-power shot.
    public static let maximumCueSpeed = 6_000.0
    public static let minimumCueSpeed = 150.0

    public struct Vector: Equatable, Hashable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        public static let zero = Vector(x: 0, y: 0)
        public static func + (a: Vector, b: Vector) -> Vector { Vector(x: a.x + b.x, y: a.y + b.y) }
        public static func - (a: Vector, b: Vector) -> Vector { Vector(x: a.x - b.x, y: a.y - b.y) }
        public static func * (a: Vector, k: Double) -> Vector { Vector(x: a.x * k, y: a.y * k) }
        public func dot(_ b: Vector) -> Double { x * b.x + y * b.y }
        public var length: Double { (x * x + y * y).squareRoot() }
        var lengthSquared: Double { x * x + y * y }
        /// To the right of this direction on screen (y grows downwards).
        var right: Vector { Vector(x: -y, y: x) }
    }

    /// A pocket: balls whose centre comes within `radius` of `centre` drop.
    public struct Pocket: Equatable, Sendable {
        public let centre: Vector
        public let radius: Double
        /// Where to aim a ball to sink it: just inside the mouth.
        public let target: Vector
    }

    /// Corners clockwise from top left, then the left and right side pockets.
    public static let pockets: [Pocket] = [
        Pocket(centre: Vector(x: -8, y: -8), radius: 60, target: Vector(x: 22, y: 22)),
        Pocket(centre: Vector(x: width + 8, y: -8), radius: 60, target: Vector(x: width - 22, y: 22)),
        Pocket(centre: Vector(x: width + 8, y: length + 8), radius: 60, target: Vector(x: width - 22, y: length - 22)),
        Pocket(centre: Vector(x: -8, y: length + 8), radius: 60, target: Vector(x: 22, y: length - 22)),
        Pocket(centre: Vector(x: -25, y: length / 2), radius: 50, target: Vector(x: 12, y: length / 2)),
        Pocket(centre: Vector(x: width + 25, y: length / 2), radius: 50, target: Vector(x: width - 12, y: length / 2)),
    ]

    /// How far the cushions stop short of a corner, and half the side pockets' gap.
    static let cornerGap = 80.0
    static let sideGap = 60.0

    /// A straight cushion along one rail. The ball bounces off it when its centre comes
    /// within a radius of the line, between `from` and `to`.
    struct Cushion {
        enum Axis { case vertical, horizontal }
        let axis: Axis
        /// x for a vertical cushion, y for a horizontal one.
        let line: Double
        let from: Double
        let to: Double
        /// Unit normal pointing into the table.
        let normal: Vector
    }

    static let cushions: [Cushion] = [
        // Top and bottom.
        Cushion(axis: .horizontal, line: 0, from: cornerGap, to: width - cornerGap, normal: Vector(x: 0, y: 1)),
        Cushion(axis: .horizontal, line: length, from: cornerGap, to: width - cornerGap, normal: Vector(x: 0, y: -1)),
        // Left, either side of the side pocket.
        Cushion(axis: .vertical, line: 0, from: cornerGap, to: length / 2 - sideGap, normal: Vector(x: 1, y: 0)),
        Cushion(axis: .vertical, line: 0, from: length / 2 + sideGap, to: length - cornerGap, normal: Vector(x: 1, y: 0)),
        // Right.
        Cushion(axis: .vertical, line: width, from: cornerGap, to: length / 2 - sideGap, normal: Vector(x: -1, y: 0)),
        Cushion(axis: .vertical, line: width, from: length / 2 + sideGap, to: length - cornerGap, normal: Vector(x: -1, y: 0)),
    ]

    /// The rounded cushion ends either side of each pocket mouth.
    static let knuckles: [Vector] = [
        Vector(x: cornerGap, y: 0), Vector(x: width - cornerGap, y: 0),
        Vector(x: cornerGap, y: length), Vector(x: width - cornerGap, y: length),
        Vector(x: 0, y: cornerGap), Vector(x: 0, y: length - cornerGap),
        Vector(x: width, y: cornerGap), Vector(x: width, y: length - cornerGap),
        Vector(x: 0, y: length / 2 - sideGap), Vector(x: 0, y: length / 2 + sideGap),
        Vector(x: width, y: length / 2 - sideGap), Vector(x: width, y: length / 2 + sideGap),
    ]

    /// The standard rack: apex on the foot spot pointing at the cue ball, the 8 in the
    /// middle of the third row, a solid and a stripe in the back corners.
    public static func rack() -> [Vector?] {
        // Ball numbers by rack position, front row first, left to right.
        let order = [1, 9, 2, 10, 8, 3, 11, 7, 14, 4, 5, 13, 15, 6, 12]
        var positions = [Vector?](repeating: nil, count: 16)
        positions[0] = headSpot
        let gap = ballRadius * 2 + 0.5
        // Row spacing for touching balls: sqrt(3) * radius, written out to avoid
        // depending on a library constant.
        let rowStep = gap * 0.8660254037844386
        var index = 0
        for row in 0..<5 {
            for column in 0...row {
                let x = footSpot.x + (Double(column) - Double(row) / 2) * gap
                let y = footSpot.y - Double(row) * rowStep
                positions[order[index]] = Vector(x: x, y: y)
                index += 1
            }
        }
        return positions
    }

    /// True when a ball centred at `point` lies on the cloth, clear of the cushions.
    public static func isOnCloth(_ point: Vector) -> Bool {
        point.x >= ballRadius && point.x <= width - ballRadius && point.y >= ballRadius && point.y <= length - ballRadius
    }

    // MARK: - Simulation

    /// What happened during one shot.
    public struct ShotOutcome: Equatable, Sendable {
        /// Ball positions when everything stopped; nil for pocketed balls (index 0 is the cue ball).
        public var positions: [Vector?]
        /// Balls that dropped, in the order they dropped.
        public var pocketed: [Int]
        /// The first object ball the cue ball touched.
        public var firstContact: Int?
        /// Cushion contacts by any ball after the cue ball first touched an object ball.
        public var cushionsAfterContact: Int
        /// Frames for animation, 60 a second, when asked for.
        public var frames: [[Vector?]]
        /// Moments worth a sound or a haptic, by frame.
        public var events: [Event]
    }

    public enum Event: Equatable, Sendable {
        case ballHit(frame: Int, speed: Double)
        case cushionHit(frame: Int, speed: Double)
        case pocketed(frame: Int, ball: Int, pocket: Int)
    }

    /// The physics step: 960 a second, so a 60-frame-a-second recording keeps every 16th.
    static let stepsPerSecond = 960.0
    static let stepsPerFrame = 16
    /// A shot that has not settled after this long is stopped where it is.
    static let maximumSteps = 960 * 14

    /// Rolling resistance: a constant part and a part proportional to speed (mm/s² and 1/s).
    static let constantDrag = 180.0
    static let speedDrag = 0.75
    /// Below this speed (mm/s) a ball stops.
    static let restSpeed = 4.0
    static let ballRestitution = 0.95
    static let cushionRestitution = 0.78
    /// How strongly follow (topspin) or draw (backspin) carries on after the first hit.
    static let followStrength = 0.6
    /// How strongly side spin bends the cue ball off a cushion.
    static let sideStrength = 0.35

    /// Plays a shot from `positions`: the cue ball leaves at `velocity` with `follow` and
    /// `side` spin (each -1...1). Deterministic; see the note at the top of this file.
    public static func simulate(positions start: [Vector?], velocity: Vector, follow: Double, side: Double, recordFrames: Bool) -> ShotOutcome {
        let count = start.count
        var position = start.map { $0 ?? .zero }
        var onTable = start.map { $0 != nil }
        var velocities = [Vector](repeating: .zero, count: count)
        velocities[0] = velocity
        var moving = [Bool](repeating: false, count: count)
        moving[0] = onTable[0]
        var follow = follow
        var side = side
        let shotDirection = velocity * (1 / max(velocity.length, 1e-9))

        var pocketed: [Int] = []
        var firstContact: Int?
        var cushionsAfterContact = 0
        var frames: [[Vector?]] = []
        var events: [Event] = []
        let dt = 1 / stepsPerSecond
        let twoR = ballRadius * 2
        let twoRSquared = twoR * twoR

        func snapshot() -> [Vector?] {
            (0..<count).map { onTable[$0] ? position[$0] : nil }
        }
        if recordFrames { frames.append(snapshot()) }

        var step = 0
        while step < maximumSteps {
            step += 1
            let frame = (step + stepsPerFrame - 1) / stepsPerFrame

            // Move and slow down.
            var anyMoving = false
            for i in 0..<count where onTable[i] && moving[i] {
                position[i] = position[i] + velocities[i] * dt
                let speed = velocities[i].length
                let slower = speed - (constantDrag + speedDrag * speed) * dt
                if slower <= restSpeed {
                    velocities[i] = .zero
                    moving[i] = false
                } else {
                    velocities[i] = velocities[i] * (slower / speed)
                    anyMoving = true
                }
            }

            // Ball against ball. Only pairs with a moving ball can start touching.
            for i in 0..<count where onTable[i] {
                for j in (i + 1)..<count where onTable[j] && (moving[i] || moving[j]) {
                    let delta = position[j] - position[i]
                    let distanceSquared = delta.lengthSquared
                    guard distanceSquared < twoRSquared, distanceSquared > 0 else { continue }
                    let distance = distanceSquared.squareRoot()
                    let normal = delta * (1 / distance)
                    // Separate the overlap evenly.
                    let push = (twoR - distance) / 2
                    position[i] = position[i] - normal * push
                    position[j] = position[j] + normal * push
                    let approach = (velocities[i] - velocities[j]).dot(normal)
                    guard approach > 0 else { continue }
                    let impulse = approach * (1 + ballRestitution) / 2
                    let cueBefore = velocities[0]
                    velocities[i] = velocities[i] - normal * impulse
                    velocities[j] = velocities[j] + normal * impulse
                    moving[i] = true
                    moving[j] = true
                    anyMoving = true
                    events.append(.ballHit(frame: frame, speed: approach))
                    if i == 0, firstContact == nil {
                        firstContact = j
                        // Follow or draw: the cue ball carries on along (or back down)
                        // its line, in proportion to how fast it arrived.
                        if follow != 0 {
                            let along = shotDirection * (follow * followStrength * cueBefore.length)
                            velocities[0] = velocities[0] + along
                            follow = 0
                        }
                    }
                }
            }

            // Cushions and the knuckles at the pocket mouths.
            for i in 0..<count where onTable[i] && moving[i] {
                for cushion in cushions {
                    let (along, across) = cushion.axis == .horizontal
                        ? (position[i].x, position[i].y)
                        : (position[i].y, position[i].x)
                    guard along >= cushion.from, along <= cushion.to else { continue }
                    let gap = (across - cushion.line) * (cushion.axis == .horizontal ? cushion.normal.y : cushion.normal.x)
                    guard gap < ballRadius else { continue }
                    let normalSpeed = velocities[i].dot(cushion.normal)
                    // Put the ball back on the cushion's face.
                    let correction = ballRadius - gap
                    position[i] = position[i] + cushion.normal * correction
                    guard normalSpeed < 0 else { continue }
                    let incoming = velocities[i]
                    velocities[i] = velocities[i] - cushion.normal * (normalSpeed * (1 + cushionRestitution))
                    if i == 0, side != 0 {
                        // Side spin pushes the rebound towards the side it was struck on.
                        let direction = incoming * (1 / max(incoming.length, 1e-9))
                        let tangent = Vector(x: -cushion.normal.y, y: cushion.normal.x)
                        let push = direction.right.dot(tangent) >= 0 ? tangent : tangent * -1
                        velocities[0] = velocities[0] + push * (side * sideStrength * -normalSpeed)
                        side *= 0.5
                    }
                    events.append(.cushionHit(frame: frame, speed: -normalSpeed))
                    if firstContact != nil { cushionsAfterContact += 1 }
                }
                for knuckle in knuckles {
                    let delta = position[i] - knuckle
                    let distanceSquared = delta.lengthSquared
                    guard distanceSquared < ballRadius * ballRadius, distanceSquared > 0 else { continue }
                    let distance = distanceSquared.squareRoot()
                    let normal = delta * (1 / distance)
                    position[i] = position[i] + normal * (ballRadius - distance)
                    let normalSpeed = velocities[i].dot(normal)
                    guard normalSpeed < 0 else { continue }
                    velocities[i] = velocities[i] - normal * (normalSpeed * (1 + cushionRestitution))
                    events.append(.cushionHit(frame: frame, speed: -normalSpeed))
                    if firstContact != nil { cushionsAfterContact += 1 }
                }
            }

            // Pockets. A ball that has somehow left the table drops in the nearest one.
            for i in 0..<count where onTable[i] {
                var dropped: Int?
                for (index, pocket) in pockets.enumerated() {
                    if (position[i] - pocket.centre).lengthSquared < pocket.radius * pocket.radius {
                        dropped = index
                        break
                    }
                }
                if dropped == nil, !isInsideRails(position[i]) {
                    dropped = nearestPocket(to: position[i])
                }
                if let dropped {
                    onTable[i] = false
                    moving[i] = false
                    velocities[i] = .zero
                    pocketed.append(i)
                    events.append(.pocketed(frame: frame, ball: i, pocket: dropped))
                }
            }

            if recordFrames, step % stepsPerFrame == 0 { frames.append(snapshot()) }
            if !anyMoving && !moving.contains(true) { break }
        }
        if recordFrames, step % stepsPerFrame != 0 { frames.append(snapshot()) }

        return ShotOutcome(
            positions: snapshot(),
            pocketed: pocketed,
            firstContact: firstContact,
            cushionsAfterContact: cushionsAfterContact,
            frames: frames,
            events: events
        )
    }

    /// Generous bounds: a ball's centre may run a little past a rail line in a pocket mouth.
    static func isInsideRails(_ point: Vector) -> Bool {
        let slack = ballRadius * 1.5
        return point.x > -slack && point.x < width + slack && point.y > -slack && point.y < length + slack
    }

    static func nearestPocket(to point: Vector) -> Int {
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, pocket) in pockets.enumerated() {
            let distance = (point - pocket.centre).lengthSquared
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }
}
