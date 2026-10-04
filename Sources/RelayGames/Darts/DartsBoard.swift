import RelayCore

/// Dartboard geometry and scoring, in integer tenths of a millimetre.
///
/// Uses the conventional clock-face number order and ring proportions of a standard
/// dartboard (a generic sporting layout). Angles are compared with integer cross
/// products against fixed boundary vectors, so no floating-point maths decides a score.
public enum DartsBoard {
    public enum Ring: String, Equatable, Sendable {
        case miss
        case single
        case double
        case treble
        case outerBull
        case bull
    }

    public struct Segment: Equatable, Hashable, Sendable {
        public var ring: Ring
        /// The board number (1–20); 25 for the bull rings; 0 for a miss.
        public var number: Int

        public init(ring: Ring, number: Int) {
            self.ring = ring
            self.number = number
        }

        public static let miss = Segment(ring: .miss, number: 0)

        public var points: Int {
            switch ring {
            case .miss: 0
            case .single: number
            case .double: number * 2
            case .treble: number * 3
            case .outerBull: 25
            case .bull: 50
            }
        }

        /// Short label for scoreboards: "T20", "D16", "7", "25", "Bull", "Miss".
        public var shortName: String {
            switch ring {
            case .miss: "Miss"
            case .single: "\(number)"
            case .double: "D\(number)"
            case .treble: "T\(number)"
            case .outerBull: "25"
            case .bull: "Bull"
            }
        }

        /// Spoken form for VoiceOver.
        public var spokenName: String {
            switch ring {
            case .miss: "miss"
            case .single: "\(number)"
            case .double: "double \(number)"
            case .treble: "treble \(number)"
            case .outerBull: "outer bull, 25"
            case .bull: "bullseye, 50"
            }
        }
    }

    /// Ring edges (outer radius of each ring), tenths of a millimetre.
    public static let bullRadius = 64
    public static let outerBullRadius = 159
    public static let trebleInnerRadius = 990
    public static let trebleOuterRadius = 1_070
    public static let doubleInnerRadius = 1_620
    public static let doubleOuterRadius = 1_700

    /// Board numbers clockwise from the top.
    public static let numbers = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

    /// Unit vectors (×1,000,000, x right, y up) of each sector's anticlockwise edge:
    /// entry k is at 18k − 9 degrees clockwise from the top. Precomputed constants so
    /// scoring never depends on a platform's trigonometry.
    static let sectorEdges: [(x: Int64, y: Int64)] = [
        (-156_434, 987_688),
        (156_434, 987_688),
        (453_990, 891_007),
        (707_107, 707_107),
        (891_007, 453_990),
        (987_688, 156_434),
        (987_688, -156_434),
        (891_007, -453_990),
        (707_107, -707_107),
        (453_990, -891_007),
        (156_434, -987_688),
        (-156_434, -987_688),
        (-453_990, -891_007),
        (-707_107, -707_107),
        (-891_007, -453_990),
        (-987_688, -156_434),
        (-987_688, 156_434),
        (-891_007, 453_990),
        (-707_107, 707_107),
        (-453_990, 891_007),
    ]

    public static func segment(at hit: Darts.Hit) -> Segment {
        let x = Int64(hit.x), y = Int64(hit.y)
        let distanceSquared = x * x + y * y
        func within(_ radius: Int) -> Bool { distanceSquared <= Int64(radius) * Int64(radius) }

        if within(bullRadius) { return Segment(ring: .bull, number: 25) }
        if within(outerBullRadius) { return Segment(ring: .outerBull, number: 25) }
        guard within(doubleOuterRadius) else { return .miss }
        let number = numbers[sectorIndex(x: x, y: y)]
        if within(trebleInnerRadius) { return Segment(ring: .single, number: number) }
        if within(trebleOuterRadius) { return Segment(ring: .treble, number: number) }
        if within(doubleInnerRadius) { return Segment(ring: .single, number: number) }
        return Segment(ring: .double, number: number)
    }

    /// Index into `numbers` of the sector containing the (non-zero) point. A point exactly
    /// on an edge belongs to the sector clockwise of it.
    static func sectorIndex(x: Int64, y: Int64) -> Int {
        for index in 0..<numbers.count {
            let low = sectorEdges[index]
            let high = sectorEdges[(index + 1) % numbers.count]
            // Clockwise of (or on) the low edge, and strictly anticlockwise of the high edge.
            if low.x * y - low.y * x <= 0 && high.x * y - high.y * x > 0 {
                return index
            }
        }
        return 0 // Unreachable for a non-zero point; the bull handles the centre.
    }

    /// Centre of a segment, for aiming (bot targets, tests). Uses floating point because
    /// it only chooses where to aim; scoring never calls it.
    public static func target(for segment: Segment) -> Darts.Hit {
        switch segment.ring {
        case .miss: return Darts.Hit(x: 0, y: doubleOuterRadius + 300)
        case .bull, .outerBull: return Darts.Hit(x: 0, y: segment.ring == .bull ? 0 : (bullRadius + outerBullRadius) / 2)
        default: break
        }
        guard let index = numbers.firstIndex(of: segment.number) else { return Darts.Hit(x: 0, y: 0) }
        let radius: Double
        switch segment.ring {
        case .treble: radius = Double(trebleInnerRadius + trebleOuterRadius) / 2
        case .double: radius = Double(doubleInnerRadius + doubleOuterRadius) / 2
        default: radius = Double(trebleOuterRadius + doubleInnerRadius) / 2
        }
        let angle = Double(index) * 18 * Double.pi / 180
        return Darts.Hit(x: Int((radius * sine(angle)).rounded()), y: Int((radius * cosine(angle)).rounded()))
    }
}

// Small series so RelayGames needs no Foundation import; only used for aiming.
func sine(_ angle: Double) -> Double {
    var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
    if a > .pi { a -= 2 * .pi } else if a < -.pi { a += 2 * .pi }
    var term = a, sum = a
    for n in 1...12 {
        term *= -a * a / Double((2 * n) * (2 * n + 1))
        sum += term
    }
    return sum
}

func cosine(_ angle: Double) -> Double {
    sine(angle + .pi / 2)
}
