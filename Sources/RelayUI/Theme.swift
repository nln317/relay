#if canImport(UIKit)
import RelayCore
import SwiftUI

/// Placeholder visual identity for Milestone 1. Original, deliberately not
/// GamePigeon's palette (no red/yellow-on-blue board). Milestone 4 replaces it
/// with a full design system (docs/DECISIONS.md, D-010).
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
        case .one: Color(red: 1.0, green: 0.42, blue: 0.36) // ember
        case .two: Color(red: 0.20, green: 0.84, blue: 0.76) // tide
        }
    }

    public static func discName(_ seat: Seat) -> String {
        switch seat {
        case .one: "Ember"
        case .two: "Tide"
        }
    }
}

/// A disc with a shape mark as well as a colour, so seats are distinguishable
/// without colour vision (ring for seat one, dot for seat two).
public struct DiscView: View {
    let seat: Seat
    var isHighlighted: Bool = false
    var isDimmed: Bool = false

    public init(seat: Seat, isHighlighted: Bool = false, isDimmed: Bool = false) {
        self.seat = seat
        self.isHighlighted = isHighlighted
        self.isDimmed = isDimmed
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [RelayTheme.disc(seat).opacity(1), RelayTheme.disc(seat).opacity(0.78)],
                            center: .init(x: 0.35, y: 0.3),
                            startRadius: 0,
                            endRadius: size * 0.7
                        )
                    )
                switch seat {
                case .one:
                    Circle()
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: max(1.5, size * 0.07))
                        .padding(size * 0.2)
                case .two:
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: size * 0.22, height: size * 0.22)
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
