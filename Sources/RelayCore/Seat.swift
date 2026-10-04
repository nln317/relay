/// A position in a two-player match. Seat one is always the player who created
/// the challenge; who moves first is a separate setting (`MatchHeader.firstSeat`).
///
/// Seats are deliberately not tied to Messages participant identifiers, which are
/// local to each device. See docs/GAME_PROTOCOL.md, "Who am I?".
public enum Seat: Int, Codable, CaseIterable, Sendable, CustomStringConvertible {
    case one = 1
    case two = 2

    public var opponent: Seat {
        switch self {
        case .one: .two
        case .two: .one
        }
    }

    public var description: String {
        switch self {
        case .one: "seat 1"
        case .two: "seat 2"
        }
    }
}

/// The outcome of a game as far as the rules know.
public enum GameOutcome: Equatable, Sendable {
    case inProgress(toAct: Seat)
    case won(by: Seat)
    case draw

    public var isFinished: Bool {
        if case .inProgress = self { return false }
        return true
    }

    public var seatToAct: Seat? {
        if case .inProgress(let seat) = self { return seat }
        return nil
    }

    public var winner: Seat? {
        if case .won(let seat) = self { return seat }
        return nil
    }
}

/// Wins and draws across a chain of rematches between the same two people,
/// expressed in the seat numbering of the match that carries it.
/// It travels inside the message, so it needs no identity system to be correct.
public struct SeriesTally: Codable, Equatable, Sendable {
    public var seatOneWins: Int
    public var seatTwoWins: Int
    public var draws: Int

    public static let empty = SeriesTally(seatOneWins: 0, seatTwoWins: 0, draws: 0)
    public static let maximumGames = 10_000

    public init(seatOneWins: Int, seatTwoWins: Int, draws: Int) {
        self.seatOneWins = seatOneWins
        self.seatTwoWins = seatTwoWins
        self.draws = draws
    }

    public var gamesPlayed: Int { seatOneWins + seatTwoWins + draws }

    public var isValid: Bool {
        seatOneWins >= 0 && seatTwoWins >= 0 && draws >= 0 && gamesPlayed <= SeriesTally.maximumGames
    }

    public func wins(for seat: Seat) -> Int {
        seat == .one ? seatOneWins : seatTwoWins
    }

    public func recording(_ outcome: GameOutcome) -> SeriesTally {
        var next = self
        switch outcome {
        case .won(.one): next.seatOneWins += 1
        case .won(.two): next.seatTwoWins += 1
        case .draw: next.draws += 1
        case .inProgress: break
        }
        return next
    }

    /// The same tally with seats renumbered, used when a rematch swaps who is seat one.
    public var swapped: SeriesTally {
        SeriesTally(seatOneWins: seatTwoWins, seatTwoWins: seatOneWins, draws: draws)
    }

    private enum CodingKeys: String, CodingKey {
        case seatOneWins = "w1"
        case seatTwoWins = "w2"
        case draws = "d"
    }
}
