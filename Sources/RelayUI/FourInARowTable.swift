#if canImport(UIKit)
import RelayCore
import RelayGames
import SwiftUI

/// The whole Four in a Row screen, laid out like the classic iMessage game (D-031): a
/// light grey backdrop, the players at the top (avatar and disc each, "You" on the left),
/// the blue board in the middle, help bottom left and a settings menu bottom right.
public struct FourInARowTable<MenuItems: View, Footer: View>: View {
    let state: FourInARow.State
    let localSeat: Seat?
    let ghost: (cell: FourInARow.Cell, seat: Seat)?
    let canMove: Bool
    let banner: DartsBanner?
    let notices: [String]
    let onColumnTap: (Int) -> Void
    let menuItems: MenuItems
    let footer: Footer
    @State private var showingRules = false
    @Environment(\.seatPalette) private var palette

    /// - Parameters:
    ///   - localSeat: whose device this is; nil for pass and play.
    ///   - ghost: a move chosen but not sent yet, drawn see-through.
    public init(
        state: FourInARow.State,
        localSeat: Seat?,
        ghost: (cell: FourInARow.Cell, seat: Seat)? = nil,
        canMove: Bool,
        banner: DartsBanner?,
        notices: [String] = [],
        onColumnTap: @escaping (Int) -> Void,
        @ViewBuilder menuItems: () -> MenuItems,
        @ViewBuilder footer: () -> Footer
    ) {
        self.state = state
        self.localSeat = localSeat
        self.ghost = ghost
        self.canMove = canMove
        self.banner = banner
        self.notices = notices
        self.onColumnTap = onColumnTap
        self.menuItems = menuItems()
        self.footer = footer()
    }

    public var body: some View {
        VStack(spacing: 0) {
            players
                .padding(.horizontal, 16)
                .padding(.top, 8)
            ForEach(notices, id: \.self) { notice in
                Text(notice)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(.top, 6)
            }
            Spacer(minLength: 12)
            FourInARowBoardView(
                state: state,
                ghost: ghost,
                isInteractive: canMove,
                animatesLastMove: true,
                localSeat: localSeat,
                onColumnTap: onColumnTap
            )
            .overlay {
                if let banner {
                    GameBannerView(banner: banner)
                        .padding(.horizontal, 36)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 22)
            Spacer(minLength: 12)
            footer
                .padding(.bottom, 8)
            HStack {
                Button { showingRules = true } label: {
                    roundIcon("questionmark")
                }
                .accessibilityLabel("How to play")
                Spacer()
                Menu { menuItems } label: { roundIcon("gearshape.fill") }
                    .accessibilityLabel("Menu")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(white: 0.86), Color(white: 0.74)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .environment(\.colorScheme, .light)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: banner)
        .alert("How to play", isPresented: $showingRules) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Take turns dropping a disc into a column. The first to line up four of their discs across, up and down, or diagonally wins.")
        }
    }

    private var players: some View {
        let left = localSeat ?? .one
        return HStack(alignment: .bottom) {
            HStack(spacing: 10) {
                badge(left)
                disc(left)
            }
            Spacer()
            HStack(spacing: 10) {
                disc(left.opponent)
                badge(left.opponent)
            }
        }
    }

    private func badge(_ seat: Seat) -> some View {
        let toAct = state.outcome.seatToAct == seat
        let wins = state.outcome.winner == seat
        return VStack(spacing: 2) {
            Text(label(for: seat) ?? " ")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Color(white: 0.1))
            ZStack {
                Capsule().fill(Color.black.opacity(0.88))
                Image(systemName: "person.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(palette.colour(seat))
            }
            .frame(width: 66, height: 52)
            .overlay(Capsule().strokeBorder(toAct ? Color.white : .clear, lineWidth: 3))
            .shadow(color: wins ? Color.yellow : .black.opacity(0.25), radius: wins ? 12 : 3, y: wins ? 0 : 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label(for: seat) ?? "Them")\(toAct ? ", to move" : "")\(wins ? ", winner" : "")")
    }

    private func disc(_ seat: Seat) -> some View {
        DiscView(seat: seat)
            .frame(width: 44, height: 44)
            .opacity(state.outcome.seatToAct == seat || state.outcome.isFinished ? 1 : 0.55)
            .scaleEffect(state.outcome.seatToAct == seat ? 1.06 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: state.outcome.seatToAct)
    }

    private func label(for seat: Seat) -> String? {
        guard let localSeat else { return palette.name(seat) }
        return seat == localSeat ? "You" : nil
    }

    private func roundIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .heavy))
            .foregroundStyle(Color(white: 0.45))
            .frame(width: 46, height: 46)
            .background(Circle().fill(Color.white.opacity(0.9)))
            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
    }
}

/// A banner across the board: dark for information, yellow for a win.
struct GameBannerView: View {
    let banner: DartsBanner

    var body: some View {
        switch banner {
        case .info(let text):
            Text(text.uppercased())
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(red: 0.05, green: 0.1, blue: 0.2).opacity(0.85)))
        case .celebration(let text):
            Text(text.uppercased())
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(Color(white: 0.08))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.vertical, 8)
                .padding(.horizontal, 28)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(red: 1.0, green: 0.88, blue: 0.1)))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        }
    }
}
#endif
