#if canImport(UIKit)
import RelayCore
import SwiftUI

/// Interim visual identity. On 2026-10-04 Nathan chose to match the classic iMessage
/// games' look first (red and yellow players, D-031) and re-skin later, so these
/// values are expected to change wholesale (docs/DECISIONS.md, D-010).
public enum RelayTheme {
    public static let background = Color(red: 0.06, green: 0.07, blue: 0.11)
    public static let surface = Color(red: 0.11, green: 0.12, blue: 0.18)
    public static let board = Color(red: 0.16, green: 0.19, blue: 0.30)
    public static let boardEdge = Color(red: 0.24, green: 0.28, blue: 0.42)
    public static let hole = Color(red: 0.05, green: 0.06, blue: 0.10)
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.65)
    public static let accent = Color(red: 0.55, green: 0.48, blue: 1.0)

    /// Seat colours are the same on both devices so the bubble image reads the same.
    public static func disc(_ seat: Seat) -> Color {
        switch seat {
        case .one: Color(red: 0.89, green: 0.13, blue: 0.15) // red
        case .two: Color(red: 0.98, green: 0.80, blue: 0.08) // yellow
        }
    }

    /// Lit and shaded tones of each seat colour, for the moulded disc look.
    static func discLight(_ seat: Seat) -> Color {
        switch seat {
        case .one: Color(red: 1.0, green: 0.45, blue: 0.42)
        case .two: Color(red: 1.0, green: 0.95, blue: 0.55)
        }
    }

    static func discDark(_ seat: Seat) -> Color {
        switch seat {
        case .one: Color(red: 0.6, green: 0.05, blue: 0.07)
        case .two: Color(red: 0.8, green: 0.58, blue: 0.0)
        }
    }

    public static func discName(_ seat: Seat) -> String {
        switch seat {
        case .one: "Red"
        case .two: "Yellow"
        }
    }
}

/// Which colour and mark each seat wears in the match on screen. Rematches renumber
/// seats, so the header's `coloursSwapped` keeps each person's colour (D-024).
public struct SeatPalette: Equatable, Sendable {
    public var coloursSwapped: Bool

    public init(coloursSwapped: Bool = false) {
        self.coloursSwapped = coloursSwapped
    }

    /// The seat whose base colour and mark `seat` wears.
    public func look(_ seat: Seat) -> Seat {
        coloursSwapped ? seat.opponent : seat
    }

    public func colour(_ seat: Seat) -> Color { RelayTheme.disc(look(seat)) }
    public func name(_ seat: Seat) -> String { RelayTheme.discName(look(seat)) }
}

extension EnvironmentValues {
    @Entry public var seatPalette = SeatPalette()
}

/// A disc with a shape mark as well as a colour, so seats are distinguishable
/// without colour vision (ring for Red, dot for Yellow).
public struct DiscView: View {
    let seat: Seat
    var isHighlighted: Bool = false
    var isDimmed: Bool = false
    @Environment(\.seatPalette) private var palette

    public init(seat: Seat, isHighlighted: Bool = false, isDimmed: Bool = false) {
        self.seat = seat
        self.isHighlighted = isHighlighted
        self.isDimmed = isDimmed
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let look = palette.look(seat)
            ZStack {
                // A moulded plastic disc: lit from the top left, with a raised rim and
                // grooves, plus a centre mark (ring or dot) so seats differ without colour.
                Circle()
                    .fill(RadialGradient(
                        colors: [RelayTheme.discLight(look), RelayTheme.disc(look), RelayTheme.discDark(look)],
                        center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.75
                    ))
                Circle()
                    .strokeBorder(RelayTheme.discDark(look), lineWidth: max(1, size * 0.05))
                Circle()
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: max(1, size * 0.03))
                    .padding(size * 0.14)
                Circle()
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: max(0.5, size * 0.02))
                    .padding(size * 0.17)
                switch look {
                case .one:
                    Circle()
                        .strokeBorder(Color.black.opacity(0.2), lineWidth: max(1, size * 0.04))
                        .padding(size * 0.32)
                case .two:
                    Circle()
                        .fill(Color.black.opacity(0.18))
                        .frame(width: size * 0.16, height: size * 0.16)
                }
                if isHighlighted {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: max(2, size * 0.08))
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .opacity(isDimmed ? 0.4 : 1)
        .accessibilityHidden(true)
    }
}
#endif
