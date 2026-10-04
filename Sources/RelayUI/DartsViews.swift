#if canImport(UIKit)
import RelayCore
import RelayGames
import SwiftUI

/// Board units (tenths of a millimetre) from the centre to the edge of the drawn board,
/// including the number ring outside the doubles.
private let drawnRadius = 2_250.0
/// Board units from the centre to the edge of the view when the wall behind the board is
/// shown, so a dart that misses the board still has somewhere visible to stick.
private let wallRadius = 3_000.0

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

/// Where things sit on a board view of a given size. Shared by the board, which draws
/// stuck darts, and the throw view, whose flights must end exactly on them.
struct DartsBoardGeometry {
    let side: CGFloat
    let visibleRadius: Double

    init(side: CGFloat, showsWall: Bool) {
        self.side = side
        visibleRadius = showsWall ? wallRadius : drawnRadius
    }

    var scale: CGFloat { side / 2 / CGFloat(visibleRadius) }

    /// Screen point for a board position, kept inside the view so far misses stay visible.
    func point(for hit: Darts.Hit) -> CGPoint {
        let limit = visibleRadius - 150
        let x = min(max(Double(hit.x), -limit), limit), y = min(max(Double(hit.y), -limit), limit)
        return CGPoint(x: side / 2 + CGFloat(x) * scale, y: side / 2 - CGFloat(y) * scale)
    }

    /// A dart stuck in the board, seen from the oche: short, because it points at you.
    var stuckSize: CGSize { CGSize(width: 260 * scale, height: 420 * scale) }

    /// Darts lean a little away from the middle, as if thrown from in front of the bull.
    func tilt(for hit: Darts.Hit) -> Double {
        min(max(Double(hit.x) / 3_000 * 14, -14), 14)
    }
}

/// The dartboard, drawn in Relay's own palette (not the traditional red/green/black/cream,
/// and nothing borrowed from another app): sand and slate beds, Ember and Tide scoring rings.
/// Darts stay stuck in it where they landed.
public struct DartsBoardView: View {
    let darts: [PlacedDart]
    /// Darts that are thrown (committed) but still in the air, so not drawn yet.
    let hiddenDarts: Set<Int>
    /// Shows the wall around the board, so misses stay in view.
    let showsWall: Bool
    /// False for still images (bubble art), which render before any animation runs.
    let animatesDarts: Bool
    @Environment(\.seatPalette) private var palette

    public init(darts: [PlacedDart], hiddenDarts: Set<Int> = [], showsWall: Bool = false, animatesDarts: Bool = true) {
        self.darts = darts
        self.hiddenDarts = hiddenDarts
        self.showsWall = showsWall
        self.animatesDarts = animatesDarts
    }

    public var body: some View {
        GeometryReader { proxy in
            let geometry = DartsBoardGeometry(side: min(proxy.size.width, proxy.size.height), showsWall: showsWall)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawBoard(in: &context, geometry: geometry)
                }
                .accessibilityHidden(true)
                ForEach(darts.filter { !hiddenDarts.contains($0.id) }) { dart in
                    StuckDart(colour: palette.colour(dart.seat), tilt: geometry.tilt(for: dart.hit), animates: animatesDarts)
                        .frame(width: geometry.stuckSize.width, height: geometry.stuckSize.height)
                        // The tip is the top edge of the dart.
                        .position(x: geometry.point(for: dart.hit).x, y: geometry.point(for: dart.hit).y + geometry.stuckSize.height / 2)
                }
            }
            .frame(width: geometry.side, height: geometry.side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func drawBoard(in context: inout GraphicsContext, geometry: DartsBoardGeometry) {
        let scale = geometry.scale
        let centre = CGPoint(x: geometry.side / 2, y: geometry.side / 2)
        func circle(_ radius: Double, offsetY: CGFloat = 0) -> Path {
            let r = CGFloat(radius) * scale
            return Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r + offsetY, width: r * 2, height: r * 2))
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

        if showsWall {
            let wall = Path(roundedRect: CGRect(x: 0, y: 0, width: geometry.side, height: geometry.side), cornerRadius: geometry.side * 0.05)
            context.fill(wall, with: .linearGradient(
                Gradient(colors: [Color(red: 0.20, green: 0.17, blue: 0.16), Color(red: 0.13, green: 0.11, blue: 0.11)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: geometry.side)
            ))
            // The board hangs slightly off the wall.
            var shadow = context
            shadow.addFilter(.blur(radius: geometry.side * 0.02))
            shadow.fill(circle(drawnRadius, offsetY: geometry.side * 0.015), with: .color(.black.opacity(0.55)))
        }

        context.fill(circle(drawnRadius), with: .color(RelayTheme.board))
        context.stroke(circle(drawnRadius - 8), with: .color(RelayTheme.boardEdge), lineWidth: 2)

        let sand = Color(red: 0.86, green: 0.81, blue: 0.70)
        let slate = Color(red: 0.17, green: 0.19, blue: 0.27)
        for index in 0..<DartsBoard.numbers.count {
            let even = index.isMultiple(of: 2)
            let bed = even ? slate : sand
            let ring = even ? RelayTheme.disc(.one) : RelayTheme.disc(.two)
            context.fill(wedge(index, inner: DartsBoard.outerBullRadius, outer: DartsBoard.trebleInnerRadius), with: .color(bed))
            context.fill(wedge(index, inner: DartsBoard.trebleInnerRadius, outer: DartsBoard.trebleOuterRadius), with: .color(ring))
            context.fill(wedge(index, inner: DartsBoard.trebleOuterRadius, outer: DartsBoard.doubleInnerRadius), with: .color(bed))
            context.fill(wedge(index, inner: DartsBoard.doubleInnerRadius, outer: DartsBoard.doubleOuterRadius), with: .color(ring))
        }
        context.fill(circle(Double(DartsBoard.outerBullRadius)), with: .color(RelayTheme.disc(.two)))
        context.fill(circle(Double(DartsBoard.bullRadius)), with: .color(RelayTheme.disc(.one)))

        let wire = Color.white.opacity(0.35)
        for radius in [DartsBoard.trebleInnerRadius, DartsBoard.trebleOuterRadius, DartsBoard.doubleInnerRadius, DartsBoard.doubleOuterRadius] {
            context.stroke(circle(Double(radius)), with: .color(wire), lineWidth: 0.6)
        }

        let fontSize = max(9, CGFloat(drawnRadius - Double(DartsBoard.doubleOuterRadius)) * scale * 0.55)
        for (index, number) in DartsBoard.numbers.enumerated() {
            let angle = (-90.0 + 18 * Double(index)) * .pi / 180
            let radius = CGFloat(Double(DartsBoard.doubleOuterRadius) + drawnRadius) / 2 * scale
            let position = CGPoint(x: centre.x + radius * CGFloat(cos(angle)), y: centre.y + radius * CGFloat(sin(angle)))
            context.draw(
                Text("\(number)").font(.system(size: fontSize, weight: .bold, design: .rounded)).foregroundStyle(RelayTheme.textPrimary),
                at: position
            )
        }
    }
}

/// A dart stuck where it landed. When it appears (the moment its flight arrives) it
/// jolts as it bites and its flights wobble, then it settles at its lean.
private struct StuckDart: View {
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
                    withAnimation(.interpolatingSpring(stiffness: 420, damping: 6)) { kick = 0 }
                }
            }
    }
}

/// One dart in the air, from where it left the hand to where it sticks.
private struct DartFlight: Identifiable {
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

private struct FlyingDart: View {
    let flight: DartFlight
    let onArrival: () -> Void
    @State private var progress = 0.0

    var body: some View {
        ThrowingDart(flights: flight.colour)
            .modifier(FlightPath(flight: flight, progress: progress))
            .allowsHitTesting(false)
            .onAppear {
                // Quick off the hand, easing as it travels away into the board.
                withAnimation(.timingCurve(0.25, 0.55, 0.5, 1, duration: DartsThrowView.flightDuration).delay(flight.delay)) {
                    progress = 1
                } completion: {
                    onArrival()
                }
            }
    }
}

/// Places a flying dart along a shallow arc, shrinking with distance (perspective) and
/// turning to its final lean, so the last frame is exactly the stuck dart.
private struct FlightPath: ViewModifier, Animatable {
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

/// The throwing area: the board on its wall, with a dart held below it. Swipe the dart up
/// to throw. How hard you flick sets how high it flies and the line of the flick sets left
/// and right (`DartsAim.flickTarget`); overdo it or slice it and it misses into the wall.
/// The landing point is committed the moment the dart leaves your hand; the flight is
/// only animation, and every dart (the bot's too) flies in rather than appearing.
/// VoiceOver users get throw actions.
public struct DartsThrowView: View {
    let darts: [PlacedDart]
    let seat: Seat
    let canThrow: Bool
    let suggestedTarget: DartsBoard.Segment?
    let onThrow: (Darts.Hit) -> Void

    /// Finger movement while the dart is held; kept at release until the flight takes over.
    @State private var hold: CGSize = .zero
    /// Where the player's dart left the hand, until its landing shows up in `darts`.
    @State private var launchTip: CGPoint?
    @State private var flights: [Int: DartFlight] = [:]
    /// Darts that have arrived (or were already there), so are drawn stuck in the board.
    @State private var landed: Set<Int> = []
    @State private var landings = 0
    @State private var dartInHand = true
    @Environment(\.seatPalette) private var palette

    /// Seconds from release to the dart hitting the board.
    static let flightDuration = 0.32
    /// Height of the area below the board where the dart is held, as a share of the board.
    private static let handHeight: CGFloat = 0.36

    public init(darts: [PlacedDart], seat: Seat, canThrow: Bool, suggestedTarget: DartsBoard.Segment? = nil, onThrow: @escaping (Darts.Hit) -> Void) {
        self.darts = darts
        self.seat = seat
        self.canThrow = canThrow
        self.suggestedTarget = suggestedTarget
        self.onThrow = onThrow
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height / (1 + Self.handHeight))
            let length = side * Self.handHeight * 0.8
            let board = DartsBoardGeometry(side: side, showsWall: true)
            let resting = restingTip(side: side)
            ZStack(alignment: .topLeading) {
                DartsBoardView(darts: darts, hiddenDarts: Set(darts.map(\.id)).subtracting(landed), showsWall: true)
                    .frame(width: side, height: side)
                // Always in the tree (only its opacity changes) so nothing around it moves.
                ThrowingDart(flights: palette.colour(seat))
                    .frame(width: length * 0.3, height: length)
                    .position(x: resting.x + hold.width, y: resting.y + hold.height + length / 2)
                    .opacity(canThrow && dartInHand ? 1 : 0)
                    .allowsHitTesting(false)
                ForEach(flights.values.sorted { $0.id < $1.id }) { flight in
                    FlyingDart(flight: flight) { arrive(flight.id) }
                }
            }
            .frame(width: side, height: side * (1 + Self.handHeight))
            .contentShape(Rectangle())
            .gesture(throwGesture(side: side), including: canThrow ? .all : .subviews)
            .onAppear { landed = Set(darts.map(\.id)) }
            .onChange(of: darts) { old, new in
                launchFlights(from: old, to: new, resting: resting, handSize: CGSize(width: length * 0.3, height: length), board: board)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1 / (1 + Self.handHeight), contentMode: .fit)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: landings)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(canThrow ? "Use the actions to throw a dart." : "")
        .accessibilityActions {
            if canThrow {
                ForEach(accessibilityTargets, id: \.self) { target in
                    Button("Throw at \(target.spokenName)") { throwAt(target) }
                }
            }
        }
    }

    /// Where the dart's tip rests: centred, a little way into the area below the board.
    private func restingTip(side: CGFloat) -> CGPoint {
        CGPoint(x: side / 2, y: side * (1 + Self.handHeight * 0.12))
    }

    private func throwGesture(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                // Only a swipe that starts on or below the bottom of the board picks up the dart.
                guard canThrow, dartInHand, launchTip == nil, value.startLocation.y > side * 0.85 else { return }
                hold = value.translation
            }
            .onEnded { value in
                guard canThrow, dartInHand, launchTip == nil, value.startLocation.y > side * 0.85 else { return }
                let target = DartsAim.flickTarget(
                    start: (Double(value.startLocation.x / side), Double(value.startLocation.y / side)),
                    release: (Double(value.location.x / side), Double(value.location.y / side)),
                    velocity: (Double(value.velocity.width / side), Double(value.velocity.height / side))
                )
                guard let target else {
                    withAnimation(.spring(duration: 0.3, bounce: 0.35)) { hold = .zero }
                    return
                }
                // Board widths to board units: the board's drawn edge is `drawnRadius` from the bull.
                let aim = Darts.Hit(x: Int(((target.x - 0.5) * 2 * drawnRadius).rounded()), y: Int(((0.5 - target.y) * 2 * drawnRadius).rounded()))
                let speed = (value.velocity.width * value.velocity.width + value.velocity.height * value.velocity.height).squareRoot() / side
                var rng = SystemRandomNumberGenerator()
                let hit = DartsAim.landing(aim: aim, scatter: DartsAim.scatter(forSpeed: Double(speed)), using: &rng)
                let resting = restingTip(side: side)
                launchTip = CGPoint(x: resting.x + hold.width, y: resting.y + hold.height)
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

    /// Starts a flight for every dart that just appeared. The player's own dart leaves from
    /// where it was let go; anyone else's (the bot's, or the other player's arriving visit)
    /// flies up from the hand position, one after another.
    private func launchFlights(from old: [PlacedDart], to new: [PlacedDart], resting: CGPoint, handSize: CGSize, board: DartsBoardGeometry) {
        let current = Set(new.map(\.id))
        landed.formIntersection(current)
        flights = flights.filter { current.contains($0.key) }
        let known = Set(old.map(\.id))
        for (index, dart) in new.filter({ !known.contains($0.id) }).enumerated() {
            let start = launchTip ?? resting
            if launchTip != nil {
                // The flying dart takes over from the one in hand in the same frame.
                launchTip = nil
                dartInHand = false
                hold = .zero
            }
            flights[dart.id] = DartFlight(
                id: dart.id,
                colour: palette.colour(dart.seat),
                fromTip: start,
                fromSize: handSize,
                toTip: board.point(for: dart.hit),
                toSize: board.stuckSize,
                tilt: board.tilt(for: dart.hit),
                lift: board.side * 0.08,
                delay: Double(index) * 0.35
            )
        }
    }

    private func arrive(_ id: Int) {
        guard flights[id] != nil else { return }
        flights[id] = nil
        landed.insert(id)
        landings += 1
        withAnimation(.easeOut(duration: 0.2).delay(0.12)) { dartInHand = true }
    }

    private func throwAt(_ segment: DartsBoard.Segment) {
        var rng = SystemRandomNumberGenerator()
        // Without a flick to judge, VoiceOver throws use a slightly wider scatter.
        onThrow(DartsAim.landing(aim: DartsBoard.target(for: segment), scatter: DartsAim.releaseScatter * 2, using: &rng))
    }

    private var accessibilityTargets: [DartsBoard.Segment] {
        var targets: [DartsBoard.Segment] = []
        if let suggestedTarget { targets.append(suggestedTarget) }
        for target in [DartsBoard.Segment(ring: .treble, number: 20), .init(ring: .treble, number: 19), .init(ring: .bull, number: 25), .init(ring: .single, number: 20)]
        where !targets.contains(target) {
            targets.append(target)
        }
        return targets
    }

    private var accessibilityDescription: String {
        guard !darts.isEmpty else { return "Dartboard" }
        let spoken = darts.map { DartsBoard.segment(at: $0.hit).spokenName }
        return "Dartboard. Darts: \(spoken.joined(separator: ", "))."
    }
}

/// A dart drawn pointing up: steel point, slate barrel with Ember grip bands, a thin shaft
/// and flights in the thrower's colour. Our own drawing, sized by its frame.
private struct ThrowingDart: View {
    let flights: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height, mid = w / 2
            func bar(_ top: CGFloat, _ bottom: CGFloat, width: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: mid - width / 2, y: h * top, width: width, height: h * (bottom - top)), cornerRadius: width / 2)
            }
            var point = Path()
            point.move(to: CGPoint(x: mid, y: 0))
            point.addLine(to: CGPoint(x: mid + w * 0.05, y: h * 0.24))
            point.addLine(to: CGPoint(x: mid - w * 0.05, y: h * 0.24))
            point.closeSubpath()
            context.fill(point, with: .color(Color(white: 0.82)))

            var fins = Path()
            fins.move(to: CGPoint(x: mid, y: h * 0.62))
            fins.addLine(to: CGPoint(x: w, y: h * 0.9))
            fins.addLine(to: CGPoint(x: w * 0.92, y: h))
            fins.addLine(to: CGPoint(x: mid, y: h * 0.93))
            fins.addLine(to: CGPoint(x: w * 0.08, y: h))
            fins.addLine(to: CGPoint(x: 0, y: h * 0.9))
            fins.closeSubpath()
            context.fill(fins, with: .color(flights))
            context.stroke(fins, with: .color(.black.opacity(0.35)), lineWidth: max(0.5, w * 0.03))

            context.fill(bar(0.56, 0.98, width: w * 0.1), with: .color(Color(white: 0.3)))
            context.fill(bar(0.22, 0.6, width: w * 0.3), with: .color(Color(red: 0.24, green: 0.27, blue: 0.36)))
            for band in [0.32, 0.4, 0.48] {
                context.fill(bar(band, band + 0.035, width: w * 0.3), with: .color(RelayTheme.disc(.one)))
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1.5)
    }
}

/// Three slots for the darts of a visit, then the visit total. Always laid out (empty
/// before the first dart) so nothing below it moves, and it catches up with a new dart
/// only once that dart has landed on the board.
public struct DartsVisitStrip: View {
    let latest: Darts.VisitProgress?
    let colour: Color
    @State private var shown: Darts.VisitProgress?
    @State private var changes = 0

    public init(progress: Darts.VisitProgress?, colour: Color) {
        latest = progress
        self.colour = colour
        _shown = State(initialValue: progress)
    }

    private var darts: [Darts.ScoredDart] { shown?.darts ?? [] }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<Darts.dartsPerVisit, id: \.self) { index in
                Text(index < darts.count ? darts[index].segment.shortName : "–")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(index < darts.count ? RelayTheme.textPrimary : RelayTheme.textSecondary)
                    .frame(minWidth: 44)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(index < darts.count ? colour.opacity(0.28) : RelayTheme.surface)
                    )
            }
            Spacer(minLength: 4)
            Text(summary)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(shown?.result == .bust ? RelayTheme.disc(.one) : RelayTheme.textPrimary)
        }
        .onChange(of: latest) { _, new in
            changes += 1
            let change = changes
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(DartsThrowView.flightDuration))
                // A later change may have arrived meanwhile; only the newest one shows.
                guard change == changes else { return }
                withAnimation(.easeOut(duration: 0.15)) { shown = new }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var summary: String {
        guard let shown else { return "" }
        switch shown.result {
        case .bust: return "Bust"
        case .finished: return "Checkout!"
        case .scored: return shown.darts.isEmpty ? "" : "+\(shown.points)"
        }
    }

    private var accessibilitySummary: String {
        guard let shown, !shown.darts.isEmpty else { return "No darts thrown yet this turn" }
        let names = shown.darts.map(\.segment.spokenName).joined(separator: ", ")
        switch shown.result {
        case .bust: return "\(names). Bust, nothing scored."
        case .finished: return "\(names). Checkout!"
        case .scored: return "\(names). \(shown.points) points, \(shown.remainingAfter) left."
        }
    }
}

/// A whole number that counts to its new value (201, 200, 199 … 141) instead of
/// morphing digit by digit, which can flash numbers that were never the score.
private struct CountingNumber: View, Animatable {
    var value: Double

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))")
    }
}

/// Remaining scores for both players, with whose turn it is and the round.
public struct DartsScoreboard: View {
    let state: Darts.State
    let localSeat: Seat?
    /// Points scored so far in the visit being thrown, shown as a live preview.
    let livePreview: (seat: Seat, remaining: Int)?
    let series: SeriesTally
    @Environment(\.seatPalette) private var palette

    public init(state: Darts.State, localSeat: Seat?, livePreview: (seat: Seat, remaining: Int)? = nil, series: SeriesTally = .empty) {
        self.state = state
        self.localSeat = localSeat
        self.livePreview = livePreview
        self.series = series
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                player(.one)
                player(.two)
            }
            Text(roundText)
                .font(.caption.weight(.medium))
                .foregroundStyle(RelayTheme.textSecondary)
        }
    }

    private var roundText: String {
        var text = "Round \(state.round) of \(state.configuration.rounds)"
        if let localSeat, series.gamesPlayed > 0 {
            text += " · Record \(series.wins(for: localSeat))–\(series.wins(for: localSeat.opponent))"
        }
        return text
    }

    private func name(_ seat: Seat) -> String {
        guard let localSeat else { return palette.name(seat) }
        return seat == localSeat ? "You" : "Them"
    }

    private func remaining(_ seat: Seat) -> Int {
        if let livePreview, livePreview.seat == seat { return livePreview.remaining }
        return state.remaining(for: seat)
    }

    private func player(_ seat: Seat) -> some View {
        let toAct = state.outcome.seatToAct == seat
        return VStack(spacing: 2) {
            HStack(spacing: 6) {
                DiscView(seat: seat).frame(width: 14, height: 14)
                Text(name(seat))
                    .font(.subheadline.weight(toAct ? .bold : .regular))
                    .foregroundStyle(toAct ? RelayTheme.textPrimary : RelayTheme.textSecondary)
            }
            CountingNumber(value: Double(remaining(seat)))
                .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(RelayTheme.textPrimary)
                // Count down as the dart hits the board, not when it leaves the hand.
                .animation(.easeOut(duration: 0.45).delay(DartsThrowView.flightDuration), value: remaining(seat))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(toAct ? palette.colour(seat).opacity(0.22) : RelayTheme.surface)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name(seat)): \(remaining(seat)) left")
        .accessibilityAddTraits(toAct ? .isSelected : [])
    }
}

/// Static art for a Darts message bubble: the board with the latest visit's darts and
/// both players' remaining scores (no names, D-016).
public struct DartsBubbleArt: View {
    let state: Darts.State
    let palette: SeatPalette

    public init(state: Darts.State, palette: SeatPalette = SeatPalette()) {
        self.state = state
        self.palette = palette
    }

    public var body: some View {
        HStack(spacing: 14) {
            DartsBoardView(darts: lastVisitDarts, animatesDarts: false)
                .frame(width: 190, height: 190)
            VStack(spacing: 12) {
                score(.one)
                score(.two)
            }
        }
        .padding(16)
        .frame(width: 300, height: 225)
        .background(LinearGradient(colors: [RelayTheme.surface, RelayTheme.background], startPoint: .top, endPoint: .bottom))
        .environment(\.seatPalette, palette)
    }

    private var lastVisitDarts: [PlacedDart] {
        guard let visit = state.lastVisit else { return [] }
        return visit.darts.enumerated().map { PlacedDart(id: $0.offset, hit: $0.element.hit, seat: visit.seat) }
    }

    private func score(_ seat: Seat) -> some View {
        VStack(spacing: 2) {
            DiscView(seat: seat).frame(width: 16, height: 16)
            Text("\(state.remaining(for: seat))")
                .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(RelayTheme.textPrimary)
        }
        .frame(width: 70)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.colour(seat).opacity(0.22)))
    }
}
#endif
