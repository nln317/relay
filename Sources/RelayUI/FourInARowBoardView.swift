#if canImport(UIKit)
import RelayCore
import RelayGames
import SwiftUI

/// The Four in a Row board. Pure presentation: it never decides legality, it
/// only reports which column was tapped.
public struct FourInARowBoardView: View {
    public let state: FourInARow.State
    /// A move that is chosen but not sent, drawn translucent on top of `state`.
    public var ghost: (cell: FourInARow.Cell, seat: Seat)?
    public var isInteractive: Bool
    /// Animates the most recent disc falling into place (used when opening a turn,
    /// so the opponent's move is replayed rather than appearing silently).
    public var animatesLastMove: Bool
    /// Whose point of view VoiceOver describes discs from ("you"/"them"); nil names colours.
    public var localSeat: Seat?
    public var onColumnTap: (Int) -> Void
    @Environment(\.seatPalette) private var palette

    public init(
        state: FourInARow.State,
        ghost: (cell: FourInARow.Cell, seat: Seat)? = nil,
        isInteractive: Bool,
        animatesLastMove: Bool = true,
        localSeat: Seat? = nil,
        onColumnTap: @escaping (Int) -> Void = { _ in }
    ) {
        self.state = state
        self.ghost = ghost
        self.isInteractive = isInteractive
        self.animatesLastMove = animatesLastMove
        self.localSeat = localSeat
        self.onColumnTap = onColumnTap
    }

    /// Height of the lip under the holes, in cells.
    private static var lip: CGFloat { 0.35 }

    private var columns: Int { state.configuration.columns }
    private var rows: Int { state.configuration.rows }

    public var body: some View {
        GeometryReader { proxy in
            let cell = min(proxy.size.width / CGFloat(columns), proxy.size.height / (CGFloat(rows) + Self.lip))
            let width = cell * CGFloat(columns)
            let height = cell * CGFloat(rows)
            ZStack(alignment: .topLeading) {
                // A glossy blue frame with a raised lip along the bottom.
                RoundedRectangle(cornerRadius: cell * 0.1, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.36, blue: 0.72), Color(red: 0.08, green: 0.27, blue: 0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(width: width, height: height + cell * Self.lip)
                    .shadow(color: .black.opacity(0.35), radius: cell * 0.25, y: cell * 0.18)
                RoundedRectangle(cornerRadius: cell * 0.1, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.32, green: 0.6, blue: 0.93), Color(red: 0.16, green: 0.46, blue: 0.86)], startPoint: .top, endPoint: .bottom))
                    .frame(width: width, height: height)
                Rectangle()
                    .fill(LinearGradient(colors: [Color.black.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: width, height: cell * 0.12)
                    .offset(y: height)

                ForEach(0..<columns, id: \.self) { column in
                    ForEach(0..<rows, id: \.self) { row in
                        Circle()
                            .fill(RadialGradient(colors: [Color(red: 0.06, green: 0.2, blue: 0.45), Color(red: 0.03, green: 0.13, blue: 0.33)], center: .init(x: 0.5, y: 0.35), startRadius: 0, endRadius: cell * 0.45))
                            .overlay(Circle().strokeBorder(LinearGradient(colors: [Color.black.opacity(0.35), Color.white.opacity(0.25)], startPoint: .top, endPoint: .bottom), lineWidth: max(1, cell * 0.04)))
                            .frame(width: cell * 0.76, height: cell * 0.76)
                            .position(center(column: column, row: row, cell: cell))
                    }
                }

                ForEach(placedDiscs, id: \.cell) { disc in
                    FallingDisc(
                        seat: disc.seat,
                        dropDistance: dropDistance(for: disc.cell, cell: cell),
                        animates: animatesLastMove && disc.cell == state.lastMove,
                        isHighlighted: state.winningCells.contains(disc.cell),
                        isDimmed: state.outcome.winner != nil && !state.winningCells.contains(disc.cell)
                    )
                    .frame(width: cell * 0.8, height: cell * 0.8)
                    .position(center(column: disc.cell.column, row: disc.cell.row, cell: cell))
                }

                if let ghost {
                    DiscView(seat: ghost.seat)
                        .frame(width: cell * 0.8, height: cell * 0.8)
                        .opacity(0.45)
                        .position(center(column: ghost.cell.column, row: ghost.cell.row, cell: cell))
                }

                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        Button {
                            onColumnTap(column)
                        } label: {
                            Color.clear.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!isInteractive || !state.isColumnOpen(column))
                        .accessibilityLabel(columnLabel(column))
                        .accessibilityHint(isInteractive && state.isColumnOpen(column) ? "Drops a disc" : "")
                    }
                }
                .frame(width: width, height: height)
            }
            .frame(width: width, height: height + cell * Self.lip, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(CGFloat(columns) / (CGFloat(rows) + Self.lip), contentMode: .fit)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: state.movesPlayed)
        .sensoryFeedback(.success, trigger: state.outcome.isFinished)
    }

    private struct PlacedDisc {
        var cell: FourInARow.Cell
        var seat: Seat
    }

    private var placedDiscs: [PlacedDisc] {
        var result: [PlacedDisc] = []
        for column in 0..<columns {
            for row in 0..<rows {
                let cell = FourInARow.Cell(column: column, row: row)
                if let seat = state.disc(at: cell) {
                    result.append(PlacedDisc(cell: cell, seat: seat))
                }
            }
        }
        return result
    }

    private func center(column: Int, row: Int, cell: CGFloat) -> CGPoint {
        CGPoint(
            x: (CGFloat(column) + 0.5) * cell,
            y: (CGFloat(rows - 1 - row) + 0.5) * cell
        )
    }

    private func dropDistance(for target: FourInARow.Cell, cell: CGFloat) -> CGFloat {
        CGFloat(rows - target.row) * cell
    }

    /// VoiceOver reads each column's discs bottom to top, then how much room is left,
    /// e.g. "Column 3: you, them, you. 3 spaces free."
    private func columnLabel(_ column: Int) -> String {
        let filled = state.height(ofColumn: column)
        let free = rows - filled
        let discs = (0..<filled).compactMap { row in
            state.disc(at: FourInARow.Cell(column: column, row: row)).map(discName)
        }
        let contents = discs.isEmpty ? "empty" : discs.joined(separator: ", ")
        let room = free == 0 ? "full" : free == 1 ? "1 space free" : "\(free) spaces free"
        let winning = state.winningCells.contains { $0.column == column } ? " Part of the winning line." : ""
        return "Column \(column + 1): \(contents). \(room).\(winning)"
    }

    private func discName(_ seat: Seat) -> String {
        guard let localSeat else { return palette.name(seat) }
        return seat == localSeat ? "you" : "them"
    }
}

/// A disc that falls from above the board and settles with a small bounce.
private struct FallingDisc: View {
    let seat: Seat
    let dropDistance: CGFloat
    let animates: Bool
    let isHighlighted: Bool
    let isDimmed: Bool
    @State private var landed = false
    @State private var pulse = false

    /// Longer drops take longer, roughly like gravity (time grows with the square root of distance).
    private var fallDuration: Double {
        max(0.14, 0.11 * Double(dropDistance / 40).squareRoot())
    }

    var body: some View {
        DiscView(seat: seat, isHighlighted: isHighlighted, isDimmed: isDimmed)
            .scaleEffect(isHighlighted && pulse ? 1.08 : 1)
            .offset(y: animates && !landed ? -dropDistance : 0)
            .onAppear {
                if animates {
                    // Accelerates like a falling disc and stops dead in its slot; a spring
                    // overshot the slot and bounced back through the disc below.
                    withAnimation(.timingCurve(0.55, 0, 1, 0.45, duration: fallDuration)) {
                        landed = true
                    }
                } else {
                    landed = true
                }
                if isHighlighted {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(0.35)) {
                        pulse = true
                    }
                }
            }
    }
}

/// Static board art for the message bubble image. No animation, no interaction.
/// The dark strip along the bottom of a bubble picture, in white capitals: "YOUR TURN",
/// like the classic iMessage games' bubbles (D-031). The same picture is shown on both
/// sides, so it speaks to whoever has to move next.
struct BubbleStrip: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(Color(white: 0.12))
    }
}

public struct FourInARowBubbleArt: View {
    let state: FourInARow.State
    let palette: SeatPalette

    public init(state: FourInARow.State, palette: SeatPalette = SeatPalette()) {
        self.state = state
        self.palette = palette
    }

    private var caption: String {
        if state.outcome.isFinished { return "Game over" }
        let started = state.discs.contains { $0.contains { $0 != nil } }
        return started ? "Your turn" : "Let's play Four in a Row!"
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color(white: 0.88), Color(white: 0.74)], startPoint: .top, endPoint: .bottom)
                FourInARowBoardView(state: state, isInteractive: false, animatesLastMove: false)
                    .padding(14)
            }
            BubbleStrip(text: caption)
        }
        .frame(width: 300, height: 225)
        .environment(\.seatPalette, palette)
    }
}

@MainActor
public enum BubbleImageRenderer {
    /// Renders the bubble image. Returns nil rather than failing the move: Messages
    /// still shows caption text without an image.
    public static func image(for match: Match<FourInARow>) -> UIImage? {
        let palette = SeatPalette(coloursSwapped: match.header.coloursSwapped)
        let renderer = ImageRenderer(content: FourInARowBubbleArt(state: match.state, palette: palette))
        renderer.scale = 3
        return renderer.uiImage
    }
}
#endif
