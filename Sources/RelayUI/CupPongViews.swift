#if canImport(UIKit)
import RelayCore
import RelayGames
import SwiftUI

// MARK: - Look

/// Colours for the pong table, cups and ball: the familiar party-game colours, our own drawing.
enum PongColours {
    static let roomTop = Color(red: 0.1, green: 0.12, blue: 0.2)
    static let roomBottom = Color(red: 0.03, green: 0.04, blue: 0.08)
    static let table = Color(red: 0.12, green: 0.36, blue: 0.68)
    static let tableFar = Color(red: 0.08, green: 0.26, blue: 0.52)
    static let tableEdge = Color(red: 0.05, green: 0.14, blue: 0.3)
    static let cup = Color(red: 0.88, green: 0.12, blue: 0.14)
    static let cupShade = Color(red: 0.55, green: 0.04, blue: 0.07)
    static let cupInside = Color(red: 0.42, green: 0.03, blue: 0.05)
    static let liquid = Color(red: 0.93, green: 0.7, blue: 0.22)
    static let ball = Color(white: 0.98)
}

/// Table millimetres (x across, y away from the thrower, z up) to view points. The camera
/// sits above and behind the thrower's end looking down the table, like the classic
/// iMessage pong game: the far end and its cups fill the middle of the screen and the
/// near end runs off the bottom.
struct PongProjection {
    static let cameraY = -400.0
    static let cameraHeight = 900.0
    /// Where a ball waits to be thrown.
    static let restY = 1_150.0
    static let restZ = 60.0

    let k: CGFloat
    let horizon: CGFloat
    let centreX: CGFloat

    init(size: CGSize) {
        let farA = 1 / (Double(CupPong.Table.length) - Self.cameraY)
        // As large as fits: the far end of the table must stay inside the width.
        k = min(size.height * 2.8, size.width * 0.47 / (Double(CupPong.Table.halfWidth) * farA))
        // The far edge of the table sits a fifth of the way down.
        horizon = size.height * 0.2 - k * Self.cameraHeight * farA
        centreX = size.width / 2
    }

    func point(x: Double, y: Double, z: Double) -> CGPoint {
        let a = 1 / max(1, y - Self.cameraY)
        return CGPoint(x: centreX + k * x * a, y: horizon + k * (Self.cameraHeight - z) * a)
    }

    /// Points per millimetre at distance `y`.
    func scale(at y: Double) -> CGFloat { k / max(1, y - Self.cameraY) }

    var restPoint: CGPoint { point(x: 0, y: Self.restY, z: Self.restZ) }
}

enum PongPainter {
    static func drawTable(in context: inout GraphicsContext, projection p: PongProjection) {
        let half = Double(CupPong.Table.halfWidth), far = Double(CupPong.Table.length), near = 700.0
        func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            path.addLine(to: c)
            path.addLine(to: d)
            path.closeSubpath()
            return path
        }
        // The front of the far end, then the top.
        let farLeft = p.point(x: -half, y: far, z: 0), farRight = p.point(x: half, y: far, z: 0)
        let thickness = 45 * p.scale(at: far)
        context.fill(quad(farLeft, farRight, CGPoint(x: farRight.x, y: farRight.y + thickness), CGPoint(x: farLeft.x, y: farLeft.y + thickness)), with: .color(PongColours.tableEdge))
        let top = quad(p.point(x: -half, y: near, z: 0), p.point(x: half, y: near, z: 0), farRight, farLeft)
        context.fill(top, with: .linearGradient(
            Gradient(colors: [PongColours.tableFar, PongColours.table]),
            startPoint: farLeft, endPoint: p.point(x: 0, y: 1_300, z: 0)
        ))
        // White border and centre line.
        let inset = 22.0
        var lines = Path()
        lines.move(to: p.point(x: -half + inset, y: near, z: 0))
        lines.addLine(to: p.point(x: -half + inset, y: far - inset, z: 0))
        lines.addLine(to: p.point(x: half - inset, y: far - inset, z: 0))
        lines.addLine(to: p.point(x: half - inset, y: near, z: 0))
        context.stroke(lines, with: .color(.white.opacity(0.85)), lineWidth: max(1.5, 14 * p.scale(at: far)))
        var centre = Path()
        centre.move(to: p.point(x: 0, y: near, z: 0))
        centre.addLine(to: p.point(x: 0, y: far - inset, z: 0))
        context.stroke(centre, with: .color(.white.opacity(0.35)), lineWidth: max(1, 6 * p.scale(at: far)))
    }

    /// A cup at (x, y): a tapered red body, a white rim, and drink inside.
    static func drawCup(in context: inout GraphicsContext, projection p: PongProjection, x: Double, y: Double, opacity: Double = 1) {
        let r = Double(CupPong.Table.cupRadius), h = Double(CupPong.Table.cupHeight)
        let s = p.scale(at: y)
        let top = p.point(x: x, y: y, z: h), bottom = p.point(x: x, y: y, z: 0)
        let rx = r * s
        let ry = (p.point(x: x, y: y - r, z: h).y - p.point(x: x, y: y + r, z: h).y) / 2
        let bottomRx = rx * 0.68
        let bottomRy = (p.point(x: x, y: y - r * 0.68, z: 0).y - p.point(x: x, y: y + r * 0.68, z: 0).y) / 2
        var cup = context
        cup.opacity = opacity
        // Shadow on the table.
        cup.fill(Path(ellipseIn: CGRect(x: bottom.x - bottomRx * 1.25, y: bottom.y - bottomRy * 0.9, width: bottomRx * 2.5, height: bottomRy * 2.4)), with: .color(.black.opacity(0.28)))
        var body = Path()
        body.move(to: CGPoint(x: top.x - rx, y: top.y))
        body.addLine(to: CGPoint(x: bottom.x - bottomRx, y: bottom.y))
        body.addArc(center: bottom, radius: 1, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        body.addLine(to: CGPoint(x: bottom.x + bottomRx, y: bottom.y))
        body.addLine(to: CGPoint(x: top.x + rx, y: top.y))
        body.closeSubpath()
        cup.fill(Path(ellipseIn: CGRect(x: bottom.x - bottomRx, y: bottom.y - bottomRy, width: bottomRx * 2, height: bottomRy * 2)), with: .color(PongColours.cupShade))
        cup.fill(body, with: .linearGradient(
            Gradient(stops: [
                .init(color: PongColours.cupShade, location: 0),
                .init(color: PongColours.cup, location: 0.35),
                .init(color: Color(red: 1, green: 0.42, blue: 0.4), location: 0.5),
                .init(color: PongColours.cup, location: 0.62),
                .init(color: PongColours.cupShade, location: 1),
            ]),
            startPoint: CGPoint(x: top.x - rx, y: top.y), endPoint: CGPoint(x: top.x + rx, y: top.y)
        ))
        // Ridges round the cup.
        for f in [0.25, 0.32] {
            let yy = top.y + (bottom.y - top.y) * f
            let half = rx + (bottomRx - rx) * f
            var ridge = Path()
            ridge.move(to: CGPoint(x: top.x - half, y: yy))
            ridge.addQuadCurve(to: CGPoint(x: top.x + half, y: yy), control: CGPoint(x: top.x, y: yy + ry * 0.9))
            cup.stroke(ridge, with: .color(.black.opacity(0.18)), lineWidth: 0.8)
        }
        // Rim and the drink inside.
        let rim = CGRect(x: top.x - rx, y: top.y - ry, width: rx * 2, height: ry * 2)
        cup.fill(Path(ellipseIn: rim), with: .color(Color(white: 0.96)))
        let inner = rim.insetBy(dx: rx * 0.1, dy: ry * 0.14)
        cup.fill(Path(ellipseIn: inner), with: .color(PongColours.cupInside))
        let drink = CGRect(x: inner.minX + inner.width * 0.06, y: inner.minY + inner.height * 0.28, width: inner.width * 0.88, height: inner.height * 0.72)
        cup.fill(Path(ellipseIn: drink), with: .color(PongColours.liquid.opacity(0.85)))
    }

    static func drawBall(in context: inout GraphicsContext, projection p: PongProjection, x: Double, y: Double, z: Double, opacity: Double = 1, shadow: Bool = true) {
        let radius = Double(CupPong.Table.ballRadius) * p.scale(at: y)
        var ball = context
        ball.opacity = opacity
        if shadow, z >= -5, abs(x) <= Double(CupPong.Table.halfWidth), y <= Double(CupPong.Table.length) {
            let ground = p.point(x: x, y: y, z: 0)
            let fade = max(0.08, 0.35 - z / 2_000)
            ball.fill(Path(ellipseIn: CGRect(x: ground.x - radius, y: ground.y - radius * 0.35, width: radius * 2, height: radius * 0.7)), with: .color(.black.opacity(fade)))
        }
        drawBall(in: &ball, at: p.point(x: x, y: y, z: z), radius: radius)
    }

    static func drawBall(in context: inout GraphicsContext, at c: CGPoint, radius r: CGFloat) {
        let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        context.fill(disc, with: .radialGradient(
            Gradient(colors: [.white, PongColours.ball, Color(white: 0.72)]),
            center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.4
        ))
    }
}

// MARK: - Balls to show

/// A ball on the record: where it came down, what it did, and the cups it was thrown at.
public struct PongBall: Identifiable, Equatable, Sendable {
    public let id: Int
    public let landing: CupPong.Landing
    public let result: CupPong.BallResult
    public let cupsBefore: [CupPong.Cup]

    public init(id: Int, landing: CupPong.Landing, result: CupPong.BallResult, cupsBefore: [CupPong.Cup]) {
        self.id = id
        self.landing = landing
        self.result = result
        self.cupsBefore = cupsBefore
    }

    /// Every ball of a turn, numbered from `firstID`.
    public static func turn(_ balls: [CupPong.ThrowResult], firstID: Int) -> [PongBall] {
        balls.enumerated().map { PongBall(id: firstID + $0.offset, landing: $0.element.landing, result: $0.element.result, cupsBefore: $0.element.cupsBefore) }
    }
}

/// A ball in the air (and just after it comes down), for the table's animation.
struct PongFlight: Equatable {
    let ball: PongBall
    let from: (x: Double, y: Double, z: Double)
    let start: Date
    /// Seconds in the air, then seconds dropping into a cup or bouncing away.
    static let air = 0.75
    static let after = 0.55
    static func == (a: PongFlight, b: PongFlight) -> Bool { a.ball.id == b.ball.id && a.start == b.start }
}

// MARK: - The table

/// The whole Cup Pong screen, laid out like the classic iMessage pong game: players along
/// the top, the table running away from you with the other side's cups at the far end,
/// and the ball resting at the bottom. Swipe the ball up to throw: how fast sets how far
/// it flies, the line of the swipe sets left and right (`CupPongAim`). Where it comes
/// down is committed the moment it leaves the hand; the flight is only animation, and the
/// other player's balls are replayed on opening.
public struct CupPongTable<MenuItems: View, Footer: View>: View {
    let state: CupPong.State
    /// The cups being thrown at now.
    let cups: [CupPong.Cup]
    let localSeat: Seat?
    let thrower: Seat?
    let canThrow: Bool
    let balls: [PongBall]
    let replaysBalls: Bool
    let nextBallID: Int
    let ballsLeft: Int
    let status: String?
    let banner: DartsBanner?
    let winner: Seat?
    let notices: [String]
    let onThrow: (CupPong.Landing) -> Void
    let menuItems: MenuItems
    let footer: Footer

    @State private var hold: CGSize = .zero
    @State private var holding = false
    @State private var holdStart: Date?
    @State private var flight: PongFlight?
    @State private var queue: [PongBall]
    @State private var seen: Set<Int>
    @State private var replaying: Bool
    @State private var showingRules = false
    @State private var sinks = 0
    @State private var bounces = 0
    @Environment(\.seatPalette) private var palette

    public init(
        state: CupPong.State,
        cups: [CupPong.Cup],
        localSeat: Seat?,
        thrower: Seat?,
        canThrow: Bool,
        balls: [PongBall],
        replaysBalls: Bool = false,
        nextBallID: Int,
        ballsLeft: Int,
        status: String?,
        banner: DartsBanner?,
        winner: Seat?,
        notices: [String] = [],
        onThrow: @escaping (CupPong.Landing) -> Void,
        @ViewBuilder menuItems: () -> MenuItems,
        @ViewBuilder footer: () -> Footer
    ) {
        self.state = state
        self.cups = cups
        self.localSeat = localSeat
        self.thrower = thrower
        self.canThrow = canThrow
        self.balls = balls
        self.replaysBalls = replaysBalls
        self.nextBallID = nextBallID
        self.ballsLeft = ballsLeft
        self.status = status
        self.banner = banner
        self.winner = winner
        self.notices = notices
        self.onThrow = onThrow
        self.menuItems = menuItems()
        self.footer = footer()
        // Queue a replay before the first frame, so the finished table never flashes first.
        _queue = State(initialValue: replaysBalls ? balls : [])
        _seen = State(initialValue: Set(balls.map(\.id)))
        _replaying = State(initialValue: replaysBalls && !balls.isEmpty)
    }

    private var isIdle: Bool { flight == nil && queue.isEmpty }
    private var showsBallInHand: Bool { canThrow && isIdle && ballsLeft > 0 }

    public var body: some View {
        VStack(spacing: 8) {
            players
                .padding(.horizontal, 12)
            // The chip's room is always kept, so the table never jumps.
            Text(chipText ?? " ")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .opacity(chipText == nil ? 0 : 1)
            ForEach(notices, id: \.self) { notice in
                Text(notice)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
            }
            tableArea
            footer
            bottomBar
                .padding(.horizontal, 12)
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [PongColours.roomTop, PongColours.roomBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: banner)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: sinks)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: bounces)
        .onAppear { if flight == nil, !queue.isEmpty { playNext() } }
        .onChange(of: balls) { _, new in enqueue(new) }
        .alert("How to play", isPresented: $showingRules) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Swipe the ball up towards the cups. A faster swipe throws further; the angle of your swipe aims left or right. Sink a cup to take it away. Sink both balls in a turn to get them back. Clear all their cups to win.")
        }
    }

    private var chipText: String? {
        if replaying { return "Their throws" }
        guard isIdle else { return nil }
        return status
    }

    // MARK: Players

    private var players: some View {
        let left = localSeat ?? .one
        return HStack(alignment: .center) {
            playerSide(left, alignment: .leading)
            Spacer(minLength: 8)
            Menu {
                menuItems
                Button("How to play", systemImage: "questionmark.circle") { showingRules = true }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .accessibilityLabel("Menu")
            Spacer(minLength: 8)
            playerSide(left.opponent, alignment: .trailing)
        }
    }

    private func playerSide(_ seat: Seat, alignment: HorizontalAlignment) -> some View {
        let toAct = state.outcome.seatToAct == seat
        let badge = PlayerBadge(colour: palette.colour(seat), label: label(for: seat), isActive: toAct, glows: winner == seat)
            .scaleEffect(0.82)
        let left = state.cupsLeft(for: seat)
        let count = VStack(spacing: 1) {
            Text("\(left)")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(left == 1 ? "CUP" : "CUPS")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        return HStack(spacing: 8) {
            if alignment == .leading {
                badge
                count
            } else {
                count
                badge
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label(for: seat) ?? "Them"), \(left) cups left\(toAct ? ", to throw" : "")")
    }

    private func label(for seat: Seat) -> String? {
        guard let localSeat else { return palette.name(seat) }
        return seat == localSeat ? "You" : nil
    }

    // MARK: Table

    private var tableArea: some View {
        GeometryReader { proxy in
            let projection = PongProjection(size: proxy.size)
            TimelineView(.animation(minimumInterval: 1 / 60, paused: flight == nil)) { timeline in
                Canvas { context, _ in
                    draw(in: &context, projection: projection, at: timeline.date)
                }
            }
            .overlay {
                if let banner, isIdle {
                    GameBannerView(banner: banner)
                        .padding(.horizontal, 12)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .gesture(throwGesture(size: proxy.size, projection: projection), including: showsBallInHand ? .all : .subviews)
            .accessibilityElement()
            .accessibilityLabel("Pong table, \(cups.count) cups to aim at")
            .accessibilityHint(showsBallInHand ? "Swipe up to throw, or use the actions to throw at a cup." : "")
            .accessibilityActions {
                if showsBallInHand {
                    ForEach(Array(cups.enumerated()), id: \.element.id) { index, cup in
                        Button("Throw at cup \(index + 1)") { throwAt(cup, projection: projection) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func draw(in context: inout GraphicsContext, projection p: PongProjection, at date: Date) {
        PongPainter.drawTable(in: &context, projection: p)
        let standing: [CupPong.Cup]
        var ballPosition: (x: Double, y: Double, z: Double, opacity: Double, inCup: CupPong.Cup?)?
        var fadingCup: (cup: CupPong.Cup, opacity: Double)?
        if let flight {
            standing = flight.ball.cupsBefore
            let t = date.timeIntervalSince(flight.start)
            let position = Self.position(of: flight, at: t)
            ballPosition = position
            if case .sunk(let id) = flight.ball.result, t > PongFlight.air, let cup = standing.first(where: { $0.id == id }) {
                fadingCup = (cup, max(0, 1 - (t - PongFlight.air) / PongFlight.after))
            }
        } else if let next = queue.first {
            standing = next.cupsBefore
        } else {
            standing = cups
        }
        // Far cups first, so nearer ones overlap them.
        var ballDrawn = false
        for cup in standing.sorted(by: { $0.y > $1.y }) {
            let opacity = fadingCup?.cup.id == cup.id ? fadingCup!.opacity : 1
            // A ball behind this cup is drawn before it.
            if let ball = ballPosition, ball.inCup == nil, ball.y > Double(cup.y) + 60, !ballDrawn {
                PongPainter.drawBall(in: &context, projection: p, x: ball.x, y: ball.y, z: ball.z, opacity: ball.opacity)
                ballDrawn = true
            }
            PongPainter.drawCup(in: &context, projection: p, x: Double(cup.x), y: Double(cup.y), opacity: opacity)
            if let ball = ballPosition, let inside = ball.inCup, inside.id == cup.id {
                // Dropping into the drink: only the part inside the rim shows.
                var clipped = context
                let s = p.scale(at: Double(cup.y))
                let top = p.point(x: Double(cup.x), y: Double(cup.y), z: Double(CupPong.Table.cupHeight))
                let rx = Double(CupPong.Table.cupRadius) * s * 0.9
                clipped.clip(to: Path(ellipseIn: CGRect(x: top.x - rx, y: top.y - rx * 0.6, width: rx * 2, height: rx * 1.2)))
                PongPainter.drawBall(in: &clipped, projection: p, x: ball.x, y: ball.y, z: ball.z, opacity: ball.opacity * opacity, shadow: false)
            }
        }
        if let ball = ballPosition, ball.inCup == nil, !ballDrawn {
            PongPainter.drawBall(in: &context, projection: p, x: ball.x, y: ball.y, z: ball.z, opacity: ball.opacity)
        }
        if showsBallInHand {
            let rest = p.restPoint
            let radius = Double(CupPong.Table.ballRadius) * p.scale(at: PongProjection.restY) * (holding ? 1.08 : 1)
            let centre = CGPoint(x: rest.x + hold.width, y: rest.y + hold.height)
            context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y + radius * 0.9, width: radius * 2, height: radius * 0.6)), with: .color(.black.opacity(0.3)))
            PongPainter.drawBall(in: &context, at: centre, radius: radius)
            // Balls still to come this turn, beside the one in hand.
            for index in 1..<max(1, ballsLeft) {
                let spare = CGPoint(x: rest.x - radius * 3.2 * CGFloat(index), y: rest.y + radius * 0.4)
                PongPainter.drawBall(in: &context, at: spare, radius: radius * 0.7)
            }
        }
    }

    /// Where the ball is `t` seconds into its flight, and how it shows.
    static func position(of flight: PongFlight, at t: Double) -> (x: Double, y: Double, z: Double, opacity: Double, inCup: CupPong.Cup?) {
        let ball = flight.ball
        let lx = Double(ball.landing.x), ly = Double(ball.landing.y)
        let rimTop = Double(CupPong.Table.cupHeight + CupPong.Table.ballRadius)
        let ballRadius = Double(CupPong.Table.ballRadius)
        let landingZ: Double
        switch ball.result {
        case .sunk, .rim: landingZ = rimTop
        case .table, .missed: landingZ = ballRadius
        }
        if t <= PongFlight.air {
            let f = max(0, t / PongFlight.air)
            let x = flight.from.x + (lx - flight.from.x) * f
            let y = flight.from.y + (ly - flight.from.y) * f
            let z = flight.from.z + (landingZ - flight.from.z) * f + 520 * 4 * f * (1 - f)
            return (x, y, z, 1, nil)
        }
        let q = min(1, (t - PongFlight.air) / PongFlight.after)
        switch ball.result {
        case .sunk(let id):
            let cup = ball.cupsBefore.first { $0.id == id }
            let cx = Double(cup?.x ?? ball.landing.x), cy = Double(cup?.y ?? ball.landing.y)
            return (lx + (cx - lx) * q, ly + (cy - ly) * q, rimTop - 70 * q, 1, cup)
        case .rim(let id):
            let cup = ball.cupsBefore.first { $0.id == id }
            var dx = lx - Double(cup?.x ?? 0), dy = ly - Double(cup?.y ?? 0)
            let length = max(1, (dx * dx + dy * dy).squareRoot())
            dx /= length
            dy /= length
            return (lx + dx * 260 * q, ly + dy * 160 * q + 120 * q, rimTop + 140 * 4 * q * (1 - q) - (rimTop - ballRadius) * q, 1 - q * q, nil)
        case .table:
            return (lx, ly + 520 * q, ballRadius + 160 * 4 * q * (1 - q), 1 - q * q, nil)
        case .missed:
            return (lx, ly + 400 * q, ballRadius - 500 * q, 1 - q, nil)
        }
    }

    // MARK: Throwing

    private func throwGesture(size: CGSize, projection: PongProjection) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard showsBallInHand else { return }
                // Only a swipe that starts in the lower part of the table picks up the ball.
                guard holding || value.startLocation.y > projection.restPoint.y - size.height * 0.25 else { return }
                holding = true
                if holdStart == nil { holdStart = value.time }
                hold = CGSize(width: value.translation.width * 0.6, height: min(0, value.translation.height) * 0.5)
            }
            .onEnded { value in
                guard showsBallInHand, holding else { return }
                holding = false
                let width = Double(size.width)
                let duration = max(0.03, value.time.timeIntervalSince(holdStart ?? value.time))
                holdStart = nil
                let averageRise = Double(value.startLocation.y - value.location.y) / width / duration
                let releaseRise = -Double(value.velocity.height) / width
                let landing = CupPongAim.flickLanding(
                    start: (Double(value.startLocation.x) / width, Double(value.startLocation.y) / width),
                    release: (Double(value.location.x) / width, Double(value.location.y) / width),
                    velocity: (Double(value.velocity.width) / width, -max(releaseRise, averageRise))
                )
                guard let landing else {
                    withAnimation(.spring(duration: 0.3, bounce: 0.35)) { hold = .zero }
                    return
                }
                let s = projection.scale(at: PongProjection.restY)
                launch(landing, from: (Double(hold.width / s), PongProjection.restY, PongProjection.restZ - Double(hold.height / s)))
            }
    }

    /// VoiceOver throws at a cup with an average arm, not a perfect one.
    private func throwAt(_ cup: CupPong.Cup, projection: PongProjection) {
        var rng = SystemRandomNumberGenerator()
        let landing = CupPongBot(difficulty: .standard).nextLanding(at: [cup], using: &rng)
        launch(landing, from: (0, PongProjection.restY, PongProjection.restZ))
    }

    private func launch(_ landing: CupPong.Landing, from: (x: Double, y: Double, z: Double)) {
        guard showsBallInHand else { return }
        let ball = PongBall(id: nextBallID, landing: landing, result: CupPong.result(of: landing, against: cups), cupsBefore: cups)
        seen.insert(ball.id)
        hold = .zero
        fly(ball, from: from)
        onThrow(landing)
    }

    private func enqueue(_ all: [PongBall]) {
        let fresh = all.filter { !seen.contains($0.id) }
        guard !fresh.isEmpty else { return }
        seen.formUnion(fresh.map(\.id))
        let wasEmpty = queue.isEmpty
        queue.append(contentsOf: fresh)
        if flight == nil, wasEmpty { playNext() }
    }

    private func playNext() {
        guard let next = queue.first else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard flight == nil, queue.first?.id == next.id else { return }
            queue.removeFirst()
            fly(next, from: (0, PongProjection.restY, PongProjection.restZ))
        }
    }

    private func fly(_ ball: PongBall, from: (x: Double, y: Double, z: Double)) {
        let current = PongFlight(ball: ball, from: from, start: Date())
        flight = current
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(PongFlight.air))
            guard flight == current else { return }
            if ball.result.isSink { sinks += 1 } else { bounces += 1 }
            try? await Task.sleep(for: .seconds(PongFlight.after + 0.1))
            guard flight == current else { return }
            flight = nil
            if queue.isEmpty {
                replaying = false
            } else {
                playNext()
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button { showingRules = true } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .accessibilityLabel("How to play")
            Spacer()
        }
    }
}

// MARK: - Bubble

/// The message bubble picture: the cups the next player throws at, with the classic strip.
public struct CupPongBubbleArt: View {
    let state: CupPong.State

    public init(state: CupPong.State) {
        self.state = state
    }

    private var shownCups: [CupPong.Cup] {
        if let seat = state.outcome.seatToAct { return state.targets(for: seat) }
        return state.lastTurn?.endCups ?? []
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [PongColours.roomTop, PongColours.roomBottom], startPoint: .top, endPoint: .bottom)
                Canvas { context, size in
                    // Closer in than the play screen, so the cups fill the picture.
                    let p = PongProjection(size: CGSize(width: size.width, height: size.height * 2.1))
                    var shifted = context
                    shifted.translateBy(x: 0, y: -size.height * 0.12)
                    PongPainter.drawTable(in: &shifted, projection: p)
                    for cup in shownCups.sorted(by: { $0.y > $1.y }) {
                        PongPainter.drawCup(in: &shifted, projection: p, x: Double(cup.x), y: Double(cup.y))
                    }
                }
                if state.outcome.winner != nil {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.1))
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
                }
            }
            BubbleStrip(text: state.outcome.isFinished ? "Game over" : state.turns.isEmpty ? "Let's play Cup Pong!" : "Your turn")
        }
        .frame(width: 300, height: 225)
        .clipped()
    }
}
#endif
