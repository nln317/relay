import Foundation
import RelayCore
import RelayGames

/// A decoded snapshot of any supported game. A plain enum rather than a type-erased
/// protocol: adding a game adds a case, and the compiler finds every switch to update.
public enum AnyMatchSnapshot: Equatable, Sendable {
    case fourInARow(MatchSnapshot<FourInARow>)

    public var header: MatchHeader {
        switch self {
        case .fourInARow(let snapshot): snapshot.match.header
        }
    }

    public var matchID: MatchID { header.matchID }
    public var gameID: GameID { header.gameID }

    public var turnNumber: Int {
        switch self {
        case .fourInARow(let snapshot): snapshot.match.turnNumber
        }
    }

    public var outcome: GameOutcome {
        switch self {
        case .fourInARow(let snapshot): snapshot.match.outcome
        }
    }

    public var producedBy: Seat {
        switch self {
        case .fourInARow(let snapshot): snapshot.match.producedBy
        }
    }

    public func url() throws(MatchCodec.EncodingError) -> URL {
        switch self {
        case .fourInARow(let snapshot): try MatchCodec.url(for: snapshot)
        }
    }

    /// True when `other` is the same match with this history as a prefix.
    public func isPrefix(of other: AnyMatchSnapshot) -> Bool {
        switch (self, other) {
        case (.fourInARow(let a), .fourInARow(let b)): a.match.isPrefix(of: b.match)
        }
    }

    /// The same match one action earlier, or nil at turn 0.
    public func removingLastAction() -> AnyMatchSnapshot? {
        switch self {
        case .fourInARow(let snapshot):
            let match = snapshot.match
            guard !match.actions.isEmpty,
                  let previous = try? Match<FourInARow>.replay(
                      header: match.header,
                      configuration: match.configuration,
                      actions: Array(match.actions.dropLast())
                  )
            else { return nil }
            return .fourInARow(MatchSnapshot(match: previous, loadouts: snapshot.loadouts))
        }
    }
}

/// Routes a URL to the right game decoder.
public enum GameDecoders {
    public static func isKnown(_ id: GameID) -> Bool {
        id == FourInARow.gameID
    }

    public static func decode(_ url: URL) throws(ProtocolError) -> AnyMatchSnapshot {
        let game = try MatchCodec.peekGameID(in: url)
        switch game {
        case FourInARow.gameID:
            return .fourInARow(try MatchCodec.decode(url, as: FourInARow.self))
        default:
            throw .unknownGame(game.rawValue)
        }
    }
}
