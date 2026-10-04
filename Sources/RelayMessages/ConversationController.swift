import Foundation
import RelayAnalytics
import RelayCore
import RelayGames

/// What the extension learned about the message the user opened, translated out
/// of the Messages framework so this logic is testable anywhere.
public struct OpenedMessage: Equatable, Sendable {
    public var url: URL?
    /// `MSMessage.senderParticipantIdentifier == MSConversation.localParticipantIdentifier`.
    public var senderIsLocal: Bool
    /// `MSMessage.isPending`: the message is still in the compose field, not sent.
    public var isPending: Bool

    public init(url: URL?, senderIsLocal: Bool, isPending: Bool) {
        self.url = url
        self.senderIsLocal = senderIsLocal
        self.isPending = isPending
    }
}

/// A match the user is looking at, already resolved against this device's ledger.
public struct PlaySession: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case yourTurn
        case waitingForOpponent
        /// A move or challenge is in the compose field but has not been sent.
        /// The board shows the official state; `pending` is what would be sent.
        case readyToSend(pending: AnyMatchSnapshot)
        case finished
    }

    public enum Notice: Equatable, Sendable {
        /// The user tapped an older bubble; the session shows the latest known turn instead.
        case openedOlderTurn(openedTurn: Int)
        /// Two different histories exist for this match (e.g. a move changed after sending,
        /// or the same Apple Account on two devices). The first one seen is kept.
        case historyDiverged
    }

    public var snapshot: AnyMatchSnapshot
    public var localSeat: Seat
    public var mode: Mode
    public var notices: [Notice]
    /// True for a match created on this device that has not been inserted yet.
    public var isUnsentNewMatch: Bool
    /// A rematch of this match that this device already knows about.
    public var knownRematch: MatchID?

    public init(snapshot: AnyMatchSnapshot, localSeat: Seat, mode: Mode, notices: [Notice] = [], isUnsentNewMatch: Bool = false, knownRematch: MatchID? = nil) {
        self.snapshot = snapshot
        self.localSeat = localSeat
        self.mode = mode
        self.notices = notices
        self.isUnsentNewMatch = isUnsentNewMatch
        self.knownRematch = knownRematch
    }

    public var canMove: Bool {
        switch mode {
        case .yourTurn, .readyToSend: snapshot.outcome.seatToAct == localSeat
        case .waitingForOpponent, .finished: false
        }
    }
}

public enum ConversationScreen: Equatable, Sendable {
    case picker
    case play(PlaySession)
    case problem(ProtocolError)
}

/// Text for the message bubble (template layout caption, subcaption, summary).
public struct MessageCaption: Equatable, Sendable {
    public var caption: String
    public var subcaption: String?
    public var summaryText: String
    public var accessibilityLabel: String
}

/// A message ready to be inserted into the compose field.
public struct OutgoingMessage: Equatable, Sendable {
    public var snapshot: AnyMatchSnapshot
    public var url: URL
    public var localSeat: Seat
    public var caption: MessageCaption
}

/// A move in any supported game.
public enum AnyAction: Equatable, Sendable {
    case fourInARow(FourInARow.Action)
}

public enum ControllerError: Error, Equatable, Sendable {
    case notYourTurn
    case gameMismatch
    case illegalMove(String)
    case matchNotFinished
    case encoding(MatchCodec.EncodingError)
}

/// Turns Messages lifecycle events into screens and outgoing messages, and keeps
/// the ledger honest. Owns no UI and imports no Apple-only framework.
public final class ConversationController {
    /// Product decision D-007: the challenger makes the first move before sending,
    /// so the very first bubble already contains a move to answer.
    public static let challengerMovesFirst = true

    private let store: LedgerStore
    private let analytics: AnalyticsSink
    private let now: () -> Date
    public private(set) var ledger: MatchLedger
    /// Last error from saving the ledger, surfaced in debug UI rather than hidden.
    public private(set) var lastPersistenceError: String?

    public init(store: LedgerStore, analytics: AnalyticsSink = NoOpAnalytics(), now: @escaping () -> Date = Date.init) {
        self.store = store
        self.analytics = analytics
        self.now = now
        self.ledger = store.load()
    }

    // MARK: Opening messages

    /// Resolves what to show for the selected message (nil when opened from the app drawer).
    public func screen(for message: OpenedMessage?) -> ConversationScreen {
        guard let message, let url = message.url else {
            analytics.record(.gamePickerOpen)
            return .picker
        }
        let opened: AnyMatchSnapshot
        do {
            opened = try GameDecoders.decode(url)
        } catch {
            analytics.record(.messageRejected(reason: Self.reasonCode(error)))
            return .problem(error)
        }
        analytics.record(.turnOpened(opened.gameID, turn: opened.turnNumber))

        if message.isPending {
            return .play(resolvePending(opened, url: url))
        }
        return .play(resolveTranscript(opened, url: url, senderIsLocal: message.senderIsLocal))
    }

    /// Called for `didReceive`: a new message arrived while the extension is open.
    /// Returns a new screen if it concerns the match on screen, else nil.
    public func received(_ message: OpenedMessage, currentMatch: MatchID?) -> ConversationScreen? {
        guard let url = message.url, let snapshot = try? GameDecoders.decode(url) else { return nil }
        let session = resolveTranscript(snapshot, url: url, senderIsLocal: message.senderIsLocal)
        return session.snapshot.matchID == currentMatch ? .play(session) : nil
    }

    private func resolvePending(_ pending: AnyMatchSnapshot, url: URL) -> PlaySession {
        let entry = ledger.entry(for: pending.matchID)
        let localSeat = pending.producedBy
        var official: AnyMatchSnapshot?
        if let known = decodeStored(entry?.official), known.isPrefix(of: pending), known.turnNumber < pending.turnNumber {
            official = known
        } else {
            // No usable record (e.g. storage was cleared): the official state is the
            // pending one minus the local move. Nil for a turn-0 challenge.
            official = pending.removingLastAction()
        }
        persist { ledger in
            ledger.update(pending.matchID, gameID: pending.gameID, now: now()) { entry in
                entry.pendingOutgoing = .init(url: url, turnNumber: pending.turnNumber, source: .insertedNotSent)
                entry.localSeat = localSeat
                entry.previousMatchID = pending.header.previousMatchID
            }
        }
        return PlaySession(
            snapshot: official ?? pending,
            localSeat: localSeat,
            mode: .readyToSend(pending: pending),
            isUnsentNewMatch: official == nil
        )
    }

    private func resolveTranscript(_ opened: AnyMatchSnapshot, url: URL, senderIsLocal: Bool) -> PlaySession {
        let entry = ledger.entry(for: opened.matchID)
        let openedSource: MatchLedger.StoredSnapshot.Source = senderIsLocal ? .sentFromThisDevice : .received
        var display = opened
        var displaySource = openedSource
        var notices: [PlaySession.Notice] = []
        var newOfficial: (AnyMatchSnapshot, URL, MatchLedger.StoredSnapshot.Source)?

        if let stored = entry?.official, let known = decodeStored(stored) {
            if known.turnNumber > opened.turnNumber {
                display = known
                displaySource = stored.source
                notices.append(.openedOlderTurn(openedTurn: opened.turnNumber))
                if !opened.isPrefix(of: known) { notices.append(.historyDiverged) }
            } else if known.turnNumber == opened.turnNumber {
                if !Self.sameHistory(known, opened) {
                    // First seen wins: never let a second history silently replace the first.
                    display = known
                    displaySource = stored.source
                    notices.append(.historyDiverged)
                }
            } else {
                if !known.isPrefix(of: opened) { notices.append(.historyDiverged) }
                newOfficial = (opened, url, openedSource)
            }
        } else {
            newOfficial = (opened, url, openedSource)
        }

        let localSeat = displaySource == .received ? display.producedBy.opponent : display.producedBy
        let previousOfficialFinished = decodeStored(entry?.official)?.outcome.isFinished ?? false

        persist { ledger in
            ledger.update(display.matchID, gameID: display.gameID, now: now()) { entry in
                if let (snapshot, url, source) = newOfficial {
                    entry.official = .init(url: url, turnNumber: snapshot.turnNumber, source: source)
                }
                if let pending = entry.pendingOutgoing,
                   let officialTurn = entry.official?.turnNumber,
                   pending.turnNumber <= officialTurn {
                    entry.pendingOutgoing = nil
                }
                entry.localSeat = localSeat
                entry.previousMatchID = display.header.previousMatchID
            }
        }
        if newOfficial != nil, display.outcome.isFinished, !previousOfficialFinished {
            recordCompletion(display, localSeat: localSeat)
        }

        let mode: PlaySession.Mode
        if display.outcome.isFinished {
            mode = .finished
        } else if let pending = decodeStored(ledger.entry(for: display.matchID)?.pendingOutgoing),
                  display.isPrefix(of: pending), pending.turnNumber > display.turnNumber {
            mode = .readyToSend(pending: pending)
        } else if display.outcome.seatToAct == localSeat {
            mode = .yourTurn
        } else {
            mode = .waitingForOpponent
        }
        return PlaySession(
            snapshot: display,
            localSeat: localSeat,
            mode: mode,
            notices: notices,
            knownRematch: ledger.rematch(of: display.matchID)
        )
    }

    // MARK: Creating messages

    public enum NewMatch: Equatable, Sendable {
        /// The local player moves first: show the board, then call `prepareMove`.
        case play(PlaySession)
        /// The opponent moves first: insert this challenge as is.
        case insert(OutgoingMessage)
    }

    public func startMatch(game: GameID) -> NewMatch? {
        guard game == FourInARow.gameID else { return nil }
        analytics.record(.gameSelected(game))
        let header = MatchHeader(
            gameID: game,
            rulesVersion: FourInARow.rulesVersion,
            firstSeat: Self.challengerMovesFirst ? .one : .two
        )
        return makeNewMatch(header: header)
    }

    public func startRematch(from session: PlaySession) throws(ControllerError) -> NewMatch {
        guard session.snapshot.outcome.isFinished else { throw .matchNotFinished }
        let header: MatchHeader
        switch session.snapshot {
        case .fourInARow(let snapshot):
            header = snapshot.match.rematchHeader(initiator: session.localSeat)
        }
        analytics.record(.rematchStarted(header.gameID))
        guard let result = makeNewMatch(header: header) else { throw .gameMismatch }
        return result
    }

    private func makeNewMatch(header: MatchHeader) -> NewMatch? {
        guard header.gameID == FourInARow.gameID,
              let match = try? Match<FourInARow>(header: header, configuration: .standard)
        else { return nil }
        let snapshot = AnyMatchSnapshot.fourInARow(MatchSnapshot(match: match))
        if header.firstSeat == .one {
            return .play(PlaySession(snapshot: snapshot, localSeat: .one, mode: .yourTurn, isUnsentNewMatch: true))
        }
        guard let url = try? snapshot.url() else { return nil }
        analytics.record(.challengePrepared(header.gameID))
        return .insert(OutgoingMessage(snapshot: snapshot, url: url, localSeat: .one, caption: Self.caption(for: snapshot)))
    }

    /// Applies the local player's move to the official state and builds the message.
    /// Choosing again while a move is ready to send replaces it (same MSSession).
    public func prepareMove(_ action: AnyAction, in session: PlaySession) throws(ControllerError) -> OutgoingMessage {
        guard session.canMove else { throw .notYourTurn }
        let next: AnyMatchSnapshot
        switch (session.snapshot, action) {
        case (.fourInARow(let snapshot), .fourInARow(let move)):
            do {
                let match = try snapshot.match.applying(move, by: session.localSeat)
                next = .fourInARow(MatchSnapshot(match: match, loadouts: snapshot.loadouts))
            } catch {
                throw .illegalMove(String(describing: error))
            }
        }
        let url: URL
        do {
            url = try next.url()
        } catch {
            throw .encoding(error)
        }
        if next.turnNumber == 1 && session.isUnsentNewMatch {
            analytics.record(.challengePrepared(next.gameID))
        }
        return OutgoingMessage(snapshot: next, url: url, localSeat: session.localSeat, caption: Self.caption(for: next))
    }

    // MARK: Messages lifecycle

    /// The message was placed in the compose field. It is not sent yet.
    public func didInsert(_ outgoing: OutgoingMessage) {
        let snapshot = outgoing.snapshot
        analytics.record(.turnPrepared(snapshot.gameID, turn: snapshot.turnNumber))
        persist { ledger in
            ledger.update(snapshot.matchID, gameID: snapshot.gameID, now: now()) { entry in
                entry.pendingOutgoing = .init(url: outgoing.url, turnNumber: snapshot.turnNumber, source: .insertedNotSent)
                entry.localSeat = outgoing.localSeat
                entry.previousMatchID = snapshot.header.previousMatchID
            }
            if let previous = snapshot.header.previousMatchID, ledger.entry(for: previous) != nil {
                ledger.update(previous, gameID: snapshot.gameID, now: now()) { $0.rematchMatchID = snapshot.matchID }
            }
        }
    }

    /// `didStartSending`: the user tapped send while the extension was alive.
    /// This makes the state "sent from this device", which is still not "delivered".
    public func didStartSending(url: URL?) {
        guard let url, let snapshot = try? GameDecoders.decode(url) else { return }
        analytics.record(.turnSendStarted(snapshot.gameID, turn: snapshot.turnNumber))
        let entry = ledger.entry(for: snapshot.matchID)
        let previousOfficial = decodeStored(entry?.official)
        let localSeat = entry?.localSeat ?? snapshot.producedBy
        persist { ledger in
            ledger.update(snapshot.matchID, gameID: snapshot.gameID, now: now()) { entry in
                if (entry.official?.turnNumber ?? -1) < snapshot.turnNumber {
                    entry.official = .init(url: url, turnNumber: snapshot.turnNumber, source: .sentFromThisDevice)
                }
                if let pending = entry.pendingOutgoing, pending.turnNumber <= snapshot.turnNumber {
                    entry.pendingOutgoing = nil
                }
                entry.localSeat = localSeat
            }
        }
        if snapshot.outcome.isFinished, !(previousOfficial?.outcome.isFinished ?? false) {
            recordCompletion(snapshot, localSeat: localSeat)
        }
    }

    /// `didCancelSending`: the user removed the message from the compose field.
    public func didCancelSending(url: URL?) {
        guard let url, let snapshot = try? GameDecoders.decode(url) else { return }
        analytics.record(.turnSendCancelled(snapshot.gameID))
        persist { ledger in
            ledger.update(snapshot.matchID, gameID: snapshot.gameID, now: now()) { entry in
                if entry.pendingOutgoing?.url == url { entry.pendingOutgoing = nil }
            }
        }
    }

    // MARK: Captions

    /// Captions are shown identically on both sides of the conversation and never name
    /// anyone (D-016). "Your turn" speaks to the recipient, as GamePigeon does (D-018).
    public static func caption(for snapshot: AnyMatchSnapshot) -> MessageCaption {
        let gameName = GameCatalog.definition(for: snapshot.gameID)?.displayName ?? "Relay"
        let subcaption: String
        let summary: String
        switch snapshot.outcome {
        case .won:
            subcaption = "Game over · four in a row!"
            summary = "Won a game of \(gameName)"
        case .draw:
            subcaption = "Game over · it's a draw"
            summary = "Drew a game of \(gameName)"
        case .inProgress:
            // Owner decision (D-018): match GamePigeon's familiar "Your turn", addressed
            // to the recipient, rather than a move counter.
            subcaption = "Your turn"
            summary = snapshot.turnNumber == 0 ? "Sent a \(gameName) challenge" : "Played \(gameName)"
        }
        return MessageCaption(
            caption: gameName,
            subcaption: subcaption,
            summaryText: summary,
            accessibilityLabel: "\(gameName). \(subcaption)."
        )
    }

    // MARK: Helpers

    private func recordCompletion(_ snapshot: AnyMatchSnapshot, localSeat: Seat) {
        let result: AnalyticsEvent.Result
        switch snapshot.outcome {
        case .won(let winner): result = winner == localSeat ? .localWin : .localLoss
        case .draw: result = .draw
        case .inProgress: return
        }
        analytics.record(.matchCompleted(snapshot.gameID, result: result, turns: snapshot.turnNumber))
    }

    private func decodeStored(_ stored: MatchLedger.StoredSnapshot?) -> AnyMatchSnapshot? {
        guard let stored else { return nil }
        return try? GameDecoders.decode(stored.url)
    }

    private static func sameHistory(_ a: AnyMatchSnapshot, _ b: AnyMatchSnapshot) -> Bool {
        a.isPrefix(of: b) && b.isPrefix(of: a)
    }

    private func persist(_ change: (inout MatchLedger) -> Void) {
        change(&ledger)
        do {
            try store.save(ledger)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = String(describing: error)
        }
    }

    static func reasonCode(_ error: ProtocolError) -> String {
        switch error {
        case .notARelayMessage: "not_relay"
        case .missingField: "missing_field"
        case .oversized: "oversized"
        case .unsupportedProtocolVersion: "protocol_too_new"
        case .obsoleteProtocolVersion: "protocol_too_old"
        case .unknownGame: "unknown_game"
        case .unsupportedRulesVersion: "rules_too_new"
        case .malformedPayload: "malformed"
        case .inconsistentHeader: "inconsistent"
        case .illegalHistory: "illegal_history"
        }
    }
}
