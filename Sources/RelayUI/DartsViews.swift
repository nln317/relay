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
    /// Where the player is aiming, while they hold a dart.
    let reticle: Darts.Hit?
    @Environment(\.seatPalette) private var palette

    public init(darts: [PlacedDart], reticle: Darts.Hit? = nil) {
        self.darts = darts
        self.reticle = reticle
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
                    DartMarker(colour: palette.colour(dart.seat))
                        .frame(width: side * 0.055, height: side * 0.055)
                        .position(point(for: dart.hit, side: side, scale: scale))
                        .transition(.asymmetric(insertion: .scale(scale: 3).combined(with: .opacity), removal: .opacity))
                }
                if let reticle {
                    Reticle()
                        .frame(width: side * 0.12, height: side * 0.12)
                        .position(point(for: reticle, side: side, scale: scale))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeIn(duration: 0.18), value: darts)
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

private struct DartMarker: View {
    let colour: Color

    var body: some View {
        ZStack {
            Circle().fill(colour)
            Circle().strokeBorder(Color.white, lineWidth: 1.5)
            Circle().fill(Color.white).frame(width: 3, height: 3)
        }
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }
}

private struct Reticle: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.white, lineWidth: 2)
            Rectangle().fill(Color.white).frame(width: 2)
                .padding(.vertical, -6)
            Rectangle().fill(Color.white).frame(height: 2)
                .padding(.horizontal, -6)
        }
        .shadow(color: .black.opacity(0.6), radius: 2)
    }
}

/// The interactive throwing area: drag anywhere on the board to aim (the sight sits a
/// little above your finger so you can see it), hold steady, let go to throw. The sight
/// drifts gently, more the longer you hold. VoiceOver users get aim-and-throw actions.
public struct DartsThrowView: View {
    let darts: [PlacedDart]
    let canThrow: Bool
    let suggestedTarget: DartsBoard.Segment?
    let onThrow: (Darts.Hit) -> Void

    @State private var aim: Darts.Hit?
    @State private var heldSince: Date?
    @State private var phase = 0.0

    public init(darts: [PlacedDart], canThrow: Bool, suggestedTarget: DartsBoard.Segment? = nil, onThrow: @escaping (Darts.Hit) -> Void) {
        self.darts = darts
        self.canThrow = canThrow
        self.suggestedTarget = suggestedTarget
        self.onThrow = onThrow
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let scale = side / 2 / drawnRadius
            TimelineView(.animation(minimumInterval: 1 / 60, paused: heldSince == nil)) { timeline in
                DartsBoardView(darts: darts, reticle: reticle(at: timeline.date))
                    .frame(width: side, height: side)
                    .contentShape(Rectangle())
                    .gesture(aimGesture(side: side, scale: scale), including: canThrow ? .all : .subviews)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: darts.count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(canThrow ? "Use the actions to aim and throw a dart." : "")
        .accessibilityActions {
            if canThrow {
                ForEach(accessibilityTargets, id: \.self) { target in
                    Button("Throw at \(target.spokenName)") { throwAt(target) }
                }
            }
        }
    }

    private func reticle(at date: Date) -> Darts.Hit? {
        guard let aim, let heldSince else { return nil }
        let sway = DartsAim.sway(heldFor: date.timeIntervalSince(heldSince), phase: phase)
        return Darts.Hit(x: aim.x + sway.x, y: aim.y + sway.y)
    }

    private func aimGesture(side: CGFloat, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canThrow else { return }
                if heldSince == nil {
                    heldSince = Date()
                    phase = Double.random(in: 0..<(2 * .pi))
                }
                // The sight sits above the fingertip so the finger never hides it.
                let lift = side * 0.16
                let x = (value.location.x - side / 2) / scale
                let y = (side / 2 - (value.location.y - lift)) / scale
                aim = Darts.Hit(x: Int(x.rounded()), y: Int(y.rounded()))
            }
            .onEnded { _ in
                defer {
                    aim = nil
                    heldSince = nil
                }
                guard canThrow, let target = reticle(at: Date()) else { return }
                var rng = SystemRandomNumberGenerator()
                onThrow(DartsAim.landing(aim: target, scatter: DartsAim.releaseScatter, using: &rng))
            }
    }

    private func throwAt(_ segment: DartsBoard.Segment) {
        var rng = SystemRandomNumberGenerator()
        // Without a steady-hand sway to beat, VoiceOver throws use a slightly wider scatter.
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
            DartsBoardView(darts: lastVisitDarts)
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
