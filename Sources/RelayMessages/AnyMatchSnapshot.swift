import Foundation
import RelayCore
import RelayGames

/// A decoded snapshot of any supported game. A plain enum rather than a type-erased
/// protocol: adding a game adds a case, and the compiler finds every switch to update.
public enum AnyMatchSnapshot: Equatable, Sendable {
    case fourInARow(MatchSnapshot<FourInARow>)
    case darts(MatchSnapshot<Darts>)

    public var header: MatchHeader {
        switch self {
        case .fourInARow(let snapshot): snapshot.match.header
        case .darts(let snapshot): snapshot.match.header
        }
    }

    /// Whether a staged move may be swapped for another before sending. True for board
    /// games; false for skill games, where a throw is committed when it is made, so
    /// cancelling cannot buy a second attempt (docs/GAME_PROTOCOL.md, "Re-roll").
    public var allowsChangingStagedMove: Bool {
        switch self {
        case .fourInARow: true
        case .darts: false
        }
    }

    public var matchID: MatchID { header.matchID }
    public var gameID: GameID { header.gameID }

    public var turnNumber: Int {
        switch self {
        case .fourInARow(let snapshot): snapshot.match.turnNumber
        case .darts(let snapshot): snapshot.match.turnNumber
        }
    }

    public var outcome: GameOutcome {
        switch self {
        case .fourInARow(let snapshot): snapshot.match.outcome
        case .darts(let snapshot): snapshot.match.outcome
        }
    }

    public var producedBy: Seat {
        switch self {
        case .fourInARow(let snapshot): snapshot.match.producedBy
        case .darts(let snapshot): snapshot.match.producedBy
        }
    }

    public func url() throws(MatchCodec.EncodingError) -> URL {
        switch self {
        case .fourInARow(let snapshot): try MatchCodec.url(for: snapshot)
        case .darts(let snapshot): try MatchCodec.url(for: snapshot)
        }
    }

    /// True when `other` is the same match with this history as a prefix.
    public func isPrefix(of other: AnyMatchSnapshot) -> Bool {
        switch (self, other) {
        case (.fourInARow(let a), .fourInARow(let b)): a.match.isPrefix(of: b.match)
        case (.darts(let a), .darts(let b)): a.match.isPrefix(of: b.match)
        default: false
        }
    }

    /// The same match one action earlier, or nil at turn 0.
    public func removingLastAction() -> AnyMatchSnapshot? {
        switch self {
        case .fourInARow(let snapshot): Self.dropLast(snapshot).map(AnyMatchSnapshot.fourInARow)
        case .darts(let snapshot): Self.dropLast(snapshot).map(AnyMatchSnapshot.darts)
        }
    }

    private static func dropLast<Rules: GameRules>(_ snapshot: MatchSnapshot<Rules>) -> MatchSnapshot<Rules>? {
        let match = snapshot.match
        guard !match.actions.isEmpty,
              let previous = try? Match<Rules>.replay(
                  header: match.header,
                  configuration: match.configuration,
                  actions: Array(match.actions.dropLast())
              )
        else { return nil }
        return MatchSnapshot(match: previous, loadouts: snapshot.loadouts)
    }
}

/// Routes a URL to the right game decoder.
public enum GameDecoders {
    public static func isKnown(_ id: GameID) -> Bool {
        id == FourInARow.gameID || id == Darts.gameID
    }

    public static func decode(_ url: URL) throws(ProtocolError) -> AnyMatchSnapshot {
        let game = try MatchCodec.peekGameID(in: url)
        switch game {
        case FourInARow.gameID:
            return .fourInARow(try MatchCodec.decode(url, as: FourInARow.self))
        case Darts.gameID:
            return .darts(try MatchCodec.decode(url, as: Darts.self))
        default:
            throw .unknownGame(game.rawValue)
        }
    }
}
