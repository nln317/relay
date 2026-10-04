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
                    onInput: { model.handle($0) },
                    onRematch: model.rematch,
                    onNewGame: model.newGame
                )
            }
        }
    }
}

/// In the compact drawer the board would be cramped, so show the game's picture (the
/// same one as the bubble) and one big button that expands to the full board.
struct CompactSessionCard: View {
    let session: PlaySession
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            GameSnapshotArt(snapshot: session.snapshot)
                .scaleEffect(0.5)
                .frame(width: 150, height: 112.5)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text(status.uppercased())
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Button(session.mode == .yourTurn ? "Play" : "Open", action: onOpen)
                    .buttonStyle(GameButtonStyle())
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.1).ignoresSafeArea())
    }

    private var status: String {
        switch session.mode {
        case .yourTurn: "Your turn"
        case .waitingForOpponent: "Waiting for opponent..."
        case .readyToSend: "Tap send to finish your turn"
        case .finished: "Game over"
        }
    }
}
