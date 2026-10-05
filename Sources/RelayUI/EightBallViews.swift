#if canImport(UIKit)
import RelayCore
import RelayGames
import SwiftUI

// MARK: - Look

/// Colours for the pool table and balls: the sport's standard colours, our own drawing.
enum PoolColours {
    static let felt = Color(red: 0.11, green: 0.47, blue: 0.27)
    static let feltShade = Color(red: 0.07, green: 0.36, blue: 0.2)
    static let cushion = Color(red: 0.08, green: 0.4, blue: 0.22)
    static let rail = Color(red: 0.42, green: 0.24, blue: 0.12)
    static let railDark = Color(red: 0.27, green: 0.14, blue: 0.07)
    static let sight = Color(red: 0.95, green: 0.88, blue: 0.7)
    static let backdrop = Color(red: 0.08, green: 0.1, blue: 0.14)

    static func ball(_ number: Int) -> Color {
        switch number % 8 {
        case 1: Color(red: 0.98, green: 0.78, blue: 0.1)
        case 2: Color(red: 0.12, green: 0.3, blue: 0.85)
        case 3: Color(red: 0.88, green: 0.13, blue: 0.13)
        case 4: Color(red: 0.45, green: 0.2, blue: 0.68)
        case 5: Color(red: 0.98, green: 0.47, blue: 0.08)
        case 6: Color(red: 0.08, green: 0.55, blue: 0.27)
        case 7: Color(red: 0.55, green: 0.1, blue: 0.12)
        default: Color(white: 0.06)
        }
    }
}

/// Table millimetres to view points.
struct PoolMapping {
    /// Rail width around the cloth, in millimetres.
    static let rail = 80.0
    static let aspect = (PoolTable.width + rail * 2) / (PoolTable.length + rail * 2)

    /// Top-left of the cloth's playing area in the view.
    let origin: CGPoint
    let scale: CGFloat

    /// The largest table that fits `size`, centred.
    init(fitting size: CGSize) {
        let outerWidth = PoolTable.width + Self.rail * 2
        let outerLength = PoolTable.length + Self.rail * 2
        scale = min(size.width / outerWidth, size.height / outerLength)
        let left = (size.width - outerWidth * scale) / 2
        let top = (size.height - outerLength * scale) / 2
        origin = CGPoint(x: left + Self.rail * scale, y: top + Self.rail * scale)
    }

    func point(_ v: PoolTable.Vector) -> CGPoint {
        CGPoint(x: origin.x + v.x * scale, y: origin.y + v.y * scale)
    }

    func vector(_ p: CGPoint) -> PoolTable.Vector {
        PoolTable.Vector(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale)
    }

    func length(_ millimetres: Double) -> CGFloat { millimetres * scale }

    var ballRadius: CGFloat { length(PoolTable.ballRadius) }

    var cloth: CGRect {
        CGRect(x: origin.x, y: origin.y, width: length(PoolTable.width), height: length(PoolTable.length))
    }

    var outer: CGRect { cloth.insetBy(dx: -length(Self.rail), dy: -length(Self.rail)) }
}

enum PoolPainter {
    /// Rails, cloth, sights and pockets. The head string is marked while placing for the break.
    static func drawTable(in context: inout GraphicsContext, mapping: PoolMapping, showsHeadString: Bool) {
        let outer = mapping.outer
        let railRadius = mapping.length(60)
        context.fill(Path(roundedRect: outer.offsetBy(dx: 0, dy: 3), cornerRadius: railRadius), with: .color(.black.opacity(0.45)))
        context.fill(Path(roundedRect: outer, cornerRadius: railRadius), with: .linearGradient(
            Gradient(colors: [PoolColours.rail, PoolColours.railDark]),
            startPoint: CGPoint(x: outer.minX, y: outer.minY), endPoint: CGPoint(x: outer.maxX, y: outer.maxY)
        ))
        context.stroke(Path(roundedRect: outer.insetBy(dx: 1, dy: 1), cornerRadius: railRadius), with: .color(.white.opacity(0.12)), lineWidth: 1)

        // Cloth, with the cushions a darker strip just inside it.
        let cushionWidth = mapping.length(26)
        let clothWithCushions = mapping.cloth.insetBy(dx: -cushionWidth, dy: -cushionWidth)
        context.fill(Path(clothWithCushions), with: .color(PoolColours.cushion))
        context.fill(Path(mapping.cloth), with: .radialGradient(
            Gradient(colors: [PoolColours.felt, PoolColours.feltShade]),
            center: CGPoint(x: mapping.cloth.midX, y: mapping.cloth.midY),
            startRadius: 0, endRadius: mapping.cloth.height * 0.7
        ))

        // Sights on the rails.
        let sightRadius = max(1.2, mapping.length(9))
        for i in 1..<4 {
            let x = PoolTable.width * Double(i) / 4
            for y in [-PoolMapping.rail / 2 - 13, PoolTable.length + PoolMapping.rail / 2 + 13] {
                let p = mapping.point(PoolTable.Vector(x: x, y: y))
                context.fill(Path(ellipseIn: CGRect(x: p.x - sightRadius, y: p.y - sightRadius, width: sightRadius * 2, height: sightRadius * 2)), with: .color(PoolColours.sight))
            }
        }
        for i in [1, 2, 3, 5, 6, 7] {
            let y = PoolTable.length * Double(i) / 8
            for x in [-PoolMapping.rail / 2 - 13, PoolTable.width + PoolMapping.rail / 2 + 13] {
                let p = mapping.point(PoolTable.Vector(x: x, y: y))
                context.fill(Path(ellipseIn: CGRect(x: p.x - sightRadius, y: p.y - sightRadius, width: sightRadius * 2, height: sightRadius * 2)), with: .color(PoolColours.sight))
            }
        }

        // Pockets.
        for (index, pocket) in PoolTable.pockets.enumerated() {
            let r = mapping.length(index < 4 ? 62 : 54)
            let centre = mapping.point(PocketArt.drawnCentre(pocket, index: index))
            context.fill(Path(ellipseIn: CGRect(x: centre.x - r - 1.5, y: centre.y - r - 1.5, width: (r + 1.5) * 2, height: (r + 1.5) * 2)), with: .color(PoolColours.railDark))
            context.fill(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)), with: .radialGradient(
                Gradient(colors: [.black, Color(white: 0.12)]),
                center: centre, startRadius: 0, endRadius: r
            ))
        }

        if showsHeadString {
            let y = mapping.point(PoolTable.Vector(x: 0, y: PoolTable.headString)).y
            var line = Path()
            line.move(to: CGPoint(x: mapping.cloth.minX, y: y))
            line.addLine(to: CGPoint(x: mapping.cloth.maxX, y: y))
            context.stroke(line, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            let kitchen = CGRect(x: mapping.cloth.minX, y: y, width: mapping.cloth.width, height: mapping.cloth.maxY - y)
            context.fill(Path(kitchen), with: .color(.white.opacity(0.05)))
        }
    }

    /// A ball: solid colour, or white with a coloured band for the stripes, the number in
    /// a white spot, and a highlight.
    static func drawBall(in context: inout GraphicsContext, number: Int, at centre: CGPoint, radius r: CGFloat) {
        let disc = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
        context.fill(Path(ellipseIn: CGRect(x: centre.x - r * 0.95, y: centre.y - r * 0.7, width: r * 2.1, height: r * 2.1)), with: .color(.black.opacity(0.3)))
        if number == 0 {
            context.fill(disc, with: .color(Color(white: 0.97)))
        } else if number > 8 {
            context.fill(disc, with: .color(Color(white: 0.97)))
            var band = context
            band.clip(to: disc)
            band.fill(Path(CGRect(x: centre.x - r, y: centre.y - r * 0.56, width: r * 2, height: r * 1.12)), with: .color(PoolColours.ball(number)))
        } else {
            context.fill(disc, with: .color(PoolColours.ball(number)))
        }
        // Shading towards the bottom right.
        context.fill(disc, with: .radialGradient(
            Gradient(colors: [.clear, .black.opacity(0.28)]),
            center: CGPoint(x: centre.x - r * 0.35, y: centre.y - r * 0.4), startRadius: r * 0.3, endRadius: r * 1.5
        ))
        if number > 0, r >= 4 {
            let spot = r * 0.5
            context.fill(Path(ellipseIn: CGRect(x: centre.x - spot, y: centre.y - spot, width: spot * 2, height: spot * 2)), with: .color(Color(white: 0.97)))
            context.draw(
                Text("\(number)").font(.system(size: r * 0.62, weight: .heavy, design: .rounded)).foregroundStyle(Color(white: 0.08)),
                at: centre
            )
        }
        let shine = r * 0.32
        context.fill(Path(ellipseIn: CGRect(x: centre.x - r * 0.55, y: centre.y - r * 0.62, width: shine * 1.6, height: shine)), with: .color(.white.opacity(0.55)))
    }

    /// The cue stick, lying behind the cue ball along `direction`, drawn back by `pull` points.
    static func drawCue(in context: inout GraphicsContext, ball: CGPoint, direction: CGVector, pull: CGFloat, ballRadius: CGFloat, length: CGFloat) {
        let back = CGVector(dx: -direction.dx, dy: -direction.dy)
        let side = CGVector(dx: -direction.dy, dy: direction.dx)
        let start = CGPoint(x: ball.x + back.dx * (ballRadius * 1.6 + pull), y: ball.y + back.dy * (ballRadius * 1.6 + pull))
        let end = CGPoint(x: start.x + back.dx * length, y: start.y + back.dy * length)
        func quad(_ a: CGPoint, _ b: CGPoint, _ wa: CGFloat, _ wb: CGFloat) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: a.x + side.dx * wa, y: a.y + side.dy * wa))
            p.addLine(to: CGPoint(x: b.x + side.dx * wb, y: b.y + side.dy * wb))
            p.addLine(to: CGPoint(x: b.x - side.dx * wb, y: b.y - side.dy * wb))
            p.addLine(to: CGPoint(x: a.x - side.dx * wa, y: a.y - side.dy * wa))
            p.closeSubpath()
            return p
        }
        let tipWidth = max(1.4, ballRadius * 0.28), buttWidth = max(3, ballRadius * 0.62)
        func along(_ f: CGFloat) -> CGPoint { CGPoint(x: start.x + (end.x - start.x) * f, y: start.y + (end.y - start.y) * f) }
        let shadowOffset = CGSize(width: 3, height: 4)
        context.fill(quad(start, end, tipWidth, buttWidth).applying(CGAffineTransform(translationX: shadowOffset.width, y: shadowOffset.height)), with: .color(.black.opacity(0.3)))
        context.fill(quad(start, along(0.03), tipWidth, tipWidth * 1.02), with: .color(Color(red: 0.25, green: 0.45, blue: 0.75)))
        context.fill(quad(along(0.03), along(0.06), tipWidth * 1.02, tipWidth * 1.08), with: .color(Color(white: 0.95)))
        context.fill(quad(along(0.06), along(0.62), tipWidth * 1.08, buttWidth * 0.8), with: .color(Color(red: 0.93, green: 0.8, blue: 0.58)))
        context.fill(quad(along(0.62), end, buttWidth * 0.8, buttWidth), with: .color(Color(red: 0.2, green: 0.1, blue: 0.06)))
        context.fill(quad(along(0.6), along(0.64), buttWidth * 0.79, buttWidth * 0.82), with: .color(Color(white: 0.9)))
    }
}

enum PocketArt {
    /// Pockets are drawn a little further out than their capture circle, at the rail's corner.
    static func drawnCentre(_ pocket: PoolTable.Pocket, index: Int) -> PoolTable.Vector {
        index < 4 ? PoolTable.Vector(x: pocket.centre.x + (pocket.centre.x < 0 ? -10 : 10), y: pocket.centre.y + (pocket.centre.y < 0 ? -10 : 10)) : PoolTable.Vector(x: pocket.centre.x + (pocket.centre.x < 0 ? -12 : 12), y: pocket.centre.y)
    }
}

// MARK: - Aim guide

/// Where the aimed cue ball would first touch something, worked out with straight-line
/// geometry for the guide (the physics decides what really happens).
struct AimGuide {
    let contact: PoolTable.Vector
    /// The ball it would hit, its centre, and the directions both balls would take.
    let ball: (number: Int, centre: PoolTable.Vector, objectDirection: PoolTable.Vector, cueDirection: PoolTable.Vector)?

    init(from cue: PoolTable.Vector, direction d: PoolTable.Vector, positions: [PoolTable.Vector?]) {
        let r = PoolTable.ballRadius
        var best = Double.greatestFiniteMagnitude
        var hit: (Int, PoolTable.Vector)?
        for (index, position) in positions.enumerated() where index != 0 {
            guard let b = position else { continue }
            let toBall = PoolTable.Vector(x: b.x - cue.x, y: b.y - cue.y)
            let along = toBall.x * d.x + toBall.y * d.y
            guard along > 0 else { continue }
            let perpendicularSquared = toBall.x * toBall.x + toBall.y * toBall.y - along * along
            let reach = 4 * r * r
            guard perpendicularSquared < reach else { continue }
            let t = along - (reach - perpendicularSquared).squareRoot()
            if t < best, t >= 0 {
                best = t
                hit = (index, b)
            }
        }
        // The cushions, as the box the ball's centre can reach.
        var wall = Double.greatestFiniteMagnitude
        if d.x > 0 { wall = min(wall, (PoolTable.width - r - cue.x) / d.x) }
        if d.x < 0 { wall = min(wall, (r - cue.x) / d.x) }
        if d.y > 0 { wall = min(wall, (PoolTable.length - r - cue.y) / d.y) }
        if d.y < 0 { wall = min(wall, (r - cue.y) / d.y) }
        wall = max(0, wall)
        if let (number, centre) = hit, best <= wall {
            let ghost = PoolTable.Vector(x: cue.x + d.x * best, y: cue.y + d.y * best)
            let n = PoolTable.Vector(x: centre.x - ghost.x, y: centre.y - ghost.y)
            let nLength = max(n.length, 1e-9)
            let unitN = PoolTable.Vector(x: n.x / nLength, y: n.y / nLength)
            let dot = d.x * unitN.x + d.y * unitN.y
            var tangent = PoolTable.Vector(x: d.x - unitN.x * dot, y: d.y - unitN.y * dot)
            let tangentLength = tangent.length
            tangent = tangentLength > 1e-6 ? PoolTable.Vector(x: tangent.x / tangentLength, y: tangent.y / tangentLength) : .zero
            contact = ghost
            ball = (number, centre, unitN, tangent)
        } else {
            contact = PoolTable.Vector(x: cue.x + d.x * wall, y: cue.y + d.y * wall)
            ball = nil
        }
    }
}

// MARK: - Shots to animate

/// A shot to show on the table: where everything was when it was struck, and the shot.
public struct PoolShotPlayback: Identifiable, Equatable, Sendable {
    public let id: Int
    public let startPositions: [PoolTable.Vector?]
    public let shot: EightBall.Shot

    public init(id: Int, startPositions: [PoolTable.Vector?], shot: EightBall.Shot) {
        self.id = id
        self.startPositions = startPositions
        self.shot = shot
    }

    /// Every shot of a recorded turn, numbered from `firstID`.
    public static func turn(_ results: [EightBall.ShotResult], firstID: Int) -> [PoolShotPlayback] {
        results.enumerated().map { PoolShotPlayback(id: firstID + $0.offset, startPositions: $0.element.startPositions, shot: $0.element.shot) }
    }
}

// MARK: - The table

/// The whole 8-Ball screen, laid out like the classic iMessage pool game: a dark room, the
/// players and their groups along the top, the table filling the screen, a power bar on
/// the left and a spin control. Touch the table to point the cue; drag the power bar down
/// and let go to shoot. With the cue ball in hand, drag the ball to place it first.
public struct EightBallTable<MenuItems: View, Footer: View>: View {
    let state: EightBall.State
    /// The table now: after any shots already taken this turn.
    let positions: [PoolTable.Vector?]
    let groups: [Seat: EightBall.Group]
    let ballInHand: EightBall.BallInHand
    let localSeat: Seat?
    let shooter: Seat?
    let canShoot: Bool
    let shots: [PoolShotPlayback]
    let replaysShots: Bool
    /// The id the next shot taken here will be given in `shots`.
    let nextShotID: Int
    let status: String?
    let banner: DartsBanner?
    let winner: Seat?
    let notices: [String]
    let onShoot: (EightBall.Shot) -> Void
    let menuItems: MenuItems
    let footer: Footer

    @State private var aim = PoolTable.Vector(x: 0, y: -1)
    @State private var power = 0.0
    @State private var placing: PoolTable.Vector?
    @State private var placingLegal = true
    @State private var spin = (x: 0, y: 0)
    @State private var showingSpin = false
    @State private var showingRules = false
    @State private var playing: Playing?
    @State private var queue: [PoolShotPlayback] = []
    @State private var seen: Set<Int> = []
    @State private var pots = 0
    @State private var hits = 0
    /// What the finger on the table is doing, decided when it touches down.
    @State private var dragMode: DragMode?
    /// The aim when a fine-tune drag began.
    @State private var fineStartAim: PoolTable.Vector?
    @State private var fineOffset: CGFloat = 0
    @Environment(\.seatPalette) private var palette

    enum DragMode {
        case placing
        case aiming
    }

    struct Playing: Equatable {
        let id: Int
        let frames: [[PoolTable.Vector?]]
        let start: Date
        let pocketFrames: [Int]
        let hitFrames: [Int]
        static func == (a: Playing, b: Playing) -> Bool { a.id == b.id && a.start == b.start }
    }

    public init(
        state: EightBall.State,
        positions: [PoolTable.Vector?],
        groups: [Seat: EightBall.Group],
        ballInHand: EightBall.BallInHand,
        localSeat: Seat?,
        shooter: Seat?,
        canShoot: Bool,
        shots: [PoolShotPlayback],
        replaysShots: Bool = false,
        nextShotID: Int,
        status: String?,
        banner: DartsBanner?,
        winner: Seat?,
        notices: [String] = [],
        onShoot: @escaping (EightBall.Shot) -> Void,
        @ViewBuilder menuItems: () -> MenuItems,
        @ViewBuilder footer: () -> Footer
    ) {
        self.state = state
        self.positions = positions
        self.groups = groups
        self.ballInHand = ballInHand
        self.localSeat = localSeat
        self.shooter = shooter
        self.canShoot = canShoot
        self.shots = shots
        self.replaysShots = replaysShots
        self.nextShotID = nextShotID
        self.status = status
        self.banner = banner
        self.winner = winner
        self.notices = notices
        self.onShoot = onShoot
        self.menuItems = menuItems()
        self.footer = footer()
    }

    private var isIdle: Bool { playing == nil && queue.isEmpty }
    private var canAim: Bool { canShoot && isIdle }
    private var cueBall: PoolTable.Vector? { placing ?? positions[0] }

    public var body: some View {
        VStack(spacing: 8) {
            players
                .padding(.horizontal, 12)
            if let status, isIdle {
                Text(status)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .transition(.opacity)
            }
            ForEach(notices, id: \.self) { notice in
                Text(notice)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
            }
            HStack(spacing: 8) {
                powerBar
                    .frame(width: 34)
                tableArea
                fineAim
                    .frame(width: 26)
            }
            .padding(.horizontal, 8)
            footer
            bottomBar
                .padding(.horizontal, 12)
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [PoolColours.backdrop, Color(red: 0.03, green: 0.04, blue: 0.06)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: banner)
        .animation(.easeInOut(duration: 0.2), value: isIdle)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: pots)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: hits)
        .onAppear(perform: start)
        .onChange(of: shots) { _, new in enqueue(new) }
        .onChange(of: ballInHand) { _, _ in
            placing = nil
            prepareTurn()
        }
        .onChange(of: canShoot) { _, _ in prepareTurn() }
        .alert("How to play", isPresented: $showingRules) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Touch the table to point the cue, then pull the power bar down and let go to shoot. Sink all of your group (solids or stripes), then the 8. Sink your own ball to keep shooting. Fouls give your opponent the cue ball in hand. Sinking the 8 early loses.")
        }
        .overlay {
            if showingSpin { spinPicker }
        }
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
        let tokens = groupTokens(seat)
        return HStack(spacing: 6) {
            if alignment == .leading {
                badge
                tokens
            } else {
                tokens
                badge
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription(seat))
    }

    private func groupTokens(_ seat: Seat) -> some View {
        let group = groups[seat]
        let balls: [Int] = group.map { Array($0.balls) } ?? []
        let cleared = group != nil && balls.allSatisfy { positions[$0] == nil }
        return VStack(alignment: .leading, spacing: 3) {
            Text(group == .solids ? "SOLIDS" : group == .stripes ? "STRIPES" : " ")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 2) {
                if group == nil {
                    ForEach(0..<7, id: \.self) { _ in
                        Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1).frame(width: 11, height: 11)
                    }
                } else {
                    ForEach(cleared ? [8] : balls, id: \.self) { number in
                        BallToken(number: number)
                            .opacity(positions[number] == nil ? 0.2 : 1)
                            .frame(width: 11, height: 11)
                    }
                }
            }
        }
    }

    private func label(for seat: Seat) -> String? {
        guard let localSeat else { return palette.name(seat) }
        return seat == localSeat ? "You" : nil
    }

    private func accessibilityDescription(_ seat: Seat) -> String {
        let who = label(for: seat) ?? "Them"
        let group = groups[seat].map { $0 == .solids ? "solids" : "stripes" } ?? "no group yet"
        let left = groups[seat].map { group in group.balls.filter { positions[$0] != nil }.count } ?? 7
        let toAct = state.outcome.seatToAct == seat ? ", to shoot" : ""
        return "\(who), \(group), \(left) left\(toAct)"
    }

    // MARK: Table

    private var tableArea: some View {
        GeometryReader { proxy in
            let mapping = PoolMapping(fitting: proxy.size)
            TimelineView(.animation(minimumInterval: 1 / 60, paused: playing == nil)) { timeline in
                let shown = displayed(at: timeline.date)
                Canvas { context, _ in
                    PoolPainter.drawTable(in: &context, mapping: mapping, showsHeadString: canAim && ballInHand == .behindHeadString)
                    let r = mapping.ballRadius
                    if canAim, let cue = shown[0] { drawGuide(in: &context, mapping: mapping, cue: cue, positions: shown) }
                    for number in [Int](1...15) + [0] {
                        guard let p = shown[number] else { continue }
                        PoolPainter.drawBall(in: &context, number: number, at: mapping.point(p), radius: r)
                    }
                    if canAim, let cue = shown[0] {
                        if ballInHand != .none {
                            // A ring says the cue ball can be moved.
                            let c = mapping.point(cue)
                            context.stroke(Path(ellipseIn: CGRect(x: c.x - r * 2, y: c.y - r * 2, width: r * 4, height: r * 4)), with: .color(placingLegal ? .white.opacity(0.8) : .red), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        }
                        PoolPainter.drawCue(
                            in: &context, ball: mapping.point(cue), direction: CGVector(dx: aim.x, dy: aim.y),
                            pull: CGFloat(power) * mapping.length(260), ballRadius: r, length: mapping.length(1_350)
                        )
                    }
                }
            }
            .overlay {
                if let banner, isIdle {
                    GameBannerView(banner: banner)
                        .padding(.horizontal, 30)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .gesture(tableGesture(mapping: mapping), including: canAim ? .all : .subviews)
            .accessibilityElement()
            .accessibilityLabel("Pool table")
            .accessibilityHint(canAim ? "Use the actions to aim at a ball and shoot." : "")
            .accessibilityActions {
                if canAim {
                    ForEach(legalTargets, id: \.self) { number in
                        Button("Aim at the \(number)") { aimAt(number) }
                    }
                    Button("Shoot, medium power") { shoot(power: 0.55) }
                }
            }
        }
        .aspectRatio(PoolMapping.aspect, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func drawGuide(in context: inout GraphicsContext, mapping: PoolMapping, cue: PoolTable.Vector, positions: [PoolTable.Vector?]) {
        let guide = AimGuide(from: cue, direction: aim, positions: positions)
        let r = mapping.ballRadius
        let from = mapping.point(cue), to = mapping.point(guide.contact)
        var line = Path()
        line.move(to: from)
        line.addLine(to: to)
        context.stroke(line, with: .color(.white.opacity(0.85)), lineWidth: 1.2)
        context.stroke(Path(ellipseIn: CGRect(x: to.x - r, y: to.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.85)), lineWidth: 1.2)
        if let ball = guide.ball {
            let centre = mapping.point(ball.centre)
            var objectLine = Path()
            objectLine.move(to: centre)
            objectLine.addLine(to: CGPoint(x: centre.x + ball.objectDirection.x * r * 7, y: centre.y + ball.objectDirection.y * r * 7))
            context.stroke(objectLine, with: .color(.white.opacity(0.85)), lineWidth: 1.2)
            var cueLine = Path()
            cueLine.move(to: to)
            cueLine.addLine(to: CGPoint(x: to.x + ball.cueDirection.x * r * 4, y: to.y + ball.cueDirection.y * r * 4))
            context.stroke(cueLine, with: .color(.white.opacity(0.4)), lineWidth: 1)
            if !isLegalFirst(ball.number) {
                // Hitting this one first would be a foul.
                let x = r * 0.7
                var cross = Path()
                cross.move(to: CGPoint(x: to.x - x, y: to.y - x))
                cross.addLine(to: CGPoint(x: to.x + x, y: to.y + x))
                cross.move(to: CGPoint(x: to.x + x, y: to.y - x))
                cross.addLine(to: CGPoint(x: to.x - x, y: to.y + x))
                context.stroke(cross, with: .color(.red), lineWidth: 1.5)
            }
        }
    }

    private func isLegalFirst(_ number: Int) -> Bool {
        guard let shooter, !state.isBreak else { return true }
        guard let group = groups[shooter] else { return number != 8 }
        let cleared = group.balls.allSatisfy { positions[$0] == nil }
        return cleared ? number == 8 : EightBall.Group.of(number) == group
    }

    private var legalTargets: [Int] {
        (1...15).filter { positions[$0] != nil && isLegalFirst($0) }
    }

    /// The balls as they should be drawn now: a frame of the shot being shown, or the table.
    private func displayed(at date: Date) -> [PoolTable.Vector?] {
        if let playing {
            let index = min(playing.frames.count - 1, max(0, Int(date.timeIntervalSince(playing.start) * 60)))
            return playing.frames[index]
        }
        if let next = queue.first { return next.startPositions }
        var shown = positions
        if let placing { shown[0] = placing }
        return shown
    }

    /// Touching near the cue ball while it is in hand moves it; anywhere else points the cue.
    private func tableGesture(mapping: PoolMapping) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canAim else { return }
                let touch = mapping.vector(value.location)
                if dragMode == nil {
                    let start = mapping.vector(value.startLocation)
                    let nearCue = cueBall.map { (start - $0).length < PoolTable.ballRadius * 3 } ?? true
                    dragMode = ballInHand != .none && nearCue ? .placing : .aiming
                }
                if dragMode == .placing {
                    move(cueTo: touch)
                } else {
                    point(at: touch)
                }
            }
            .onEnded { _ in dragMode = nil }
    }

    /// With the cue ball in hand and off the table, start it somewhere legal near the head spot.
    private func prepareTurn() {
        guard canShoot else { return }
        if ballInHand != .none, positions[0] == nil, placing == nil {
            for offset in stride(from: 0.0, through: 600, by: 30) {
                for sign in [1.0, -1.0] {
                    let spot = PoolTable.Vector(x: PoolTable.headSpot.x + sign * offset, y: PoolTable.headSpot.y)
                    if EightBall.isLegalPlacement(placement(for: spot), ballInHand: ballInHand, positions: positions) {
                        placing = spot
                        placingLegal = true
                        aimAtSomething()
                        return
                    }
                }
            }
        }
        aimAtSomething()
    }

    private func move(cueTo point: PoolTable.Vector) {
        let clamped = PoolTable.Vector(
            x: min(max(point.x, PoolTable.ballRadius), PoolTable.width - PoolTable.ballRadius),
            y: min(max(point.y, ballInHand == .behindHeadString ? PoolTable.headString : PoolTable.ballRadius), PoolTable.length - PoolTable.ballRadius)
        )
        placing = clamped
        placingLegal = EightBall.isLegalPlacement(placement(for: clamped), ballInHand: ballInHand, positions: positions)
    }

    private func point(at target: PoolTable.Vector) {
        guard let cue = cueBall else { return }
        let d = PoolTable.Vector(x: target.x - cue.x, y: target.y - cue.y)
        let length = d.length
        guard length > PoolTable.ballRadius else { return }
        aim = PoolTable.Vector(x: d.x / length, y: d.y / length)
    }

    private func aimAt(_ number: Int) {
        guard let target = positions[number] else { return }
        point(at: target)
    }

    /// Starting aim: the nearest ball it is legal to hit first.
    private func aimAtSomething() {
        guard let cue = cueBall else { return }
        let nearest = legalTargets.compactMap { number in positions[number].map { (number, ($0 - cue).length) } }.min { $0.1 < $1.1 }
        if let nearest { aimAt(nearest.0) }
    }

    private func placement(for point: PoolTable.Vector) -> EightBall.Shot.Placement {
        EightBall.Shot.Placement(x: Int(point.x.rounded()), y: Int(point.y.rounded()))
    }

    // MARK: Power and spin

    private var powerBar: some View {
        GeometryReader { proxy in
            let height = proxy.size.height * 0.62
            let top = (proxy.size.height - height) / 2
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.1), Color(red: 0.95, green: 0.25, blue: 0.1)], startPoint: .top, endPoint: .bottom))
                    .frame(height: max(0, (height - 6) * power))
                    .padding(3)
                // The handle: drag it down.
                Capsule()
                    .fill(Color.white)
                    .frame(width: 30, height: 10)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(y: max(0, (height - 10) * power))
            }
            .frame(width: 30, height: height)
            .offset(x: 2, y: top)
            .opacity(canAim ? 1 : 0.35)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard canAim else { return }
                        power = min(1, max(0, value.translation.height / height))
                    }
                    .onEnded { _ in
                        guard canAim else { return }
                        let release = power
                        if release > 0.03 { shoot(power: release) }
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { power = 0 }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Power")
            .accessibilityHint("Drag down, then let go to shoot")
        }
    }

    /// A ridged wheel beside the table: drag it up or down to turn the cue a little.
    private var fineAim: some View {
        GeometryReader { proxy in
            let height = proxy.size.height * 0.62
            let top = (proxy.size.height - height) / 2
            let spacing: CGFloat = 7
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.42), Color(white: 0.2)], startPoint: .leading, endPoint: .trailing))
                Canvas { context, size in
                    let shift = fineOffset.truncatingRemainder(dividingBy: spacing)
                    var y = shift - spacing
                    while y < size.height + spacing {
                        var ridge = Path()
                        ridge.move(to: CGPoint(x: 3, y: y))
                        ridge.addLine(to: CGPoint(x: size.width - 3, y: y))
                        context.stroke(ridge, with: .color(.black.opacity(0.45)), lineWidth: 1.5)
                        y += spacing
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            }
            .frame(width: 22, height: height)
            .offset(x: 2, y: top)
            .opacity(canAim ? 1 : 0.35)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard canAim else { return }
                        if fineStartAim == nil { fineStartAim = aim }
                        guard let base = fineStartAim else { return }
                        let angle = Double(value.translation.height) * 0.0012
                        let c = cos(angle), s = sin(angle)
                        aim = PoolTable.Vector(x: base.x * c - base.y * s, y: base.x * s + base.y * c)
                        fineOffset = value.translation.height
                    }
                    .onEnded { _ in fineStartAim = nil }
            )
            .accessibilityElement()
            .accessibilityLabel("Fine aim")
            .accessibilityAdjustableAction { direction in
                let angle = direction == .increment ? 0.01 : -0.01
                let c = cos(angle), s = sin(angle)
                aim = PoolTable.Vector(x: aim.x * c - aim.y * s, y: aim.x * s + aim.y * c)
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
            Button { showingSpin = true } label: {
                SpinBall(spin: spin)
                    .frame(width: 40, height: 40)
            }
            .disabled(!canAim)
            .opacity(canAim ? 1 : 0.4)
            .accessibilityLabel("Spin")
            .accessibilityValue(spinDescription)
        }
    }

    private var spinDescription: String {
        let vertical = spin.y > 0 ? "follow" : spin.y < 0 ? "draw" : ""
        let horizontal = spin.x > 0 ? "right" : spin.x < 0 ? "left" : ""
        let parts = [vertical, horizontal].filter { !$0.isEmpty }
        return parts.isEmpty ? "centre" : parts.joined(separator: " and ")
    }

    private var spinPicker: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { showingSpin = false }
            VStack(spacing: 16) {
                Text("SPIN")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                GeometryReader { proxy in
                    let size = proxy.size.width
                    SpinBall(spin: spin)
                        .contentShape(Circle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            let limit = Double(EightBall.maximumSpin)
                            var x = (value.location.x / size - 0.5) * 2 * limit
                            var y = -(value.location.y / size - 0.5) * 2 * limit
                            let length = (x * x + y * y).squareRoot()
                            if length > limit {
                                x *= limit / length
                                y *= limit / length
                            }
                            var sx = Int(x.rounded()), sy = Int(y.rounded())
                            while sx * sx + sy * sy > EightBall.maximumSpin * EightBall.maximumSpin {
                                if abs(sx) > abs(sy) { sx -= sx.signum() } else { sy -= sy.signum() }
                            }
                            spin = (sx, sy)
                        })
                }
                .frame(width: 180, height: 180)
                HStack(spacing: 12) {
                    Button("Centre") { spin = (0, 0) }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Button("Done") { showingSpin = false }
                        .buttonStyle(GameButtonStyle())
                }
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(white: 0.12)))
        }
        .transition(.opacity)
    }

    // MARK: Shooting and playback

    private func shoot(power fraction: Double) {
        guard canAim, let cue = cueBall else { return }
        var placementValue: EightBall.Shot.Placement?
        if ballInHand != .none {
            let placed = placement(for: cue)
            guard EightBall.isLegalPlacement(placed, ballInHand: ballInHand, positions: positions) else {
                placingLegal = false
                return
            }
            placementValue = placed
        }
        let scale = Double(EightBall.directionScale) / max(abs(aim.x), abs(aim.y))
        let shot = EightBall.Shot(
            dx: Int((aim.x * scale).rounded()),
            dy: Int((aim.y * scale).rounded()),
            power: min(EightBall.maximumPower, max(1, Int((fraction * Double(EightBall.maximumPower)).rounded()))),
            spinX: spin.x,
            spinY: spin.y,
            placement: placementValue
        )
        guard EightBall.validate(shot, ballInHand: ballInHand, positions: positions) == nil else { return }
        seen.insert(nextShotID)
        play(PoolShotPlayback(id: nextShotID, startPositions: positions, shot: shot))
        placing = nil
        spin = (0, 0)
        onShoot(shot)
    }

    private func start() {
        if replaysShots {
            enqueue(shots)
        } else {
            seen.formUnion(shots.map(\.id))
        }
        prepareTurn()
    }

    private func enqueue(_ all: [PoolShotPlayback]) {
        let fresh = all.filter { !seen.contains($0.id) }
        guard !fresh.isEmpty else { return }
        seen.formUnion(fresh.map(\.id))
        queue.append(contentsOf: fresh)
        if playing == nil { playNext() }
    }

    private func playNext() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        // A short pause between shots so each one reads.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            play(next)
        }
    }

    private func play(_ playback: PoolShotPlayback) {
        let outcome = EightBall.animation(of: playback.shot, from: playback.startPositions)
        var pocketFrames: [Int] = [], hitFrames: [Int] = []
        for event in outcome.events {
            switch event {
            case .pocketed(let frame, _, _): pocketFrames.append(frame)
            case .ballHit(let frame, let speed) where speed > 300: hitFrames.append(frame)
            default: break
            }
        }
        let current = Playing(id: playback.id, frames: outcome.frames, start: Date(), pocketFrames: pocketFrames, hitFrames: hitFrames)
        playing = current
        // Haptics for the drops and the harder knocks, on time with the picture.
        for frame in Set(pocketFrames).sorted() {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Double(frame) / 60))
                if playing?.id == current.id { pots += 1 }
            }
        }
        for frame in Set(hitFrames).sorted().prefix(6) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Double(frame) / 60))
                if playing?.id == current.id { hits += 1 }
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Double(outcome.frames.count) / 60 + 0.1))
            guard playing?.id == current.id else { return }
            playing = nil
            if queue.isEmpty {
                prepareTurn()
            } else {
                playNext()
            }
        }
    }
}

/// A small ball icon, for the group rows.
struct BallToken: View {
    let number: Int

    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2
            PoolPainter.drawBall(in: &context, number: number, at: CGPoint(x: size.width / 2, y: size.height / 2), radius: r)
        }
    }
}

/// The cue ball seen head on with a red dot where it will be struck.
struct SpinBall: View {
    let spin: (x: Int, y: Int)

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let limit = CGFloat(EightBall.maximumSpin)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white, Color(white: 0.78)], center: .init(x: 0.38, y: 0.35), startRadius: 0, endRadius: size * 0.7))
                Circle()
                    .fill(Color.red)
                    .frame(width: size * 0.18, height: size * 0.18)
                    .offset(x: CGFloat(spin.x) / limit * size * 0.4, y: -CGFloat(spin.y) / limit * size * 0.4)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Bubble

/// The message bubble picture: the table as it stands, with the classic strip.
public struct EightBallBubbleArt: View {
    let state: EightBall.State

    public init(state: EightBall.State) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                PoolColours.backdrop
                Canvas { context, size in
                    // The table lies on its side to fill the wide picture.
                    var turned = context
                    turned.translateBy(x: size.width / 2, y: size.height / 2)
                    turned.rotate(by: .degrees(-90))
                    let fitted = CGSize(width: size.height - 12, height: size.width - 12)
                    turned.translateBy(x: -fitted.width / 2, y: -fitted.height / 2)
                    let mapping = PoolMapping(fitting: fitted)
                    PoolPainter.drawTable(in: &turned, mapping: mapping, showsHeadString: false)
                    for number in [Int](1...15) + [0] {
                        guard let p = state.positions[number] else { continue }
                        PoolPainter.drawBall(in: &turned, number: number, at: mapping.point(p), radius: mapping.ballRadius * 1.25)
                    }
                }
                if state.outcome.winner != nil {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.1))
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 3)
                }
            }
            BubbleStrip(text: state.outcome.isFinished ? "Game over" : state.isBreak ? "Let's play 8 Ball!" : "Your turn")
        }
        .frame(width: 300, height: 225)
        .clipped()
    }
}
#endif
