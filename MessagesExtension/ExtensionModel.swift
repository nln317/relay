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
    /// Longer for Darts, so the visit total can be read before the sheet collapses.
    @ObservationIgnored private let visitInsertDelay: Duration = .milliseconds(1_100)
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

    func handle(_ input: PlayInput) {
        switch input {
        case .column(let column): play(.fourInARow(.init(column: column)))
        case .dart(let hit): throwDart(hit)
        case .shot(let shot): takeShot(shot)
        case .sendCommitted: sendCommitted()
        }
    }

    private func play(_ action: AnyAction) {
        guard !isWorking, case .play(let session) = screen else { return }
        do {
            let outgoing = try controller.prepareMove(action, in: session)
            // Show the move landing immediately, read-only until sent or reopened.
            let landed = PlaySession(snapshot: outgoing.snapshot, localSeat: session.localSeat, mode: .readyToSend(pending: outgoing.snapshot))
            stage(outgoing, showing: landed, restoring: session, delay: insertDelay)
        } catch {
            errorText = "That move isn't allowed."
        }
    }

    /// A dart is committed to the ledger before it is shown landing (no re-throws).
    private func throwDart(_ hit: Darts.Hit) {
        guard !isWorking, case .play(let session) = screen else { return }
        do {
            switch try controller.throwDart(hit, in: session) {
            case .thrown(let next):
                screen = .play(next)
            case .visitComplete(let next, let outgoing):
                // If inserting fails, come back to the finished visit with its Send button.
                stage(outgoing, showing: staged(outgoing, over: session), restoring: next, delay: visitInsertDelay)
            }
        } catch {
            errorText = "Couldn't throw that dart."
        }
    }

    /// A shot is committed to the ledger before the balls move (no re-shots). The last
    /// shot of a turn plays out in full before the sheet collapses.
    private func takeShot(_ shot: EightBall.Shot) {
        guard !isWorking, case .play(let session) = screen else { return }
        let start = session.eightBallProgress
        do {
            switch try controller.takeShot(shot, in: session) {
            case .thrown(let next):
                screen = .play(next)
            case .visitComplete(let next, let outgoing):
                var delay = visitInsertDelay
                if let start {
                    let frames = EightBall.animation(of: shot, from: start.positions).frames.count
                    delay = .milliseconds(min(9_000, frames * 1_000 / 60 + 900))
                }
                stage(outgoing, showing: staged(outgoing, over: session), restoring: next, delay: delay)
            }
        } catch {
            errorText = "Couldn't take that shot."
        }
    }

    /// Puts an already committed visit back in the message box (after it was deleted).
    private func sendCommitted() {
        guard !isWorking, case .play(let session) = screen, let draft = session.draft else { return }
        do {
            let outgoing = try controller.prepareMove(draft, in: session)
            stage(outgoing, showing: staged(outgoing, over: session), restoring: session, delay: .zero)
        } catch {
            errorText = "Couldn't prepare your darts."
        }
    }

    /// The official position with `outgoing` waiting to be sent.
    private func staged(_ outgoing: OutgoingMessage, over session: PlaySession) -> PlaySession {
        PlaySession(
            snapshot: session.snapshot,
            localSeat: session.localSeat,
            mode: .readyToSend(pending: outgoing.snapshot),
            isUnsentNewMatch: session.isUnsentNewMatch
        )
    }

    /// Shows `showing` now, then asks Messages to insert the move after `delay`, so the
    /// disc falls or the last dart lands before the sheet collapses.
    private func stage(_ outgoing: OutgoingMessage, showing: PlaySession, restoring previous: PlaySession, delay: Duration) {
        screenBeforeInsert = .play(previous)
        screen = .play(showing)
        isWorking = true
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            isWorking = false
            perform(.insert(outgoing))
        }
    }

    /// The move is in the compose field. Show the official board with the staged move as a
    /// ghost and keep it interactive, so tapping another column replaces the staged message.
    func markInserted(_ outgoing: OutgoingMessage) {
        errorText = nil
        if case .play(let before)? = screenBeforeInsert {
            screen = .play(PlaySession(
                snapshot: before.snapshot,
                localSeat: before.localSeat,
                mode: .readyToSend(pending: outgoing.snapshot),
                isUnsentNewMatch: before.isUnsentNewMatch
            ))
        } else {
            // A no-move challenge: nothing to change, just show it as staged.
            screen = .play(PlaySession(
                snapshot: outgoing.snapshot,
                localSeat: outgoing.localSeat,
                mode: .readyToSend(pending: outgoing.snapshot),
                isUnsentNewMatch: true
            ))
        }
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
    /// Set from the RELAY_APP_GROUP build setting (Config/Relay.xcconfig) via Info.plist,
    /// so it always matches the entitlements.
    /// Empty when the build has no App Group (RELAY_USE_APP_GROUP = NO, D-025).
    static var appGroup: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "RelayAppGroup") as? String,
              !group.isEmpty
        else { return nil }
        return group
    }

    static var ledgerURL: URL {
        let base = appGroup.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Relay", isDirectory: true).appendingPathComponent("ledger-v1.json")
    }
}
