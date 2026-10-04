#if canImport(UIKit)
import RelayCore
import RelayGames
import SwiftUI

/// Board units (tenths of a millimetre) from the bull to the outside of the number ring.
private let drawnRadius = 2_250.0

/// Shared timings, so the score, the points pop and the stuck dart all follow the flight.
enum DartsTiming {
    /// Seconds from release to the dart hitting the board.
    static let flight = 0.24
}

/// A dart on the board: where it landed and whose it is.
public struct PlacedDart: Equatable, Identifiable, Sendable {
    public var id: Int
    public var hit: Darts.Hit
    public var seat: Seat

    public init(id: Int, hit: Darts.Hit, seat: Seat) {
        self.id = id
        self.hit = hit
        self.seat = seat
    }
}

// MARK: - Board

/// Traditional dartboard colours, which belong to the sport rather than to any app.
enum DartboardColours {
    static let black = Color(white: 0.08)
    static let white = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let red = Color(red: 0.86, green: 0.11, blue: 0.13)
    static let green = Color(red: 0.05, green: 0.55, blue: 0.27)
    static let surround = Color(white: 0.05)
    static let highlight = Color(red: 1.0, green: 0.92, blue: 0.45)
}

/// Where board positions land in a view, and how big things on the board are drawn.
struct BoardMapping {
    let centre: CGPoint
    /// Points from the bull to the outside of the number ring.
    let radius: CGFloat
    /// Where stuck darts may be drawn; far misses are pulled inside it.
    let bounds: CGRect

    var scale: CGFloat { radius / CGFloat(drawnRadius) }

    /// The view point for a board position, kept inside `bounds` so far misses stay visible.
    func point(for hit: Darts.Hit) -> CGPoint {
        let raw = CGPoint(x: centre.x + CGFloat(hit.x) * scale, y: centre.y - CGFloat(hit.y) * scale)
        let size = stuckSize
        let minX = bounds.minX + size.width / 2, maxX = max(minX, bounds.maxX - size.width / 2)
        let minY = bounds.minY + 4, maxY = max(minY, bounds.maxY - size.height)
        return CGPoint(x: min(max(raw.x, minX), maxX), y: min(max(raw.y, minY), maxY))
    }

    /// A dart stuck in the board, seen from the oche: short, because it points at you.
    var stuckSize: CGSize { CGSize(width: 580 * scale, height: 780 * scale) }

    /// Darts lean a little away from the middle, as if thrown from in front of the bull.
    func tilt(for hit: Darts.Hit) -> Double {
        min(max(Double(hit.x) / 3_000 * 14, -14), 14)
    }
}

/// Draws a classic dartboard: black and white beds, red and green scoring rings, a black
/// number ring with white numbers. Our own drawing of the sport's standard look.
enum DartboardPainter {
    static func draw(in context: inout GraphicsContext, mapping: BoardMapping, highlight: DartsBoard.Segment? = nil, castsShadow: Bool = false) {
        let centre = mapping.centre, scale = mapping.scale
        func circle(_ radius: Double, dy: CGFloat = 0) -> Path {
            let r = CGFloat(radius) * scale
            return Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r + dy, width: r * 2, height: r * 2))
        }
        func wedge(_ index: Int, inner: Int, outer: Int) -> Path {
            // Sector `index` is centred 18·index degrees clockwise from the top.
            let middle = -90.0 + 18 * Double(index)
            var path = Path()
            path.addArc(center: centre, radius: CGFloat(outer) * scale, startAngle: .degrees(middle - 9), endAngle: .degrees(middle + 9), clockwise: false)
            path.addArc(center: centre, radius: CGFloat(inner) * scale, startAngle: .degrees(middle + 9), endAngle: .degrees(middle - 9), clockwise: true)
            path.closeSubpath()
            return path
        }

        if castsShadow {
            var shadow = context
            shadow.addFilter(.blur(radius: mapping.radius * 0.05))
            shadow.fill(circle(drawnRadius, dy: mapping.radius * 0.05), with: .color(.black.opacity(0.6)))
        }
        context.fill(circle(drawnRadius), with: .color(DartboardColours.surround))

        for index in 0..<DartsBoard.numbers.count {
            let even = index.isMultiple(of: 2)
            let bed = even ? DartboardColours.black : DartboardColours.white
            let ring = even ? DartboardColours.red : DartboardColours.green
            context.fill(wedge(index, inner: DartsBoard.outerBullRadius, outer: DartsBoard.trebleInnerRadius), with: .color(bed))
            context.fill(wedge(index, inner: DartsBoard.trebleInnerRadius, outer: DartsBoard.trebleOuterRadius), with: .color(ring))
            context.fill(wedge(index, inner: DartsBoard.trebleOuterRadius, outer: DartsBoard.doubleInnerRadius), with: .color(bed))
            context.fill(wedge(index, inner: DartsBoard.doubleInnerRadius, outer: DartsBoard.doubleOuterRadius), with: .color(ring))
        }

        if let highlight, highlight.ring != .bull, highlight.ring != .outerBull, highlight.ring != .miss,
           let index = DartsBoard.numbers.firstIndex(of: highlight.number) {
            context.fill(wedge(index, inner: DartsBoard.outerBullRadius, outer: DartsBoard.doubleOuterRadius), with: .color(DartboardColours.highlight.opacity(0.7)))
        }

        context.fill(circle(Double(DartsBoard.outerBullRadius)), with: .color(DartboardColours.green))
        context.fill(circle(Double(DartsBoard.bullRadius)), with: .color(DartboardColours.red))
        if let highlight, highlight.ring == .bull || highlight.ring == .outerBull {
            context.fill(circle(Double(DartsBoard.outerBullRadius)), with: .color(DartboardColours.highlight.opacity(0.65)))
        }

        // Thin wire between the beds.
        let wire = GraphicsContext.Shading.color(Color(white: 0.75).opacity(0.55))
        let wireWidth = max(0.5, mapping.radius * 0.004)
        for radius in [DartsBoard.outerBullRadius, DartsBoard.trebleInnerRadius, DartsBoard.trebleOuterRadius, DartsBoard.doubleInnerRadius, DartsBoard.doubleOuterRadius] {
            context.stroke(circle(Double(radius)), with: wire, lineWidth: wireWidth)
        }
        for index in 0..<DartsBoard.numbers.count {
            let angle = (-90.0 + 18 * Double(index) - 9) * .pi / 180
            let inner = CGFloat(DartsBoard.outerBullRadius) * scale, outer = CGFloat(DartsBoard.doubleOuterRadius) * scale
            var spoke = Path()
            spoke.move(to: CGPoint(x: centre.x + inner * CGFloat(cos(angle)), y: centre.y + inner * CGFloat(sin(angle))))
            spoke.addLine(to: CGPoint(x: centre.x + outer * CGFloat(cos(angle)), y: centre.y + outer * CGFloat(sin(angle))))
            context.stroke(spoke, with: wire, lineWidth: wireWidth)
        }

        let fontSize = max(7, CGFloat(drawnRadius - Double(DartsBoard.doubleOuterRadius)) * scale * 0.62)
        for (index, number) in DartsBoard.numbers.enumerated() {
            let angle = (-90.0 + 18 * Double(index)) * .pi / 180
            let radius = CGFloat(Double(DartsBoard.doubleOuterRadius) + drawnRadius) / 2 * scale
            let position = CGPoint(x: centre.x + radius * CGFloat(cos(angle)), y: centre.y + radius * CGFloat(sin(angle)))
            context.draw(
                Text("\(number)").font(.system(size: fontSize, weight: .heavy, design: .rounded)).foregroundStyle(Color.white),
                at: position
            )
        }
    }
}

/// A dartboard with darts stuck in it, for still pictures: message bubbles and the game list.
public struct DartsBoardView: View {
    let darts: [PlacedDart]
    /// False for still images (bubble art), which render before any animation runs.
    let animatesDarts: Bool
    @Environment(\.seatPalette) private var palette

    public init(darts: [PlacedDart], animatesDarts: Bool = true) {
        self.darts = darts
        self.animatesDarts = animatesDarts
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let mapping = BoardMapping(centre: CGPoint(x: side / 2, y: side / 2), radius: side / 2, bounds: CGRect(x: 0, y: 0, width: side, height: side))
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    DartboardPainter.draw(in: &context, mapping: mapping)
                }
                .accessibilityHidden(true)
                ForEach(darts) { dart in
                    StuckDart(colour: palette.colour(dart.seat), tilt: mapping.tilt(for: dart.hit), animates: animatesDarts)
                        .frame(width: mapping.stuckSize.width, height: mapping.stuckSize.height)
                        .position(x: mapping.point(for: dart.hit).x, y: mapping.point(for: dart.hit).y + mapping.stuckSize.height / 2)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Darts

/// A dart drawn pointing up: steel point, dark barrel with steel grip rings, a thin shaft
/// and flights in the thrower's colour (two side-on, one behind). Our own drawing, sized
/// by its frame.
struct ThrowingDart: View {
    let flights: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height, mid = w / 2
            func bar(_ top: CGFloat, _ bottom: CGFloat, width: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: mid - width / 2, y: h * top, width: width, height: h * (bottom - top)), cornerRadius: width / 2)
            }
            var point = Path()
            point.move(to: CGPoint(x: mid, y: 0))
            point.addLine(to: CGPoint(x: mid + w * 0.035, y: h * 0.2))
            point.addLine(to: CGPoint(x: mid - w * 0.035, y: h * 0.2))
            point.closeSubpath()
            context.fill(point, with: .linearGradient(
                Gradient(colors: [Color(white: 0.95), Color(white: 0.6)]),
                startPoint: CGPoint(x: mid - w * 0.04, y: 0), endPoint: CGPoint(x: mid + w * 0.04, y: 0)
            ))

            // The flight behind, darker, then the two side flights.
            var back = Path()
            back.move(to: CGPoint(x: mid, y: h * 0.58))
            back.addLine(to: CGPoint(x: mid + w * 0.12, y: h * 0.86))
            back.addLine(to: CGPoint(x: mid, y: h * 0.97))
            back.addLine(to: CGPoint(x: mid - w * 0.12, y: h * 0.86))
            back.closeSubpath()
            context.fill(back, with: .color(flights))
            context.fill(back, with: .color(.black.opacity(0.35)))
            for side in [-1.0, 1.0] {
                var fin = Path()
                fin.move(to: CGPoint(x: mid, y: h * 0.56))
                fin.addLine(to: CGPoint(x: mid + side * w * 0.5, y: h * 0.84))
                fin.addLine(to: CGPoint(x: mid + side * w * 0.44, y: h))
                fin.addLine(to: CGPoint(x: mid + side * w * 0.04, y: h * 0.9))
                fin.closeSubpath()
                context.fill(fin, with: .color(flights))
                context.fill(fin, with: .color(side < 0 ? .white.opacity(0.12) : .black.opacity(0.15)))
            }
            context.fill(bar(0.62, 1.0, width: w * 0.06), with: .color(flights))
            context.fill(bar(0.62, 1.0, width: w * 0.06), with: .color(.black.opacity(0.3)))

            context.fill(bar(0.52, 0.64, width: w * 0.07), with: .color(Color(white: 0.25)))
            context.fill(bar(0.19, 0.54, width: w * 0.13), with: .linearGradient(
                Gradient(colors: [Color(white: 0.32), Color(white: 0.12)]),
                startPoint: CGPoint(x: mid - w * 0.07, y: 0), endPoint: CGPoint(x: mid + w * 0.07, y: 0)
            ))
            for band in [0.27, 0.33, 0.39, 0.45] {
                context.fill(bar(band, band + 0.018, width: w * 0.13), with: .color(Color(white: 0.7)))
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1.5)
    }
}

/// A dart stuck where it landed. When it appears (the moment its flight arrives) it
/// thuds in with a short jolt and a quick, heavy settle, then rests at its lean.
struct StuckDart: View {
    let colour: Color
    let tilt: Double
    let animates: Bool
    @State private var kick = 0.0

    var body: some View {
        ThrowingDart(flights: colour)
            .background(alignment: .top) {
                // A little puncture shadow where the point went in.
                Ellipse().fill(Color.black.opacity(0.45))
                    .frame(width: 5, height: 2.5)
                    .offset(y: -1)
            }
            .scaleEffect(x: 1, y: 1 - abs(kick) * 0.02, anchor: .top)
            .rotationEffect(.degrees(tilt + kick), anchor: .top)
            .onAppear {
                guard animates else { return }
                withAnimation(.easeOut(duration: 0.05)) { kick = 5 } completion: {
                    withAnimation(.interpolatingSpring(stiffness: 420, damping: 11)) { kick = 0 }
                }
            }
    }
}

/// One dart in the air, from where it left the hand to where it sticks.
struct DartFlight: Identifiable {
    let id: Int
    let colour: Color
    let fromTip: CGPoint
    let fromSize: CGSize
    let toTip: CGPoint
    let toSize: CGSize
    let tilt: Double
    /// How far above the straight line the arc rises.
    let lift: CGFloat
    let delay: Double
}

struct FlyingDart: View {
    let flight: DartFlight
    let onArrival: () -> Void
    @State private var progress = 0.0

    var body: some View {
        ThrowingDart(flights: flight.colour)
            .modifier(FlightPath(flight: flight, progress: progress))
            .allowsHitTesting(false)
            .onAppear {
                // Quick off the hand, easing as it travels away into the board.
                withAnimation(.timingCurve(0.25, 0.55, 0.5, 1, duration: DartsTiming.flight).delay(flight.delay)) {
                    progress = 1
                } completion: {
                    onArrival()
                }
            }
    }
}

/// Places a flying dart along a shallow arc, shrinking with distance (perspective) and
/// turning to its final lean, so the last frame is exactly the stuck dart.
struct FlightPath: ViewModifier, Animatable {
    let flight: DartFlight
    var progress: Double

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = CGFloat(progress)
        func shrink(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from / (1 + (from / to - 1) * t) }
        let width = shrink(flight.fromSize.width, flight.toSize.width)
        let height = shrink(flight.fromSize.height, flight.toSize.height)
        let a = flight.fromTip, b = flight.toTip
        let control = CGPoint(x: (a.x + b.x) / 2, y: min(a.y, b.y) - flight.lift)
        let u = 1 - t
        let tip = CGPoint(
            x: u * u * a.x + 2 * u * t * control.x + t * t * b.x,
            y: u * u * a.y + 2 * u * t * control.y + t * t * b.y
        )
        return content
            .frame(width: width, height: height)
            .rotationEffect(.degrees(flight.tilt * progress), anchor: .top)
            .position(x: tip.x, y: tip.y + height / 2)
    }
}

// MARK: - Table furniture

/// Warm wood-grain wall behind the board, drawn procedurally (no image assets).
struct WoodWall: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [Color(red: 0.47, green: 0.25, blue: 0.13), Color(red: 0.37, green: 0.19, blue: 0.10)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
            ))
            // Grain: long wavy streaks, from a fixed seed so the wall never shimmers.
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(seed >> 11) / Double(UInt64(1) << 53)
            }
            let streaks = max(40, Int(size.width / 3))
            for _ in 0..<streaks {
                let x0 = next() * Double(size.width)
                let amplitude = 2 + next() * 6
                let wavelength = 120 + next() * 260
                let phase = next() * 6.28
                let width = 0.4 + next() * 2.2
                let dark = next() < 0.65
                let alpha = 0.05 + next() * 0.16
                var path = Path()
                var y = -10.0
                path.move(to: CGPoint(x: x0 + amplitude * sin(phase), y: y))
                while y < Double(size.height) + 10 {
                    y += 12
                    path.addLine(to: CGPoint(x: x0 + amplitude * sin(y / wavelength * 6.28 + phase), y: y))
                }
                let colour = dark ? Color(red: 0.17, green: 0.07, blue: 0.03) : Color(red: 0.75, green: 0.47, blue: 0.27)
                context.stroke(path, with: .color(colour.opacity(alpha)), lineWidth: width)
            }
            // Soft vignette.
            context.fill(Path(rect), with: .radialGradient(
                Gradient(colors: [.clear, .black.opacity(0.35)]),
                center: CGPoint(x: size.width / 2, y: size.height * 0.4),
                startRadius: min(size.width, size.height) * 0.3, endRadius: max(size.width, size.height) * 0.8
            ))
        }
        .accessibilityHidden(true)
    }
}

/// Score plaque: a green ticket with clipped corners and a three-digit score.
struct ScorePlaque: View {
    let value: Int
    let delay: Double

    var body: some View {
        CountingNumber(value: Double(value), digits: 3)
            .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background {
                TicketShape()
                    .fill(Color(red: 0.08, green: 0.42, blue: 0.24))
                    .overlay(TicketShape().inset(by: 3).stroke(Color.white.opacity(0.85), lineWidth: 2))
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            }
            // Count down as the dart hits the board, not when it leaves the hand.
            .animation(.easeOut(duration: 0.45).delay(delay), value: value)
    }
}

/// A rectangle with its corners scooped inwards, like a raffle ticket.
struct TicketShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let cut = min(r.width, r.height) * 0.22
        var path = Path()
        path.move(to: CGPoint(x: r.minX + cut, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - cut, y: r.minY))
        path.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + cut), control: CGPoint(x: r.maxX - cut, y: r.minY + cut))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cut))
        path.addQuadCurve(to: CGPoint(x: r.maxX - cut, y: r.maxY), control: CGPoint(x: r.maxX - cut, y: r.maxY - cut))
        path.addLine(to: CGPoint(x: r.minX + cut, y: r.maxY))
        path.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - cut), control: CGPoint(x: r.minX + cut, y: r.maxY - cut))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + cut))
        path.addQuadCurve(to: CGPoint(x: r.minX + cut, y: r.minY), control: CGPoint(x: r.minX + cut, y: r.minY + cut))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> TicketShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

/// A whole number that counts to its new value (101, 100, 99 … 41) instead of
/// morphing digit by digit, which can flash numbers that were never the score.
struct CountingNumber: View, Animatable {
    var value: Double
    var digits = 1

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        let text = String(max(0, Int(value.rounded())))
        Text(String(repeating: "0", count: max(0, digits - text.count)) + text)
    }
}

/// A player's round avatar, with an optional label above it.
struct PlayerBadge: View {
    let colour: Color
    let label: String?
    let isActive: Bool
    let glows: Bool

    var body: some View {
        VStack(spacing: 3) {
            if let label {
                Text(label)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
            }
            ZStack {
                Circle().fill(Color.black.opacity(0.85))
                Image(systemName: "person.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(colour)
                Circle().strokeBorder(isActive ? Color.white : Color.white.opacity(0.25), lineWidth: isActive ? 2.5 : 1)
            }
            .frame(width: 48, height: 48)
            .shadow(color: glows ? Color.yellow.opacity(0.95) : .black.opacity(0.4), radius: glows ? 14 : 3, y: glows ? 0 : 2)
        }
    }
}

/// The yellow tag that says how many points finish the game with one dart.
struct CheckoutTag: View {
    let points: Int

    var body: some View {
        HStack(spacing: 3) {
            Text("\(points)").font(.subheadline.weight(.black))
            Text("to win").font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color(white: 0.1))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color(red: 1.0, green: 0.86, blue: 0.1)))
        .overlay(alignment: .bottom) {
            Triangle().fill(Color(red: 1.0, green: 0.86, blue: 0.1))
                .frame(width: 10, height: 6)
                .offset(y: 5)
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A dart's points, popping up where it landed, then floating away.
struct PointsPop: View {
    let text: String
    let size: CGFloat
    let colour: Color
    @State private var shown = false
    @State private var leaving = false

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .black, design: .rounded))
            .foregroundStyle(colour)
            .shadow(color: .white, radius: 0, x: 1.5, y: 0)
            .shadow(color: .white, radius: 0, x: -1.5, y: 0)
            .shadow(color: .white, radius: 0, x: 0, y: 1.5)
            .shadow(color: .white, radius: 0, x: 0, y: -1.5)
            .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            .fixedSize()
            .scaleEffect(shown ? 1 : 0.3)
            .opacity(shown && !leaving ? 1 : 0)
            .offset(y: leaving ? -size * 0.9 : 0)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { shown = true }
                withAnimation(.easeIn(duration: 0.45).delay(0.75)) { leaving = true }
            }
    }
}

/// A banner across the lower half of the board.
public enum DartsBanner: Equatable, Sendable {
    /// Dark banner, white capitals: "WAITING FOR OPPONENT..."
    case info(String)
    /// Yellow banner, dark capitals: "YOU WON!"
    case celebration(String)
}

// MARK: - The table

/// The whole Darts screen, laid out like the classic iMessage darts game: a wood wall, a
/// big board at the top, the dart in hand below it, darts left top left, a menu top right,
/// and each player's avatar and score in the bottom corners. The player swipes the dart up
/// to throw: how hard sets how high it flies, the line of the flick sets left and right
/// (`DartsAim.flickTarget`). The landing point is committed the moment the dart leaves the
/// hand; the flight is only animation, and every dart (the bot's, and the other player's
/// visit replayed on opening) flies in rather than appearing.
public struct DartsTable<MenuItems: View, Footer: View>: View {
    let state: Darts.State
    let localSeat: Seat?
    let thrower: Seat?
    let canThrow: Bool
    let darts: [PlacedDart]
    let visit: Darts.VisitProgress?
    let livePreview: (seat: Seat, remaining: Int)?
    let dartsLeft: Int
    let banner: DartsBanner?
    let winner: Seat?
    let replaysDarts: Bool
    let notices: [String]
    let onThrow: (Darts.Hit) -> Void
    let menuItems: MenuItems
    let footer: Footer

    /// Finger movement while the dart is held; kept at release until the flight takes over.
    @State private var hold: CGSize = .zero
    @State private var holding = false
    /// Where the player's dart left the hand, until its landing shows up in `darts`.
    @State private var launchTip: CGPoint?
    @State private var flights: [Int: DartFlight] = [:]
    /// Darts that have arrived (or were already there), so are drawn stuck in the board.
    @State private var landed: Set<Int> = []
    /// Darts taken off the board when the next player's turn began.
    @State private var cleared: Set<Int> = []
    @State private var pops: [Pop] = []
    @State private var landings = 0
    @State private var dartInHand = true
    /// Points landed so far by darts replaying the last visit, for that player's plaque.
    @State private var replayedPoints: Int?
    @State private var showingRules = false
    @Environment(\.seatPalette) private var palette

    struct Pop: Identifiable {
        let id: Int
        let text: String
        let point: CGPoint
        let colour: Color
    }

    /// - Parameters:
    ///   - localSeat: whose device this is; nil for pass and play (both seats local).
    ///   - thrower: who is throwing now on this device: their dart is in hand.
    ///   - darts: darts on the board, in the order they were thrown.
    ///   - visit: how those darts scored, to mark a bust.
    ///   - livePreview: the thrower's score after the darts thrown so far this visit.
    ///   - winner: lights up that player's avatar.
    ///   - replaysDarts: fly the darts on the board in when the table appears (opening the
    ///     other player's visit).
    public init(
        state: Darts.State,
        localSeat: Seat?,
        thrower: Seat?,
        canThrow: Bool,
        darts: [PlacedDart],
        visit: Darts.VisitProgress?,
        livePreview: (seat: Seat, remaining: Int)?,
        dartsLeft: Int,
        banner: DartsBanner?,
        winner: Seat?,
        replaysDarts: Bool = false,
        notices: [String] = [],
        onThrow: @escaping (Darts.Hit) -> Void,
        @ViewBuilder menuItems: () -> MenuItems,
        @ViewBuilder footer: () -> Footer
    ) {
        self.state = state
        self.localSeat = localSeat
        self.thrower = thrower
        self.canThrow = canThrow
        self.darts = darts
        self.visit = visit
        self.livePreview = livePreview
        self.dartsLeft = dartsLeft
        self.banner = banner
        self.winner = winner
        self.replaysDarts = replaysDarts
        self.notices = notices
        self.onThrow = onThrow
        self.menuItems = menuItems()
        self.footer = footer()
    }

    private struct Layout {
        let size: CGSize
        let top: CGFloat = 50
        let bottom: CGFloat = 118

        var diameter: CGFloat { max(120, min(size.width - 14, (size.height - top - bottom) * 0.64)) }
        var mapping: BoardMapping {
            BoardMapping(
                centre: CGPoint(x: size.width / 2, y: top + diameter / 2),
                radius: diameter / 2,
                bounds: CGRect(x: 0, y: top * 0.4, width: size.width, height: size.height - bottom)
            )
        }
        var boardBottom: CGFloat { top + diameter }
        var handHeight: CGFloat { max(60, size.height - bottom - boardBottom) }
        var dartLength: CGFloat { min(size.width * 0.36, handHeight * 0.95) }
        var handSize: CGSize { CGSize(width: dartLength * 0.62, height: dartLength) }
        var restingTip: CGPoint {
            CGPoint(x: size.width / 2, y: boardBottom + max(6, (handHeight - dartLength) * 0.35))
        }
        /// Board widths, with the board's top-left corner at the origin.
        func unit(_ point: CGPoint) -> (x: Double, y: Double) {
            let originX = size.width / 2 - diameter / 2
            return (Double((point.x - originX) / diameter), Double((point.y - top) / diameter))
        }
    }

    public var body: some View {
        GeometryReader { proxy in
            let layout = Layout(size: proxy.size)
            let mapping = layout.mapping
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    DartboardPainter.draw(in: &context, mapping: mapping, highlight: checkout?.segment, castsShadow: true)
                }
                boardAccessibility
                    .frame(width: layout.diameter, height: layout.diameter)
                    .position(mapping.centre)

                ForEach(darts.filter { landed.contains($0.id) && !cleared.contains($0.id) }) { dart in
                    StuckDart(colour: palette.colour(dart.seat), tilt: mapping.tilt(for: dart.hit), animates: true)
                        .frame(width: mapping.stuckSize.width, height: mapping.stuckSize.height)
                        .position(x: mapping.point(for: dart.hit).x, y: mapping.point(for: dart.hit).y + mapping.stuckSize.height / 2)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
                ForEach(flights.values.sorted { $0.id < $1.id }) { flight in
                    FlyingDart(flight: flight) { arrive(flight.id, mapping: mapping) }
                        .accessibilityHidden(true)
                }
                ForEach(pops) { pop in
                    let size = layout.diameter * 0.13
                    // Kept on screen: a wide miss can land at the very edge.
                    let half = size * 0.36 * CGFloat(pop.text.count) + 8
                    PointsPop(text: pop.text, size: size, colour: pop.colour)
                        .position(
                            x: min(max(pop.point.x, half), max(half, layout.size.width - half)),
                            y: max(pop.point.y - layout.diameter * 0.06, size)
                        )
                        .accessibilityHidden(true)
                }

                // The dart in hand, resting still: always in the tree (only its opacity
                // changes) so nothing moves.
                ThrowingDart(flights: palette.colour(thrower ?? .one))
                    .frame(width: layout.handSize.width, height: layout.handSize.height)
                    // Leans along the swipe while held, so you can see where it will go.
                    .rotationEffect(.degrees(heldLean), anchor: .bottom)
                    .position(x: layout.restingTip.x + hold.width, y: layout.restingTip.y + hold.height + layout.handSize.height / 2)
                .opacity(showsHandDart ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                if let banner {
                    bannerView(banner, width: min(layout.size.width - 24, layout.diameter * 0.92))
                        .position(x: layout.size.width / 2, y: mapping.centre.y + layout.diameter * 0.3)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                topBar.frame(width: layout.size.width)
                bottomBar(layout: layout)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(throwGesture(layout: layout), including: canThrow ? .all : .subviews)
            .onAppear { start(layout: layout) }
            .onChange(of: darts) { old, new in
                launchFlights(from: old, to: new, layout: layout)
            }
        }
        .background {
            ZStack {
                WoodWall()
                Color(red: 1, green: 0.8, blue: 0.1)
                    .opacity(celebrates ? 0.3 : 0)
                    .blendMode(.screen)
            }
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.6), value: celebrates)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: banner)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: landings)
        .alert("How to play", isPresented: $showingRules) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Swipe the dart up at the board. Flick harder to throw higher; the line of your swipe aims left and right. Each turn is three darts. Count down from \(state.configuration.startingScore) and hit exactly zero to win. Going below zero is a bust and the turn scores nothing.")
        }
    }

    /// Degrees the held dart leans: the swipe's direction so far (sideways drift is held
    /// at `sideFollow`, so it is scaled back up), up to 20 either way.
    private var heldLean: Double {
        guard holding, hold.height < -8 else { return 0 }
        let degrees = atan2(Double(hold.width) / DartsAim.sideFollow, Double(-hold.height)) * 180 / .pi
        return min(max(degrees, -20), 20)
    }

    private var showsHandDart: Bool { canThrow && dartInHand && thrower != nil }
    private var celebrates: Bool { winner != nil && (localSeat == nil || winner == localSeat) }

    // MARK: Pieces

    private var topBar: some View {
        HStack(alignment: .top) {
            HStack(spacing: 2) {
                ForEach(0..<Darts.dartsPerVisit, id: \.self) { index in
                    ThrowingDart(flights: index < dartsLeft ? palette.colour(thrower ?? .one) : Color(white: 0.45))
                        .frame(width: 12, height: 24)
                        .opacity(index < dartsLeft ? 1 : 0.5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(dartsLeft) darts left")
            VStack(spacing: 6) {
                ForEach(notices, id: \.self) { notice in
                    Text(notice)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                }
            }
            .frame(maxWidth: .infinity)
            Menu {
                menuItems
                Button("How to play", systemImage: "questionmark.circle") { showingRules = true }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.75)))
            }
            .accessibilityLabel("Menu")
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private func bottomBar(layout: Layout) -> some View {
        let left = localSeat ?? .one
        // Each player pinned to a corner, whether or not there is a footer between them.
        return ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 0) {
                playerCorner(left)
                Spacer(minLength: 0)
                playerCorner(left.opponent)
            }
            footer
                .frame(maxWidth: max(0, layout.size.width - 2 * 108))
                .padding(.bottom, 6)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(width: layout.size.width, height: layout.size.height, alignment: .bottom)
    }

    private func playerCorner(_ seat: Seat) -> some View {
        let toAct = state.outcome.seatToAct == seat
        return VStack(spacing: 8) {
            if let checkout, checkout.seat == seat {
                CheckoutTag(points: checkout.points)
                    .transition(.scale.combined(with: .opacity))
            }
            PlayerBadge(colour: palette.colour(seat), label: label(for: seat), isActive: toAct, glows: winner == seat)
            ScorePlaque(value: plaqueValue(seat), delay: DartsTiming.flight + 0.25)
        }
        .frame(minWidth: 84)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: checkout?.points)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label(for: seat) ?? "Them"): \(plaqueValue(seat)) left\(toAct ? ", to throw" : "")")
    }

    private func label(for seat: Seat) -> String? {
        guard let localSeat else { return palette.name(seat) }
        return seat == localSeat ? "You" : nil
    }

    private func plaqueValue(_ seat: Seat) -> Int {
        if let replayedPoints, let last = state.lastVisit, last.seat == seat {
            return max(0, last.remainingBefore - replayedPoints)
        }
        if let livePreview, livePreview.seat == seat { return livePreview.remaining }
        return state.remaining(for: seat)
    }

    /// The thrower's one-dart finish, if there is one: the tag above their avatar and the
    /// segment lit on the board.
    private var checkout: (seat: Seat, points: Int, segment: DartsBoard.Segment)? {
        guard canThrow, let thrower else { return nil }
        let remaining = livePreview.flatMap { $0.seat == thrower ? $0.remaining : nil } ?? state.remaining(for: thrower)
        guard let segment = DartsCheckout.oneDartFinish(remaining) else { return nil }
        return (thrower, remaining, segment)
    }

    @ViewBuilder
    private func bannerView(_ banner: DartsBanner, width: CGFloat) -> some View {
        switch banner {
        case .info(let text):
            Text(text.uppercased())
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .frame(width: width)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.7)))
        case .celebration(let text):
            Text(text.uppercased())
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(Color(white: 0.08))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .frame(minWidth: width * 0.62)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(red: 1.0, green: 0.88, blue: 0.1)))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        }
    }

    // MARK: Throwing

    private func throwGesture(layout: Layout) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                // Only a swipe that starts low on the board or below it picks up the dart.
                guard showsHandDart, launchTip == nil, value.startLocation.y > layout.mapping.centre.y + layout.diameter * 0.3 else { return }
                holding = true
                // The dart rises with the finger but drifts sideways only part as far.
                hold = CGSize(width: value.translation.width * DartsAim.sideFollow, height: value.translation.height)
            }
            .onEnded { value in
                guard showsHandDart, launchTip == nil, holding else { return }
                holding = false
                let diameter = Double(layout.diameter)
                let target = DartsAim.flickTarget(
                    start: layout.unit(value.startLocation),
                    release: layout.unit(value.location),
                    velocity: (Double(value.velocity.width) / diameter, Double(value.velocity.height) / diameter),
                    dartX: 0.5
                )
                guard let target else {
                    withAnimation(.spring(duration: 0.3, bounce: 0.35)) { hold = .zero }
                    return
                }
                // Board widths to board units: the board's drawn edge is `drawnRadius` from the bull.
                let aim = Darts.Hit(x: Int(((target.x - 0.5) * 2 * drawnRadius).rounded()), y: Int(((0.5 - target.y) * 2 * drawnRadius).rounded()))
                let speed = Double((value.velocity.width * value.velocity.width + value.velocity.height * value.velocity.height).squareRoot()) / diameter
                var rng = SystemRandomNumberGenerator()
                let hit = DartsAim.landing(aim: aim, scatter: DartsAim.scatter(forSpeed: speed), using: &rng)
                launchTip = CGPoint(x: layout.restingTip.x + hold.width, y: layout.restingTip.y + hold.height)
                onThrow(hit)
                // If the throw was not taken (it should always be), put the dart back in hand.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    guard launchTip != nil else { return }
                    launchTip = nil
                    withAnimation(.spring(duration: 0.3, bounce: 0.35)) { hold = .zero }
                }
            }
    }

    /// Shows what is already on the board, or flies it in when replaying a visit.
    private func start(layout: Layout) {
        guard replaysDarts, !darts.isEmpty else {
            landed = Set(darts.map(\.id))
            clearOthersSoon(after: 0.6)
            return
        }
        landed = []
        replayedPoints = 0
        dartInHand = false
        for (index, dart) in darts.enumerated() {
            flights[dart.id] = flight(for: dart, from: layout.restingTip, layout: layout, delay: 0.5 + Double(index) * 0.75)
        }
    }

    /// Starts a flight for every dart that just appeared. The player's own dart leaves from
    /// where it was let go; anyone else's (the bot's) flies up from the hand position.
    private func launchFlights(from old: [PlacedDart], to new: [PlacedDart], layout: Layout) {
        let current = Set(new.map(\.id))
        landed.formIntersection(current)
        cleared.formIntersection(current)
        flights = flights.filter { current.contains($0.key) }
        if flights.isEmpty { replayedPoints = nil }
        let known = Set(old.map(\.id))
        for (index, dart) in new.filter({ !known.contains($0.id) }).enumerated() {
            let start = launchTip ?? layout.restingTip
            if launchTip != nil {
                // The flying dart takes over from the one in hand in the same frame.
                launchTip = nil
                dartInHand = false
                hold = .zero
            }
            flights[dart.id] = flight(for: dart, from: start, layout: layout, delay: Double(index) * 0.35)
        }
    }

    private func flight(for dart: PlacedDart, from start: CGPoint, layout: Layout, delay: Double) -> DartFlight {
        let mapping = layout.mapping
        return DartFlight(
            id: dart.id,
            colour: palette.colour(dart.seat),
            fromTip: start,
            fromSize: layout.handSize,
            toTip: mapping.point(for: dart.hit),
            toSize: mapping.stuckSize,
            tilt: mapping.tilt(for: dart.hit),
            lift: layout.diameter * 0.05,
            delay: delay
        )
    }

    private func arrive(_ id: Int, mapping: BoardMapping) {
        guard flights[id] != nil else { return }
        flights[id] = nil
        landed.insert(id)
        landings += 1
        if let index = darts.firstIndex(where: { $0.id == id }) {
            let segment = DartsBoard.segment(at: darts[index].hit)
            let busted = visit?.result == .bust && index == (visit?.darts.count ?? 0) - 1
            let text = busted ? "BUST" : segment == .miss ? "MISS" : "\(segment.points)"
            let pop = Pop(id: id, text: text, point: mapping.point(for: darts[index].hit), colour: busted ? DartboardColours.red : DartboardColours.green)
            if let points = replayedPoints, !busted { replayedPoints = points + segment.points }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.2))
                pops.append(pop)
                try? await Task.sleep(for: .seconds(1.4))
                pops.removeAll { $0.id == pop.id }
            }
        }
        if flights.isEmpty {
            replayedPoints = nil
            withAnimation(.easeOut(duration: 0.2).delay(0.12)) { dartInHand = true }
            clearOthersSoon(after: 1.1)
        }
    }

    /// When it is someone's turn to throw, the darts left by the other player come out of
    /// the board after a moment to read them, so each visit starts on a clean board.
    private func clearOthersSoon(after delay: Double) {
        guard canThrow, let thrower else { return }
        let others = Set(darts.filter { $0.seat != thrower && landed.contains($0.id) }.map(\.id))
        guard !others.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            // Not while a dart is in the air; its landing tries again.
            guard flights.isEmpty else { return }
            withAnimation(.easeOut(duration: 0.35)) { cleared.formUnion(others.intersection(landed)) }
        }
    }

    // MARK: Accessibility

    /// VoiceOver access to the board: what is on it, and throw actions on your turn.
    private var boardAccessibility: some View {
        Color.clear
            .accessibilityElement()
            .accessibilityLabel(darts.isEmpty ? "Dartboard" : "Dartboard. Darts: \(darts.map { DartsBoard.segment(at: $0.hit).spokenName }.joined(separator: ", ")).")
            .accessibilityHint(canThrow ? "Use the actions to throw a dart." : "")
            .accessibilityActions {
                if canThrow {
                    ForEach(accessibilityTargets, id: \.self) { target in
                        Button("Throw at \(target.spokenName)") { throwAt(target) }
                    }
                }
            }
    }

    private func throwAt(_ segment: DartsBoard.Segment) {
        var rng = SystemRandomNumberGenerator()
        // Without a flick to judge, VoiceOver throws use a slightly wider scatter.
        onThrow(DartsAim.landing(aim: DartsBoard.target(for: segment), scatter: DartsAim.releaseScatter * 2, using: &rng))
    }

    private var accessibilityTargets: [DartsBoard.Segment] {
        var targets: [DartsBoard.Segment] = []
        if let checkout { targets.append(checkout.segment) }
        for target in [DartsBoard.Segment(ring: .treble, number: 20), .init(ring: .treble, number: 19), .init(ring: .bull, number: 25), .init(ring: .single, number: 20)]
        where !targets.contains(target) {
            targets.append(target)
        }
        return targets
    }
}

/// One-dart finishes, for the "to win" tag.
public enum DartsCheckout {
    /// The segment that finishes from `remaining` with one dart, preferring the plainest.
    public static func oneDartFinish(_ remaining: Int) -> DartsBoard.Segment? {
        switch remaining {
        case 50: return DartsBoard.Segment(ring: .bull, number: 25)
        case 25: return DartsBoard.Segment(ring: .outerBull, number: 25)
        case 1...20: return DartsBoard.Segment(ring: .single, number: remaining)
        case 21...40 where remaining.isMultiple(of: 2): return DartsBoard.Segment(ring: .double, number: remaining / 2)
        case 21...60 where remaining.isMultiple(of: 3): return DartsBoard.Segment(ring: .treble, number: remaining / 3)
        default: return nil
        }
    }
}

/// Static art for a Darts message bubble: the board on the wall with the latest visit's
/// darts, and a trophy over it once the game is won.
public struct DartsBubbleArt: View {
    let state: Darts.State
    let palette: SeatPalette

    public init(state: Darts.State, palette: SeatPalette = SeatPalette()) {
        self.state = state
        self.palette = palette
    }

    public var body: some View {
        ZStack {
            WoodWall()
            DartsBoardView(darts: lastVisitDarts, animatesDarts: false)
                .frame(width: 196, height: 196)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 4)
            if state.outcome.winner != nil {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 78))
                    .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.1))
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
            }
        }
        .frame(width: 300, height: 225)
        .clipped()
        .environment(\.seatPalette, palette)
    }

    private var lastVisitDarts: [PlacedDart] {
        guard let visit = state.lastVisit else { return [] }
        return visit.darts.enumerated().map { PlacedDart(id: $0.offset, hit: $0.element.hit, seat: visit.seat) }
    }
}
#endif
