import Foundation
import RelayAnalytics
import RelayCore
import RelayGames
@testable import RelayMessages
import Testing

/// One simulated iPhone running the extension. Two of these plus a shared
/// transcript stand in for a two-device Messages conversation. This is an
/// integration test of our logic, not of Messages itself (docs/TESTING.md).
final class SimulatedDevice {
    let name: String
    let store: InMemoryLedgerStore
    let analytics = RecordingAnalytics()
    private(set) var controller: ConversationController
    var clock = Date(timeIntervalSince1970: 1_700_000_000)

    init(name: String) {
        self.name = name
        self.store = InMemoryLedgerStore()
        self.controller = ConversationController(store: store, analytics: analytics)
        rebuildController()
    }

    /// Simulates the extension process being killed and relaunched.
    func relaunch() {
        rebuildController()
    }

    private func rebuildController() {
        controller = ConversationController(store: store, analytics: analytics, now: { [unowned self] in
            clock.addTimeInterval(1)
            return clock
        })
    }

    var token: String { "$\(name)" }
}

struct SentMessage {
    var url: URL
    var sender: SimulatedDevice
}

final class Conversation {
    var transcript: [SentMessage] = []

    /// User taps a bubble in the transcript on `device`.
    func open(_ message: SentMessage, on device: SimulatedDevice) -> ConversationScreen {
        device.controller.screen(for: OpenedMessage(url: message.url, senderIsLocal: message.sender === device, isPending: false))
    }

    /// Insert into the compose field, then the user taps send.
    @discardableResult
    func insertAndSend(_ outgoing: OutgoingMessage, from device: SimulatedDevice) -> SentMessage {
        device.controller.didInsert(outgoing)
        device.controller.didStartSending(url: outgoing.url)
        let message = SentMessage(url: outgoing.url, sender: device)
        transcript.append(message)
        return message
    }

    var last: SentMessage { transcript[transcript.count - 1] }
}

func session(_ screen: ConversationScreen?, sourceLocation: SourceLocation = #_sourceLocation) throws -> PlaySession {
    guard case .play(let session) = screen else {
        Issue.record("expected a play screen, got \(String(describing: screen))", sourceLocation: sourceLocation)
        throw CancellationError()
    }
    return session
}

func move(_ column: Int) -> AnyAction { .fourInARow(.init(column: column)) }

@Suite("Two-device conversation flow")
struct ConversationFlowTests {
    /// Ava challenges Ben; they play to a win; Ben asks for a rematch.
    @Test func fullMatchThenRematch() throws {
        let ava = SimulatedDevice(name: "ava")
        let ben = SimulatedDevice(name: "ben")
        let chat = Conversation()

        // Ava opens the app drawer: picker.
        #expect(ava.controller.screen(for: nil) == .picker)

        // Ava picks Four in a Row and moves first (D-007).
        guard case .play(let fresh) = ava.controller.startMatch(game: FourInARow.gameID, senderToken: ava.token) else {
            Issue.record("expected the challenger to move first")
            return
        }
        #expect(fresh.mode == .yourTurn)
        #expect(fresh.isUnsentNewMatch)
        #expect(fresh.localSeat == .one)

        var outgoing = try ava.controller.prepareMove(move(0), in: fresh, senderToken: ava.token)
        #expect(outgoing.caption.subcaption == "$ava made the first move")
        chat.insertAndSend(outgoing, from: ava)

        // Ava re-opens her own bubble: waiting.
        let avaWaiting = try session(chat.open(chat.last, on: ava))
        #expect(avaWaiting.mode == .waitingForOpponent)
        #expect(avaWaiting.localSeat == .one)

        // Alternate until Ava completes the bottom row: A0 B0 A1 B1 A2 B2 A3.
        let script: [(SimulatedDevice, Int)] = [(ben, 0), (ava, 1), (ben, 1), (ava, 2), (ben, 2), (ava, 3)]
        for (device, column) in script {
            let current = try session(chat.open(chat.last, on: device))
            #expect(current.mode == .yourTurn, "\(device.name) should be able to move")
            #expect(current.localSeat == (device === ava ? .one : .two))
            outgoing = try device.controller.prepareMove(move(column), in: current, senderToken: device.token)
            chat.insertAndSend(outgoing, from: device)
        }
        #expect(outgoing.caption.subcaption == "$ava wins!")

        let benResult = try session(chat.open(chat.last, on: ben))
        #expect(benResult.mode == .finished)
        #expect(benResult.snapshot.outcome == .won(by: .one))
        #expect(benResult.localSeat == .two)
        let avaResult = try session(chat.open(chat.last, on: ava))
        #expect(avaResult.mode == .finished)
        #expect(avaResult.localSeat == .one)

        #expect(ava.analytics.events.contains(.matchCompleted(FourInARow.gameID, result: .localWin, turns: 7)))
        #expect(ben.analytics.events.contains(.matchCompleted(FourInARow.gameID, result: .localLoss, turns: 7)))

        // Ben (who moved second) starts the rematch, so Ben moves first.
        let rematch = try ben.controller.startRematch(from: benResult, senderToken: ben.token)
        guard case .play(let benFirst) = rematch else {
            Issue.record("expected Ben to move first in the rematch")
            return
        }
        #expect(benFirst.snapshot.header.previousMatchID == benResult.snapshot.matchID)
        #expect(benFirst.snapshot.header.series == SeriesTally(seatOneWins: 0, seatTwoWins: 1, draws: 0))
        let rematchMove = try ben.controller.prepareMove(move(3), in: benFirst, senderToken: ben.token)
        chat.insertAndSend(rematchMove, from: ben)

        let avaRematch = try session(chat.open(chat.last, on: ava))
        #expect(avaRematch.mode == .yourTurn)
        #expect(avaRematch.localSeat == .two)
        #expect(avaRematch.snapshot.header.series.wins(for: .two) == 1)

        // Opening the old result now shows that a rematch exists, on both devices.
        #expect(try session(chat.open(chat.transcript[6], on: ben)).knownRematch == rematchMove.snapshot.matchID)
        #expect(try session(chat.open(chat.transcript[6], on: ava)).knownRematch == rematchMove.snapshot.matchID)
    }

    @Test func secondMoverChallengeCarriesNoMove() throws {
        let ava = SimulatedDevice(name: "ava")
        let ben = SimulatedDevice(name: "ben")
        let chat = Conversation()
        // A rematch started by the player who moved first produces a turn-0 challenge.
        let finished = try makeMatch([0, 1, 0, 1, 0, 1, 0])
        let avaSession = PlaySession(snapshot: .fourInARow(MatchSnapshot(match: finished)), localSeat: .one, mode: .finished)
        guard case .insert(let challenge) = try ava.controller.startRematch(from: avaSession, senderToken: ava.token) else {
            Issue.record("expected a challenge to insert")
            return
        }
        #expect(challenge.snapshot.turnNumber == 0)
        #expect(challenge.caption.subcaption == "$ava wants to play")
        chat.insertAndSend(challenge, from: ava)
        #expect(try session(chat.open(chat.last, on: ava)).mode == .waitingForOpponent)
        let benSession = try session(chat.open(chat.last, on: ben))
        #expect(benSession.mode == .yourTurn)
        #expect(benSession.localSeat == .two)
    }

    @Test func cannotMoveOutOfTurnOrAfterTheEnd() throws {
        let ava = SimulatedDevice(name: "ava")
        let chat = Conversation()
        guard case .play(let fresh) = ava.controller.startMatch(game: FourInARow.gameID, senderToken: nil) else { return }
        chat.insertAndSend(try ava.controller.prepareMove(move(3), in: fresh, senderToken: nil), from: ava)
        let waiting = try session(chat.open(chat.last, on: ava))
        #expect(throws: ControllerError.notYourTurn) {
            try ava.controller.prepareMove(move(4), in: waiting, senderToken: nil)
        }
        let finished = PlaySession(snapshot: .fourInARow(MatchSnapshot(match: try makeMatch([0, 1, 0, 1, 0, 1, 0]))), localSeat: .two, mode: .finished)
        #expect(throws: ControllerError.notYourTurn) { try ava.controller.prepareMove(move(4), in: finished, senderToken: nil) }
        #expect(throws: ControllerError.matchNotFinished) { try ava.controller.startRematch(from: waiting, senderToken: nil) }
    }

    @Test func illegalLocalMoveIsReportedNotSent() throws {
        let ava = SimulatedDevice(name: "ava")
        let full = try makeMatch([2, 2, 2, 2, 2, 2])
        let current = PlaySession(snapshot: .fourInARow(MatchSnapshot(match: full)), localSeat: .one, mode: .yourTurn)
        #expect(throws: ControllerError.self) { try ava.controller.prepareMove(move(2), in: current, senderToken: nil) }
    }
}

@Suite("Messages edge cases")
struct EdgeCaseTests {
    /// Plays `columns` alternately between Ava and Ben, starting with Ava.
    func playedConversation(_ columns: [Int]) throws -> (SimulatedDevice, SimulatedDevice, Conversation) {
        let ava = SimulatedDevice(name: "ava")
        let ben = SimulatedDevice(name: "ben")
        let chat = Conversation()
        guard case .play(var current) = ava.controller.startMatch(game: FourInARow.gameID, senderToken: nil) else {
            throw CancellationError()
        }
        for (index, column) in columns.enumerated() {
            let device = index.isMultiple(of: 2) ? ava : ben
            if index > 0 { current = try session(chat.open(chat.last, on: device)) }
            chat.insertAndSend(try device.controller.prepareMove(move(column), in: current, senderToken: nil), from: device)
        }
        return (ava, ben, chat)
    }

    @Test func openingAnOlderBubbleShowsTheLatestTurn() throws {
        let (_, ben, chat) = try playedConversation([3, 3, 4, 4])
        // Ben opens Ava's first move (turn 1) although turn 4 exists.
        let older = try session(chat.open(chat.transcript[0], on: ben))
        #expect(older.snapshot.turnNumber == 4)
        #expect(older.notices == [.openedOlderTurn(openedTurn: 1)])
        #expect(older.mode == .waitingForOpponent)
        #expect(older.localSeat == .two)
    }

    @Test func olderBubbleCannotBeUsedToReplayATurn() throws {
        let (ava, _, chat) = try playedConversation([3, 3])
        // Ava already answered turn... Ava opens Ben's turn-2 bubble: her move.
        let current = try session(chat.open(chat.last, on: ava))
        chat.insertAndSend(try ava.controller.prepareMove(move(0), in: current, senderToken: nil), from: ava)
        // Re-opening Ben's turn-2 bubble must not offer a second answer to it.
        let again = try session(chat.open(chat.transcript[1], on: ava))
        #expect(again.snapshot.turnNumber == 3)
        #expect(again.mode == .waitingForOpponent)
        #expect(!again.canMove)
    }

    @Test func duplicateDeliveryIsIdempotent() throws {
        let (_, ben, chat) = try playedConversation([3, 4, 5])
        let first = try session(chat.open(chat.last, on: ben))
        let second = try session(chat.open(chat.last, on: ben))
        #expect(first == second)
        #expect(second.notices.isEmpty)
        #expect(ben.controller.ledger.entries.count == 1)
    }

    @Test func outOfOrderArrivalKeepsTheHighestTurn() throws {
        let (_, _, chat) = try playedConversation([3, 4, 5, 6, 0])
        // A third device in the chat (an observer) sees turn 5 first, then a late turn 3.
        let observer = SimulatedDevice(name: "observer")
        _ = try session(chat.open(chat.transcript[4], on: observer))
        let afterLate = try session(chat.open(chat.transcript[2], on: observer))
        #expect(afterLate.snapshot.turnNumber == 5)
        #expect(afterLate.notices == [.openedOlderTurn(openedTurn: 3)])
    }

    @Test func divergentHistoryKeepsTheFirstSeenAndSaysSo() throws {
        let (ava, ben, chat) = try playedConversation([3])
        // Ben answers turn 1 with column 4 and sends it.
        let benTurn = try session(chat.open(chat.last, on: ben))
        chat.insertAndSend(try ben.controller.prepareMove(move(4), in: benTurn, senderToken: nil), from: ben)
        _ = try session(chat.open(chat.last, on: ava))
        // A second, different turn-2 history for the same match reaches Ava
        // (e.g. Ben's other device answered the same bubble differently).
        let forkMatch = try ben.controller.prepareMove(move(6), in: benTurn, senderToken: nil)
        let fork = SentMessage(url: forkMatch.url, sender: ben)
        let shown = try session(chat.open(fork, on: ava))
        #expect(shown.notices == [.historyDiverged])
        guard case .fourInARow(let snapshot) = shown.snapshot else { return }
        #expect(snapshot.match.actions.last == .init(column: 4))
    }

    @Test func reopeningAnUnsentDraftShowsItAsReadyToSend() throws {
        let (ava, ben, chat) = try playedConversation([3])
        let benTurn = try session(chat.open(chat.last, on: ben))
        let draft = try ben.controller.prepareMove(move(5), in: benTurn, senderToken: nil)
        ben.controller.didInsert(draft)

        // Ben taps the bubble sitting in his compose field.
        let pending = try session(ben.controller.screen(for: OpenedMessage(url: draft.url, senderIsLocal: true, isPending: true)))
        #expect(pending.mode == .readyToSend(pending: draft.snapshot))
        #expect(pending.snapshot.turnNumber == 1, "the board shows the official state, not the unsent move")
        #expect(pending.canMove)

        // Opening the official bubble while the draft is pending says the same.
        let official = try session(chat.open(chat.last, on: ben))
        #expect(official.mode == .readyToSend(pending: draft.snapshot))

        // Ben changes his mind: the replacement is built from the official state.
        let replacement = try ben.controller.prepareMove(move(0), in: pending, senderToken: nil)
        #expect(replacement.snapshot.turnNumber == 2)
        guard case .fourInARow(let snapshot) = replacement.snapshot else { return }
        #expect(snapshot.match.actions == [.init(column: 3), .init(column: 0)])

        // The unsent move never became official for Ava.
        _ = ava
        #expect(chat.transcript.count == 1)
    }

    @Test func cancellingSendDropsTheDraft() throws {
        let (_, ben, chat) = try playedConversation([3])
        let benTurn = try session(chat.open(chat.last, on: ben))
        let draft = try ben.controller.prepareMove(move(5), in: benTurn, senderToken: nil)
        ben.controller.didInsert(draft)
        ben.controller.didCancelSending(url: draft.url)
        let after = try session(chat.open(chat.last, on: ben))
        #expect(after.mode == .yourTurn)
        #expect(ben.controller.ledger.entry(for: draft.snapshot.matchID)?.pendingOutgoing == nil)
        #expect(ben.analytics.events.contains(.turnSendCancelled(FourInARow.gameID)))
    }

    @Test func draftSurvivesExtensionTermination() throws {
        let (_, ben, chat) = try playedConversation([3])
        let benTurn = try session(chat.open(chat.last, on: ben))
        let draft = try ben.controller.prepareMove(move(5), in: benTurn, senderToken: nil)
        ben.controller.didInsert(draft)
        ben.relaunch()
        let recovered = try session(chat.open(chat.last, on: ben))
        #expect(recovered.mode == .readyToSend(pending: draft.snapshot))
        #expect(recovered.snapshot.turnNumber == 1)
    }

    @Test func sendWithoutCallbackIsReconciledFromTheTranscript() throws {
        // The extension was killed after insert, so didStartSending never fired,
        // but the user did send. Opening the sent bubble makes it official.
        let (ava, ben, chat) = try playedConversation([3])
        let benTurn = try session(chat.open(chat.last, on: ben))
        let draft = try ben.controller.prepareMove(move(5), in: benTurn, senderToken: nil)
        ben.controller.didInsert(draft)
        ben.relaunch()
        let sent = SentMessage(url: draft.url, sender: ben)
        chat.transcript.append(sent)
        let own = try session(chat.open(sent, on: ben))
        #expect(own.mode == .waitingForOpponent)
        #expect(ben.controller.ledger.entry(for: draft.snapshot.matchID)?.pendingOutgoing == nil)
        #expect(try session(chat.open(sent, on: ava)).mode == .yourTurn)
    }

    @Test func ledgerLossOnlyLosesHints() throws {
        // App deleted and reinstalled, or storage cleared: the transcript still works.
        let (ava, _, chat) = try playedConversation([3, 4])
        try ava.store.save(MatchLedger())
        ava.relaunch()
        let current = try session(chat.open(chat.last, on: ava))
        #expect(current.mode == .yourTurn)
        #expect(current.localSeat == .one)
    }

    @Test func receivedWhileOpenUpdatesOnlyTheCurrentMatch() throws {
        let (ava, ben, chat) = try playedConversation([3])
        let avaWaiting = try session(chat.open(chat.last, on: ava))
        let benTurn = try session(chat.open(chat.last, on: ben))
        let reply = chat.insertAndSend(try ben.controller.prepareMove(move(2), in: benTurn, senderToken: nil), from: ben)
        let incoming = OpenedMessage(url: reply.url, senderIsLocal: false, isPending: false)
        let updated = try session(ava.controller.received(incoming, currentMatch: avaWaiting.snapshot.matchID))
        #expect(updated.mode == .yourTurn)
        #expect(ava.controller.received(incoming, currentMatch: MatchID()) == nil)
    }

    @Test(arguments: [
        URL(string: "https://relay.invalid/play?v=9&g=four-in-a-row&p=e30")!,
        URL(string: "https://relay.invalid/play?v=1&g=mini-golf&p=e30")!,
        URL(string: "https://relay.invalid/play?v=1&g=four-in-a-row&p=bm9wZQ")!,
        URL(string: "https://example.com/")!,
    ])
    func badMessagesShowAProblemScreen(url: URL) {
        let device = SimulatedDevice(name: "x")
        let screen = device.controller.screen(for: OpenedMessage(url: url, senderIsLocal: false, isPending: false))
        guard case .problem = screen else {
            Issue.record("expected problem screen, got \(screen)")
            return
        }
        #expect(device.controller.ledger.entries.isEmpty)
        #expect(device.analytics.events.contains { $0.name == "message_rejected" })
    }

    @Test func persistenceFailuresAreSurfaced() throws {
        struct FailingStore: LedgerStore {
            struct Failure: Error {}
            func load() -> MatchLedger { MatchLedger() }
            func save(_ ledger: MatchLedger) throws { throw Failure() }
        }
        let controller = ConversationController(store: FailingStore())
        guard case .play(let fresh) = controller.startMatch(game: FourInARow.gameID, senderToken: nil) else { return }
        controller.didInsert(try controller.prepareMove(move(1), in: fresh, senderToken: nil))
        #expect(controller.lastPersistenceError != nil)
    }
}

@Suite("Ledger storage")
struct LedgerStorageTests {
    @Test func fileStoreRoundTripsAndToleratesCorruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("ledger.json")
        let store = FileLedgerStore(fileURL: file)
        #expect(store.load() == MatchLedger())

        var ledger = MatchLedger()
        let id = MatchID()
        ledger.update(id, gameID: FourInARow.gameID, now: Date(timeIntervalSince1970: 5)) { $0.localSeat = .two }
        try store.save(ledger)
        #expect(store.load() == ledger)

        try Data("{ not json".utf8).write(to: file)
        #expect(store.load() == MatchLedger())

        try Data(#"{"schemaVersion":99,"entries":{}}"#.utf8).write(to: file)
        #expect(store.load() == MatchLedger())
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func ledgerIsPrunedToTheMostRecentEntries() {
        var ledger = MatchLedger()
        var newest: MatchID?
        for index in 0..<(MatchLedger.maximumEntries + 25) {
            let id = MatchID()
            ledger.update(id, gameID: FourInARow.gameID, now: Date(timeIntervalSince1970: Double(index))) { _ in }
            newest = id
        }
        #expect(ledger.entries.count == MatchLedger.maximumEntries)
        #expect(ledger.entry(for: newest!) != nil)
    }
}

@Suite("Analytics privacy")
struct AnalyticsPrivacyTests {
    @Test func eventsCarryNoIdentifiersOrText() throws {
        let ava = SimulatedDevice(name: "ava")
        let ben = SimulatedDevice(name: "ben")
        let chat = Conversation()
        guard case .play(let fresh) = ava.controller.startMatch(game: FourInARow.gameID, senderToken: ava.token) else { return }
        chat.insertAndSend(try ava.controller.prepareMove(move(3), in: fresh, senderToken: ava.token), from: ava)
        _ = chat.open(chat.last, on: ben)
        let allowedKeys: Set<String> = ["game", "turn", "result", "turns", "presentation", "reason", "opponent"]
        for event in ava.analytics.events + ben.analytics.events {
            #expect(Set(event.properties.keys).isSubset(of: allowedKeys))
            for value in event.properties.values {
                #expect(!value.contains("$"), "participant tokens must never reach analytics")
                #expect(UUID(uuidString: value) == nil, "no identifiers in analytics")
            }
        }
    }
}
