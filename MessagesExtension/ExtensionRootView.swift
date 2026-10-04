import Messages
import RelayCore
import RelayGames
import RelayMessages
import RelayUI
import SwiftUI

struct ExtensionRootView: View {
    @Bindable var model: ExtensionModel

    var body: some View {
        ZStack(alignment: .bottom) {
            RelayTheme.background.ignoresSafeArea()
            content
            if let error = model.errorText {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
                    .padding(.bottom, 12)
                    .onTapGesture { model.errorText = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: model.errorText)
    }

    @ViewBuilder
    private var content: some View {
        switch model.screen {
        case .picker:
            GamePickerView { model.select($0) }
        case .problem(let error):
            ProblemView(error: error, onNewGame: model.newGame)
        case .play(let session):
            if model.presentationStyle == .compact {
                CompactSessionCard(session: session, onOpen: model.expand)
            } else {
                PlayScreen(
                    session: session,
                    onColumn: { model.play(column: $0) },
                    onRematch: model.rematch,
                    onNewGame: model.newGame
                )
            }
        }
    }
}

/// In the compact drawer the board would be cramped, so show a summary and one
/// button that expands to the full board.
struct CompactSessionCard: View {
    let session: PlaySession
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(GameCatalog.definition(for: session.snapshot.gameID)?.displayName ?? "Game")
                .font(.title3.weight(.bold))
                .foregroundStyle(RelayTheme.textPrimary)
            Text(status)
                .font(.subheadline)
                .foregroundStyle(RelayTheme.textSecondary)
            Button(session.mode == .yourTurn ? "Play your move" : "Open board", action: onOpen)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 32)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var status: String {
        switch session.mode {
        case .yourTurn: "Your move"
        case .waitingForOpponent: "Waiting for their move"
        case .readyToSend: "Your move is ready. Tap send."
        case .finished: "Game over"
        }
    }
}
