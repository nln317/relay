import Foundation
import RelayCore

/// Funnel events. Deliberately coarse: no conversation text, no participant
/// identifiers, no contact data, no free-form strings (docs/ANALYTICS.md, docs/PRIVACY.md).
public enum AnalyticsEvent: Equatable, Sendable {
    case extensionOpen(presentation: Presentation)
    case gamePickerOpen
    case gameSelected(GameID)
    case challengePrepared(GameID)
    case turnOpened(GameID, turn: Int)
    /// A move was inserted into the compose field. Not "sent", not "delivered".
    case turnPrepared(GameID, turn: Int)
    /// Messages reported that sending started (`didStartSending`). Not "delivered".
    case turnSendStarted(GameID, turn: Int)
    case turnSendCancelled(GameID)
    case matchCompleted(GameID, result: Result, turns: Int)
    case rematchStarted(GameID)
    case messageRejected(reason: String)
    case practiceStarted(GameID, opponent: String)

    public enum Presentation: String, Sendable {
        case compact, expanded, transcript, unknown
    }

    public enum Result: String, Sendable {
        case localWin, localLoss, draw
    }

    public var name: String {
        switch self {
        case .extensionOpen: "extension_open"
        case .gamePickerOpen: "game_picker_open"
        case .gameSelected: "game_selected"
        case .challengePrepared: "challenge_prepared"
        case .turnOpened: "turn_opened"
        case .turnPrepared: "turn_prepared"
        case .turnSendStarted: "turn_send_started"
        case .turnSendCancelled: "turn_send_cancelled"
        case .matchCompleted: "match_completed"
        case .rematchStarted: "rematch_started"
        case .messageRejected: "message_rejected"
        case .practiceStarted: "practice_started"
        }
    }

    /// Flat, non-identifying properties.
    public var properties: [String: String] {
        switch self {
        case .extensionOpen(let presentation): ["presentation": presentation.rawValue]
        case .gamePickerOpen: [:]
        case .gameSelected(let game), .challengePrepared(let game), .rematchStarted(let game), .turnSendCancelled(let game):
            ["game": game.rawValue]
        case .turnOpened(let game, let turn), .turnPrepared(let game, let turn), .turnSendStarted(let game, let turn):
            ["game": game.rawValue, "turn": String(turn)]
        case .matchCompleted(let game, let result, let turns):
            ["game": game.rawValue, "result": result.rawValue, "turns": String(turns)]
        case .messageRejected(let reason): ["reason": reason]
        case .practiceStarted(let game, let opponent): ["game": game.rawValue, "opponent": opponent]
        }
    }
}

/// Where events go. Milestone 1 ships no network sink at all.
public protocol AnalyticsSink: Sendable {
    func record(_ event: AnalyticsEvent)
}

public struct NoOpAnalytics: AnalyticsSink {
    public init() {}
    public func record(_ event: AnalyticsEvent) {}
}

/// Keeps events in memory. Used by tests and the debug screen.
public final class RecordingAnalytics: AnalyticsSink, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AnalyticsEvent] = []

    public init() {}

    public func record(_ event: AnalyticsEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    public var events: [AnalyticsEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
