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

    private var columns: Int { state.configuration.columns }
    private var rows: Int { state.configuration.rows }

    public var body: some View {
        GeometryReader { proxy in
            let cell = min(proxy.size.width / CGFloat(columns), proxy.size.height / CGFloat(rows))
            let width = cell * CGFloat(columns)
            let height = cell * CGFloat(rows)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cell * 0.28, style: .continuous)
                    .fill(RelayTheme.board)
                    .overlay(
                        RoundedRectangle(cornerRadius: cell * 0.28, style: .continuous)
                            .strokeBorder(RelayTheme.boardEdge, lineWidth: 2)
                    )

                ForEach(0..<columns, id: \.self) { column in
                    ForEach(0..<rows, id: \.self) { row in
                        Circle()
                            .fill(RelayTheme.hole)
                            .frame(width: cell * 0.78, height: cell * 0.78)
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
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(CGFloat(columns) / CGFloat(rows), contentMode: .fit)
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
    /// e.g. "Column 3: you, them, you. 3 spaces free".
    private func columnLabel(_ column: Int) -> String {
        let filled = state.height(ofColumn: column)
        let free = rows - filled
        let discs = (0..<filled).compactMap { row -> String? in
            let cell = FourInARow.Cell(column: column, row: row)
            guard let seat = state.disc(at: cell) else { return nil }
            let name = discName(seat)
            return state.winningCells.contains(cell) ? "\(name), winning" : name
        }
        let contents = discs.isEmpty ? "empty" : discs.joined(separator: ", ")
        let room = free == 0 ? "full" : free == 1 ? "1 space free" : "\(free) spaces free"
        return "Column \(column + 1): \(contents). \(room)"
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

    var body: some View {
        DiscView(seat: seat, isHighlighted: isHighlighted, isDimmed: isDimmed)
            .scaleEffect(isHighlighted && pulse ? 1.08 : 1)
            .offset(y: animates && !landed ? -dropDistance : 0)
            .onAppear {
                if animates {
                    withAnimation(.interpolatingSpring(stiffness: 260, damping: 17)) {
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
public struct FourInARowBubbleArt: View {
    let state: FourInARow.State
    let palette: SeatPalette

    public init(state: FourInARow.State, palette: SeatPalette = SeatPalette()) {
        self.state = state
        self.palette = palette
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [RelayTheme.surface, RelayTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            FourInARowBoardView(state: state, isInteractive: false, animatesLastMove: false)
                .padding(18)
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
