import Foundation
import Messages
import Observation
import RelayAnalytics
import RelayCore
import RelayGames
import RelayMessages
import RelayUI

/// UI state for the extension. Owns the `ConversationController`; asks the view
/// controller to do anything that needs the Messages framework.
@MainActor
@Observable
final class ExtensionModel {
    enum Request {
        case expand
        case insert(OutgoingMessage)
    }

    var screen: ConversationScreen = .picker
    var presentationStyle: MSMessagesAppPresentationStyle = .compact
    var isWorking = false
    var errorText: String?

    @ObservationIgnored let analytics: AnalyticsSink = NoOpAnalytics()
    @ObservationIgnored let controller: ConversationController
    @ObservationIgnored var perform: (Request) -> Void = { _ in }

    /// Delay between the disc landing and collapsing to the compose field, so the
    /// player sees their move land before the extension gets out of the way.
    @ObservationIgnored private let insertDelay: Duration = .milliseconds(450)
    /// The screen before an optimistic move, restored if inserting fails.
    @ObservationIgnored private var screenBeforeInsert: ConversationScreen?

    init() {
        controller = ConversationController(store: FileLedgerStore(fileURL: SharedStorage.ledgerURL), analytics: analytics)
    }

    var currentMatchID: MatchID? {
        if case .play(let session) = screen { return session.snapshot.matchID }
        return nil
    }

    // MARK: Intents

    func select(_ game: GameDefinition) {
        guard let start = controller.startMatch(game: game.id) else {
            errorText = "That game isn't available in this version."
            return
        }
        begin(start)
    }

    func rematch() {
        guard case .play(let session) = screen else { return }
        do {
            begin(try controller.startRematch(from: session))
        } catch {
            errorText = "Couldn't start a rematch."
        }
    }

    func newGame() {
        screen = .picker
    }

    func expand() {
        perform(.expand)
    }

    func play(column: Int) {
        guard !isWorking, case .play(let session) = screen else { return }
        do {
            let outgoing = try controller.prepareMove(.fourInARow(.init(column: column)), in: session)
            screenBeforeInsert = screen
            // Show the move landing immediately; the board is now read-only until
            // the message is sent or the draft is reopened.
            screen = .play(PlaySession(
                snapshot: outgoing.snapshot,
                localSeat: session.localSeat,
                mode: .readyToSend(pending: outgoing.snapshot),
                knownRematch: nil
            ))
            isWorking = true
            Task { @MainActor in
                try? await Task.sleep(for: insertDelay)
                isWorking = false
                perform(.insert(outgoing))
            }
        } catch {
            errorText = "That move isn't allowed."
        }
    }

    func markInserted(_ outgoing: OutgoingMessage) {
        errorText = nil
        screenBeforeInsert = nil
    }

    /// Messages refused the insert: put the board back so the player can try again.
    func insertFailed(_ message: String) {
        errorText = message
        if let previous = screenBeforeInsert { screen = previous }
        screenBeforeInsert = nil
    }

    private func begin(_ start: ConversationController.NewMatch) {
        switch start {
        case .play(let session):
            screen = .play(session)
            perform(.expand)
        case .insert(let outgoing):
            perform(.insert(outgoing))
        }
    }
}

enum SharedStorage {
    /// Must match the App Group in both targets' entitlements.
    static let appGroup = "group.dev.relay.shared"

    static var ledgerURL: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Relay", isDirectory: true).appendingPathComponent("ledger-v1.json")
    }
}
