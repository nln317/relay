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
    /// Throws already committed for this turn (skill games), possibly a whole visit that
    /// still has to be put in the message box. Nil for board games.
    public var draft: AnyAction?

    public init(snapshot: AnyMatchSnapshot, localSeat: Seat, mode: Mode, notices: [Notice] = [], isUnsentNewMatch: Bool = false, knownRematch: MatchID? = nil, draft: AnyAction? = nil) {
        self.snapshot = snapshot
        self.localSeat = localSeat
        self.mode = mode
        self.notices = notices
        self.isUnsentNewMatch = isUnsentNewMatch
        self.knownRematch = knownRematch
        self.draft = draft
    }

    public var canMove: Bool {
        switch mode {
        case .yourTurn: snapshot.outcome.seatToAct == localSeat
        case .readyToSend: snapshot.allowsChangingStagedMove && snapshot.outcome.seatToAct == localSeat
        case .waitingForOpponent, .finished: false
        }
    }

    /// The darts thrown so far this turn, scored against the official state.
    public var dartsProgress: Darts.VisitProgress? {
        guard case .darts(let snapshot) = snapshot else { return nil }
        let hits: [Darts.Hit]
        if case .darts(let visit)? = draft { hits = visit.hits } else { hits = [] }
        return snapshot.match.state.progress(of: hits, by: localSeat)
    }

    /// The shots taken so far this turn, played out on the official table.
    public var eightBallProgress: EightBall.TurnProgress? {
        guard case .eightBall(let snapshot) = snapshot else { return nil }
        let shots: [EightBall.Shot]
        if case .eightBall(let turn)? = draft { shots = turn.shots } else { shots = [] }
        return snapshot.match.state.progress(of: shots, by: localSeat)
    }

    /// The balls thrown so far this turn, judged against the official cups.
    public var cupPongProgress: CupPong.TurnProgress? {
        guard case .cupPong(let snapshot) = snapshot else { return nil }
        let landings: [CupPong.Landing]
        if case .cupPong(let turn)? = draft { landings = turn.landings } else { landings = [] }
        return snapshot.match.state.progress(of: landings, by: localSeat)
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
    case darts(Darts.Action)
    case eightBall(EightBall.Action)
    case cupPong(CupPong.Action)
}

public enum ControllerError: Error, Equatable, Sendable {
    case notYourTurn
    case gameMismatch
    case illegalMove(String)
    case matchNotFinished
    case encoding(MatchCodec.EncodingError)
    /// A skill-game action that differs from the throws already committed for this turn.
    case differsFromCommittedThrows
    /// No more darts can be thrown (or shots taken) this turn.
    case visitAlreadyComplete
    /// A shot the rules refuse before it is played (bad numbers or cue ball placement).
    case illegalShot(String)
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
        // A snapshot whose last move was made from our known seat is ours, whatever the
        // participant identifiers say (see localSeat below).
        let openedIsOurs = entry?.localSeat.map { $0 == opened.producedBy } ?? senderIsLocal
        let openedSource: MatchLedger.StoredSnapshot.Source = openedIsOurs ? .sentFromThisDevice : .received
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

        // Once this device has played a seat in a match, that is authoritative. Participant
        // identifiers proved unreliable for the sender's own bubble (iOS 26.5 simulator showed
        // our own sent message as remote), so they only decide the seat on first contact.
        let localSeat = entry?.localSeat
            ?? (displaySource == .received ? display.producedBy.opponent : display.producedBy)
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
                if entry.localSeat == nil { entry.localSeat = localSeat }
                entry.previousMatchID = display.header.previousMatchID
                if let draft = entry.draft, draft.turnNumber < (entry.official?.turnNumber ?? 0) {
                    entry.draft = nil
                }
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
            knownRematch: ledger.rematch(of: display.matchID),
            draft: mode == .yourTurn ? committedDraft(for: display) : nil
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
        let rulesVersion: RulesVersion
        switch game {
        case FourInARow.gameID: rulesVersion = FourInARow.rulesVersion
        case Darts.gameID: rulesVersion = Darts.rulesVersion
        case EightBall.gameID: rulesVersion = EightBall.rulesVersion
        case CupPong.gameID: rulesVersion = CupPong.rulesVersion
        default: return nil
        }
        analytics.record(.gameSelected(game))
        let header = MatchHeader(
            gameID: game,
            rulesVersion: rulesVersion,
            firstSeat: Self.challengerMovesFirst ? .one : .two
        )
        return makeNewMatch(header: header, like: nil)
    }

    public func startRematch(from session: PlaySession) throws(ControllerError) -> NewMatch {
        guard session.snapshot.outcome.isFinished else { throw .matchNotFinished }
        let header: MatchHeader
        switch session.snapshot {
        case .fourInARow(let snapshot):
            header = snapshot.match.rematchHeader(initiator: session.localSeat)
        case .darts(let snapshot):
            header = snapshot.match.rematchHeader(initiator: session.localSeat)
        case .eightBall(let snapshot):
            header = snapshot.match.rematchHeader(initiator: session.localSeat)
        case .cupPong(let snapshot):
            header = snapshot.match.rematchHeader(initiator: session.localSeat)
        }
        analytics.record(.rematchStarted(header.gameID))
        guard let result = makeNewMatch(header: header, like: session.snapshot) else { throw .gameMismatch }
        return result
    }

    /// A new match with `header`, using the configuration of `previous` (a rematch plays
    /// the same variant) or the game's standard one.
    private func makeNewMatch(header: MatchHeader, like previous: AnyMatchSnapshot?) -> NewMatch? {
        let snapshot: AnyMatchSnapshot
        switch header.gameID {
        case FourInARow.gameID:
            var configuration = FourInARow.Configuration.standard
            if case .fourInARow(let old)? = previous { configuration = old.match.configuration }
            guard let match = try? Match<FourInARow>(header: header, configuration: configuration) else { return nil }
            snapshot = .fourInARow(MatchSnapshot(match: match))
        case Darts.gameID:
            var configuration = Darts.Configuration.standard
            if case .darts(let old)? = previous { configuration = old.match.configuration }
            guard let match = try? Match<Darts>(header: header, configuration: configuration) else { return nil }
            snapshot = .darts(MatchSnapshot(match: match))
        case EightBall.gameID:
            var configuration = EightBall.Configuration.standard
            if case .eightBall(let old)? = previous { configuration = old.match.configuration }
            guard let match = try? Match<EightBall>(header: header, configuration: configuration) else { return nil }
            snapshot = .eightBall(MatchSnapshot(match: match))
        case CupPong.gameID:
            var configuration = CupPong.Configuration.standard
            if case .cupPong(let old)? = previous { configuration = old.match.configuration }
            guard let match = try? Match<CupPong>(header: header, configuration: configuration) else { return nil }
            snapshot = .cupPong(MatchSnapshot(match: match))
        default:
            return nil
        }
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
        if !session.snapshot.allowsChangingStagedMove,
           let committed = committedDraft(for: session.snapshot), committed != action {
            throw .differsFromCommittedThrows
        }
        let next: AnyMatchSnapshot
        switch (session.snapshot, action) {
        case (.fourInARow(let snapshot), .fourInARow(let move)):
            do {
                let match = try snapshot.match.applying(move, by: session.localSeat)
                next = .fourInARow(MatchSnapshot(match: match, loadouts: snapshot.loadouts))
            } catch {
                throw .illegalMove(String(describing: error))
            }
        case (.darts(let snapshot), .darts(let visit)):
            do {
                let match = try snapshot.match.applying(visit, by: session.localSeat)
                next = .darts(MatchSnapshot(match: match, loadouts: snapshot.loadouts))
            } catch {
                throw .illegalMove(String(describing: error))
            }
        case (.eightBall(let snapshot), .eightBall(let turn)):
            do {
                let match = try snapshot.match.applying(turn, by: session.localSeat)
                next = .eightBall(MatchSnapshot(match: match, loadouts: snapshot.loadouts))
            } catch {
                throw .illegalMove(String(describing: error))
            }
        case (.cupPong(let snapshot), .cupPong(let turn)):
            do {
                let match = try snapshot.match.applying(turn, by: session.localSeat)
                next = .cupPong(MatchSnapshot(match: match, loadouts: snapshot.loadouts))
            } catch {
                throw .illegalMove(String(describing: error))
            }
        default:
            throw .gameMismatch
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

    // MARK: Skill games

    public enum ThrowResult: Equatable, Sendable {
        /// The dart is committed; the visit continues. Show this session.
        case thrown(PlaySession)
        /// The visit is over (third dart, checkout or bust): insert this message.
        case visitComplete(PlaySession, OutgoingMessage)
    }

    /// Commits one dart before anything is shown about where it landed, so reopening the
    /// extension or deleting the staged message cannot buy a second attempt.
    public func throwDart(_ hit: Darts.Hit, in session: PlaySession) throws(ControllerError) -> ThrowResult {
        guard case .yourTurn = session.mode, session.canMove,
              case .darts(let snapshot) = session.snapshot
        else { throw .notYourTurn }
        var hits: [Darts.Hit] = []
        if case .darts(let committed)? = committedDraft(for: session.snapshot) { hits = committed.hits }
        guard !snapshot.match.state.progress(of: hits, by: session.localSeat).isComplete else {
            throw .visitAlreadyComplete
        }
        hits.append(DartsAim.clamp(hit))
        let visit = AnyAction.darts(Darts.Action(hits: hits))
        commitDraft(visit, for: session.snapshot)
        var updated = session
        updated.draft = visit
        guard snapshot.match.state.progress(of: hits, by: session.localSeat).isComplete else {
            return .thrown(updated)
        }
        return .visitComplete(updated, try prepareMove(visit, in: updated))
    }

    /// Commits one 8-Ball shot before its result is shown, like `throwDart`: the shot is
    /// on record before the balls move, so nothing can be undone by reopening Relay.
    public func takeShot(_ shot: EightBall.Shot, in session: PlaySession) throws(ControllerError) -> ThrowResult {
        guard case .yourTurn = session.mode, session.canMove,
              case .eightBall(let snapshot) = session.snapshot
        else { throw .notYourTurn }
        var shots: [EightBall.Shot] = []
        if case .eightBall(let committed)? = committedDraft(for: session.snapshot) { shots = committed.shots }
        let state = snapshot.match.state
        let before = state.progress(of: shots, by: session.localSeat)
        guard !before.isComplete else { throw .visitAlreadyComplete }
        if let violation = EightBall.validate(shot, ballInHand: before.ballInHand, positions: before.positions) {
            throw .illegalShot(String(describing: violation))
        }
        shots.append(shot)
        let turn = AnyAction.eightBall(EightBall.Action(shots: shots))
        commitDraft(turn, for: session.snapshot)
        var updated = session
        updated.draft = turn
        guard state.progress(of: shots, by: session.localSeat).isComplete else {
            return .thrown(updated)
        }
        return .visitComplete(updated, try prepareMove(turn, in: updated))
    }

    /// Commits one Cup Pong ball before anything is shown about where it went, like
    /// `throwDart`.
    public func throwBall(_ landing: CupPong.Landing, in session: PlaySession) throws(ControllerError) -> ThrowResult {
        guard case .yourTurn = session.mode, session.canMove,
              case .cupPong(let snapshot) = session.snapshot
        else { throw .notYourTurn }
        var landings: [CupPong.Landing] = []
        if case .cupPong(let committed)? = committedDraft(for: session.snapshot) { landings = committed.landings }
        let state = snapshot.match.state
        guard !state.progress(of: landings, by: session.localSeat).isComplete else { throw .visitAlreadyComplete }
        let reach = CupPong.maximumReach
        landings.append(CupPong.Landing(x: min(max(landing.x, -reach), reach), y: min(max(landing.y, -reach), reach)))
        let turn = AnyAction.cupPong(CupPong.Action(landings: landings))
        commitDraft(turn, for: session.snapshot)
        var updated = session
        updated.draft = turn
        guard state.progress(of: landings, by: session.localSeat).isComplete else {
            return .thrown(updated)
        }
        return .visitComplete(updated, try prepareMove(turn, in: updated))
    }

    private func commitDraft(_ action: AnyAction, for snapshot: AnyMatchSnapshot) {
        let data: Data?
        switch action {
        case .fourInARow(let move): data = try? JSONEncoder().encode(move)
        case .darts(let visit): data = try? JSONEncoder().encode(visit)
        case .eightBall(let turn): data = try? JSONEncoder().encode(turn)
        case .cupPong(let turn): data = try? JSONEncoder().encode(turn)
        }
        guard let data else { return }
        persist { ledger in
            ledger.update(snapshot.matchID, gameID: snapshot.gameID, now: now()) { entry in
                entry.draft = .init(turnNumber: snapshot.turnNumber, action: data)
            }
        }
    }

    /// The committed draft for the turn after `snapshot`, if any.
    func committedDraft(for snapshot: AnyMatchSnapshot) -> AnyAction? {
        guard let draft = ledger.entry(for: snapshot.matchID)?.draft,
              draft.turnNumber == snapshot.turnNumber
        else { return nil }
        switch snapshot {
        case .fourInARow:
            return (try? JSONDecoder().decode(FourInARow.Action.self, from: draft.action)).map(AnyAction.fourInARow)
        case .darts:
            return (try? JSONDecoder().decode(Darts.Action.self, from: draft.action)).map(AnyAction.darts)
        case .eightBall:
            return (try? JSONDecoder().decode(EightBall.Action.self, from: draft.action)).map(AnyAction.eightBall)
        case .cupPong:
            return (try? JSONDecoder().decode(CupPong.Action.self, from: draft.action)).map(AnyAction.cupPong)
        }
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
                if let draft = entry.draft, draft.turnNumber < snapshot.turnNumber {
                    entry.draft = nil
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
            subcaption = "Game over · \(winningLine(for: snapshot))"
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

    private static func winningLine(for snapshot: AnyMatchSnapshot) -> String {
        switch snapshot {
        case .fourInARow:
            return "four in a row!"
        case .darts(let darts):
            return darts.match.state.lastVisit?.result == .finished ? "checked out!" : "fewest points left"
        case .eightBall(let pool):
            return pool.match.state.lastTurn?.shots.last?.ending == .won ? "sank the 8!" : "8-ball foul"
        case .cupPong(let pong):
            return pong.match.state.turns.count >= CupPong.maximumTurns ? "most cups left" : "all cups sunk!"
        }
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
