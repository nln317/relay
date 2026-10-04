#if canImport(UIKit)
import RelayCore
import RelayGames
import SwiftUI

/// Board units (tenths of a millimetre) from the centre to the edge of the drawn board,
/// including the number ring outside the doubles.
private let drawnRadius = 2_250.0

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

/// The dartboard, drawn in Relay's own palette (not the traditional red/green/black/cream,
/// and nothing borrowed from another app): sand and slate beds, Ember and Tide scoring rings.
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
            let scale = side / 2 / drawnRadius
            ZStack {
                Canvas { context, size in
                    drawBoard(in: &context, size: size, scale: scale)
                }
                .accessibilityHidden(true)
                ForEach(darts) { dart in
                    DartMarker(colour: palette.colour(dart.seat), animates: animatesDarts)
                        .frame(width: side * 0.055, height: side * 0.055)
                        .position(point(for: dart.hit, side: side, scale: scale))
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func point(for hit: Darts.Hit, side: CGFloat, scale: CGFloat) -> CGPoint {
        CGPoint(x: side / 2 + CGFloat(hit.x) * scale, y: side / 2 - CGFloat(hit.y) * scale)
    }

    private func drawBoard(in context: inout GraphicsContext, size: CGSize, scale: CGFloat) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        func circle(_ radius: Double) -> Path {
            let r = CGFloat(radius) * scale
            return Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
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
            let radius = CGFloat(Double(DartsBoard.doubleOuterRadius + 2_250) / 2) * scale
            let position = CGPoint(x: centre.x + radius * CGFloat(cos(angle)), y: centre.y + radius * CGFloat(sin(angle)))
            context.draw(
                Text("\(number)").font(.system(size: fontSize, weight: .bold, design: .rounded)).foregroundStyle(RelayTheme.textPrimary),
                at: position
            )
        }
    }
}

/// A dart's mark on the board. It thuds in where it landed: it starts larger and settles
/// in place, scaling about its own centre so it never appears to fly across the board.
/// It waits for the thrown dart's flight (`DartsThrowView.flightDuration`) to arrive.
private struct DartMarker: View {
    let colour: Color
    @State private var landed: Bool

    init(colour: Color, animates: Bool) {
        self.colour = colour
        _landed = State(initialValue: !animates)
    }

    var body: some View {
        ZStack {
            Circle().fill(colour)
            Circle().strokeBorder(Color.white, lineWidth: 1.5)
            Circle().fill(Color.white).frame(width: 3, height: 3)
        }
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        .scaleEffect(landed ? 1 : 2.4)
        .opacity(landed ? 1 : 0)
        .onAppear {
            withAnimation(.easeIn(duration: 0.12).delay(DartsThrowView.flightDuration)) { landed = true }
        }
    }
}

/// The throwing area: the board, with a dart held below it. Swipe the dart up to throw.
/// How hard you flick sets how high it flies and the line of the flick sets left and
/// right (`DartsAim.flickTarget`). The landing point is committed the moment the dart
/// leaves your hand; the flight is only animation. VoiceOver users get throw actions.
public struct DartsThrowView: View {
    let darts: [PlacedDart]
    let canThrow: Bool
    let suggestedTarget: DartsBoard.Segment?
    let onThrow: (Darts.Hit) -> Void

    /// Finger movement while the dart is held.
    @State private var hold: CGSize = .zero
    /// The dart in the air: where its tip is and how small it has got.
    @State private var flight: (tip: CGPoint, scale: CGFloat)?
    @State private var dartVisible = true

    /// Seconds from release to the dart hitting the board.
    static let flightDuration = 0.24
    /// Height of the area below the board where the dart is held, as a share of the board.
    private static let handHeight: CGFloat = 0.36

    public init(darts: [PlacedDart], canThrow: Bool, suggestedTarget: DartsBoard.Segment? = nil, onThrow: @escaping (Darts.Hit) -> Void) {
        self.darts = darts
        self.canThrow = canThrow
        self.suggestedTarget = suggestedTarget
        self.onThrow = onThrow
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height / (1 + Self.handHeight))
            let length = side * Self.handHeight * 0.8
            ZStack(alignment: .topLeading) {
                DartsBoardView(darts: darts)
                    .frame(width: side, height: side)
                if dartVisible {
                    ThrowingDart()
                        .frame(width: length * 0.3, height: length)
                        .scaleEffect(flight?.scale ?? 1, anchor: .top)
                        .position(dartCentre(side: side, length: length))
                        .opacity(canThrow || flight != nil ? 1 : 0.35)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(width: side, height: side * (1 + Self.handHeight))
            .contentShape(Rectangle())
            .gesture(throwGesture(side: side), including: canThrow ? .all : .subviews)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1 / (1 + Self.handHeight), contentMode: .fit)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: darts.count)
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

    private func dartCentre(side: CGFloat, length: CGFloat) -> CGPoint {
        // The tip is the top edge of the dart; scaling keeps the top fixed.
        let tip = flight?.tip ?? CGPoint(x: restingTip(side: side).x + hold.width, y: restingTip(side: side).y + hold.height)
        return CGPoint(x: tip.x, y: tip.y + length / 2)
    }

    private func throwGesture(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                // Only a swipe that starts on or below the bottom of the board picks up the dart.
                guard canThrow, flight == nil, value.startLocation.y > side * 0.85 else { return }
                hold = value.translation
            }
            .onEnded { value in
                guard canThrow, flight == nil, value.startLocation.y > side * 0.85 else {
                    hold = .zero
                    return
                }
                let target = DartsAim.flickTarget(
                    start: (Double(value.startLocation.x / side), Double(value.startLocation.y / side)),
                    release: (Double(value.location.x / side), Double(value.location.y / side)),
                    velocity: (Double(value.velocity.width / side), Double(value.velocity.height / side))
                )
                guard let target else {
                    withAnimation(.spring(duration: 0.3, bounce: 0.35)) { hold = .zero }
                    return
                }
                let aim = Darts.Hit(x: Int(((target.x - 0.5) * 2 * drawnRadius).rounded()), y: Int(((0.5 - target.y) * 2 * drawnRadius).rounded()))
                let speed = (value.velocity.width * value.velocity.width + value.velocity.height * value.velocity.height).squareRoot() / side
                var rng = SystemRandomNumberGenerator()
                let hit = DartsAim.landing(aim: aim, scatter: DartsAim.scatter(forSpeed: Double(speed)), using: &rng)
                fly(to: hit, side: side)
                onThrow(hit)
            }
    }

    /// Animates the dart from the hand to `hit`, then puts a fresh one back in hand.
    private func fly(to hit: Darts.Hit, side: CGFloat) {
        let scale = side / 2 / drawnRadius
        // Far misses still fly off the board, just not off the screen.
        let limit = drawnRadius * 1.2
        let x = min(max(Double(hit.x), -limit), limit), y = min(max(Double(hit.y), -limit), limit)
        let landing = CGPoint(x: side / 2 + x * scale, y: side / 2 - y * scale)
        let resting = restingTip(side: side)
        flight = (CGPoint(x: resting.x + hold.width, y: resting.y + hold.height), 1)
        hold = .zero
        withAnimation(.easeOut(duration: Self.flightDuration)) {
            flight = (landing, 0.3)
        } completion: {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                flight = nil
                dartVisible = false
            }
            withAnimation(.easeIn(duration: 0.2).delay(0.15)) { dartVisible = true }
        }
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

/// The dart in hand, drawn pointing up: steel point, slate barrel with Ember grip
/// bands, a thin shaft and Tide flights. Our own drawing, sized by its frame.
private struct ThrowingDart: View {
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

            var flights = Path()
            flights.move(to: CGPoint(x: mid, y: h * 0.62))
            flights.addLine(to: CGPoint(x: w, y: h * 0.9))
            flights.addLine(to: CGPoint(x: w * 0.92, y: h))
            flights.addLine(to: CGPoint(x: mid, y: h * 0.93))
            flights.addLine(to: CGPoint(x: w * 0.08, y: h))
            flights.addLine(to: CGPoint(x: 0, y: h * 0.9))
            flights.closeSubpath()
            context.fill(flights, with: .color(RelayTheme.disc(.two)))
            context.stroke(flights, with: .color(.black.opacity(0.35)), lineWidth: 1)

            context.fill(bar(0.56, 0.98, width: w * 0.1), with: .color(Color(white: 0.3)))
            context.fill(bar(0.22, 0.6, width: w * 0.3), with: .color(Color(red: 0.24, green: 0.27, blue: 0.36)))
            for band in [0.32, 0.4, 0.48] {
                context.fill(bar(band, band + 0.035, width: w * 0.3), with: .color(RelayTheme.disc(.one)))
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
    }
}

/// Three slots for the darts of a visit, then the visit total.
public struct DartsVisitStrip: View {
    let progress: Darts.VisitProgress
    let colour: Color

    public init(progress: Darts.VisitProgress, colour: Color) {
        self.progress = progress
        self.colour = colour
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<Darts.dartsPerVisit, id: \.self) { index in
                Text(index < progress.darts.count ? progress.darts[index].segment.shortName : "–")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(index < progress.darts.count ? RelayTheme.textPrimary : RelayTheme.textSecondary)
                    .frame(minWidth: 44)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(index < progress.darts.count ? colour.opacity(0.28) : RelayTheme.surface)
                    )
            }
            Spacer(minLength: 4)
            Text(summary)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(progress.result == .bust ? RelayTheme.disc(.one) : RelayTheme.textPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var summary: String {
        switch progress.result {
        case .bust: "Bust"
        case .finished: "Checkout!"
        case .scored: progress.darts.isEmpty ? "" : "+\(progress.points)"
        }
    }

    private var accessibilitySummary: String {
        guard !progress.darts.isEmpty else { return "No darts thrown yet this turn" }
        let names = progress.darts.map(\.segment.spokenName).joined(separator: ", ")
        switch progress.result {
        case .bust: return "\(names). Bust, nothing scored."
        case .finished: return "\(names). Checkout!"
        case .scored: return "\(names). \(progress.points) points, \(progress.remainingAfter) left."
        }
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
            Text("\(remaining(seat))")
                .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(RelayTheme.textPrimary)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: remaining(seat))
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
