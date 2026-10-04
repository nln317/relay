#if DEBUG
import Foundation
import Observation
import RelayCore
import RelayGames
import RelayMessages
import RelayUI
import SwiftUI

/// Debug-only stand-in for a two-phone Messages conversation.
///
/// Two `ConversationController`s, each with its own ledger, share an in-memory
/// transcript, and the real `PlayScreen` renders whichever "phone" is selected. It runs
/// the exact logic and views the extension uses, minus the Messages framework, so the
/// receiving player's screens can be checked in the simulator without a second device.
/// It is not evidence of real Messages behaviour (docs/TESTING.md).
@MainActor
@Observable
final class RehearsalModel {
    struct Bubble: Identifiable {
        let id = UUID()
        let url: URL
        let sender: Int
        let caption: MessageCaption
        let image: UIImage?
    }

    let names = ["Ava", "Ben"]
    private(set) var transcript: [Bubble] = []
    private(set) var viewer = 0
    private(set) var screen: ConversationScreen = .picker
    private(set) var lastError: String?
    @ObservationIgnored private let controllers = [
        ConversationController(store: InMemoryLedgerStore()),
        ConversationController(store: InMemoryLedgerStore()),
    ]

    private var controller: ConversationController { controllers[viewer] }

    func selectViewer(_ index: Int) {
        viewer = index
        // The other phone opens the newest bubble, like tapping it in the transcript.
        if let last = transcript.last { open(last) } else { screen = .picker }
    }

    func open(_ bubble: Bubble) {
        screen = controller.screen(for: OpenedMessage(url: bubble.url, senderIsLocal: bubble.sender == viewer, isPending: false))
    }

    func start() {
        guard let start = controller.startMatch(game: FourInARow.gameID) else { return }
        handle(start)
    }

    func play(column: Int) {
        guard case .play(let session) = screen else { return }
        do {
            send(try controller.prepareMove(.fourInARow(.init(column: column)), in: session))
        } catch {
            lastError = String(describing: error)
        }
    }

    func rematch() {
        guard case .play(let session) = screen else { return }
        do {
            handle(try controller.startRematch(from: session))
        } catch {
            lastError = String(describing: error)
        }
    }

    func newGame() {
        screen = .picker
    }

    /// Opens a deliberately broken message on the current phone.
    func openDamaged(newerVersion: Bool) {
        let raw = newerVersion
            ? "https://relay.invalid/play?v=9&g=four-in-a-row&p=e30"
            : "https://relay.invalid/play?v=1&g=four-in-a-row&p=bm9wZQ"
        guard let url = URL(string: raw) else { return }
        screen = controller.screen(for: OpenedMessage(url: url, senderIsLocal: false, isPending: false))
    }

    private func handle(_ start: ConversationController.NewMatch) {
        switch start {
        case .play(let session): screen = .play(session)
        case .insert(let outgoing): send(outgoing)
        }
    }

    /// Insert and send in one step: the sending side of Messages is covered elsewhere.
    private func send(_ outgoing: OutgoingMessage) {
        controller.didInsert(outgoing)
        controller.didStartSending(url: outgoing.url)
        var image: UIImage?
        if case .fourInARow(let snapshot) = outgoing.snapshot {
            image = BubbleImageRenderer.image(for: snapshot.match)
        }
        let bubble = Bubble(url: outgoing.url, sender: viewer, caption: outgoing.caption, image: image)
        transcript.append(bubble)
        open(bubble)
    }
}

struct RehearsalView: View {
    @State private var model = RehearsalModel()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Phone", selection: Binding(get: { model.viewer }, set: { model.selectViewer($0) })) {
                ForEach(0..<2, id: \.self) { index in
                    Text("\(model.names[index])'s phone").tag(index)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)
            .accessibilityIdentifier("rehearsal.phone")

            Group {
                switch model.screen {
                case .picker:
                    GamePickerView { _ in model.start() }
                case .problem(let error):
                    ProblemView(error: error, onNewGame: model.newGame)
                case .play(let session):
                    PlayScreen(session: session, onColumn: model.play(column:), onRematch: model.rematch, onNewGame: model.newGame)
                }
            }
            .frame(maxHeight: .infinity)

            transcriptStrip
        }
        .background(RelayTheme.background.ignoresSafeArea())
        .navigationTitle("Two-phone rehearsal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu("Edge cases") {
                Button("Open a damaged message") { model.openDamaged(newerVersion: false) }
                Button("Open a message from a newer version") { model.openDamaged(newerVersion: true) }
            }
        }
    }

    private var transcriptStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.transcript.enumerated()), id: \.element.id) { index, bubble in
                    Button {
                        model.open(bubble)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            if let image = bubble.image {
                                Image(uiImage: image).resizable().scaledToFit().frame(height: 44)
                            }
                            Text("\(index + 1). \(model.names[bubble.sender])")
                                .font(.caption2.weight(.bold))
                            Text(bubble.caption.subcaption ?? "")
                                .font(.caption2)
                        }
                        .foregroundStyle(RelayTheme.textPrimary)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(bubble.sender == model.viewer ? RelayTheme.accent.opacity(0.5) : RelayTheme.surface)
                        )
                    }
                    .accessibilityIdentifier("rehearsal.bubble.\(index + 1)")
                }
            }
            .padding(12)
        }
        .frame(height: 104)
        .background(RelayTheme.surface.opacity(0.5))
    }
}
#endif
