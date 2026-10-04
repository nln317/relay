import RelayCore

/// Four in a Row: drop discs into columns; first to line up `connect` in a row,
/// column or diagonal wins. Independently implemented classic mechanic.
public enum FourInARow: GameRules {
    public static let gameID = GameID(constant: "four-in-a-row")
    public static let rulesVersion = RulesVersion(1)

    public struct Configuration: Codable, Equatable, Sendable {
        public var columns: Int
        public var rows: Int
        public var connect: Int

        public static let standard = Configuration(columns: 7, rows: 6, connect: 4)

        public init(columns: Int, rows: Int, connect: Int) {
            self.columns = columns
            self.rows = rows
            self.connect = connect
        }

        private enum CodingKeys: String, CodingKey {
            case columns = "w"
            case rows = "h"
            case connect = "k"
        }
    }

    /// A move: the column (0-based, left to right) to drop a disc into.
    /// Encoded as a bare integer to keep messages small.
    public struct Action: Codable, Equatable, Hashable, Sendable {
        public var column: Int

        public init(column: Int) {
            self.column = column
        }

        public init(from decoder: Decoder) throws {
            column = try decoder.singleValueContainer().decode(Int.self)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(column)
        }
    }

    public enum RuleViolation: Error, Equatable, Sendable {
        case gameOver
        case notYourTurn
        case columnOutOfRange(Int)
        case columnFull(Int)
    }

    public struct Cell: Hashable, Sendable, CustomStringConvertible {
        public var column: Int
        /// 0 is the bottom row.
        public var row: Int

        public init(column: Int, row: Int) {
            self.column = column
            self.row = row
        }

        public var description: String { "(\(column),\(row))" }
    }

    public struct State: Equatable, Sendable {
        public let configuration: Configuration
        /// Column-major: `discs[column][row]`, row 0 at the bottom.
        public private(set) var discs: [[Seat?]]
        public private(set) var outcome: GameOutcome
        /// Every cell that is part of a winning line (more than one line can complete at once).
        public private(set) var winningCells: Set<Cell>
        public private(set) var lastMove: Cell?
        public private(set) var movesPlayed: Int

        init(configuration: Configuration, firstSeat: Seat) {
            self.configuration = configuration
            self.discs = Array(repeating: Array(repeating: nil, count: configuration.rows), count: configuration.columns)
            self.outcome = .inProgress(toAct: firstSeat)
            self.winningCells = []
            self.lastMove = nil
            self.movesPlayed = 0
        }

        public func disc(at cell: Cell) -> Seat? {
            guard contains(cell) else { return nil }
            return discs[cell.column][cell.row]
        }

        public func height(ofColumn column: Int) -> Int {
            guard discs.indices.contains(column) else { return 0 }
            return discs[column].firstIndex(where: { $0 == nil }) ?? configuration.rows
        }

        public func isColumnOpen(_ column: Int) -> Bool {
            discs.indices.contains(column) && height(ofColumn: column) < configuration.rows
        }

        public var openColumns: [Int] {
            (0..<configuration.columns).filter(isColumnOpen)
        }

        func contains(_ cell: Cell) -> Bool {
            (0..<configuration.columns).contains(cell.column) && (0..<configuration.rows).contains(cell.row)
        }

        mutating func place(_ seat: Seat, inColumn column: Int) -> Cell {
            let cell = Cell(column: column, row: height(ofColumn: column))
            discs[cell.column][cell.row] = seat
            movesPlayed += 1
            lastMove = cell
            let line = FourInARow.winningCells(through: cell, for: seat, in: self)
            if !line.isEmpty {
                winningCells = line
                outcome = .won(by: seat)
            } else if movesPlayed == configuration.columns * configuration.rows {
                outcome = .draw
            } else {
                outcome = .inProgress(toAct: seat.opponent)
            }
            return cell
        }
    }

    static let directions: [(dc: Int, dr: Int)] = [(1, 0), (0, 1), (1, 1), (1, -1)]

    public static func maximumActions(for configuration: Configuration) -> Int {
        configuration.columns * configuration.rows
    }

    /// Protocol v1 clients only offer the standard board, but accept sane
    /// variants so custom rules (Milestone 5+) do not need a protocol bump.
    public static func isSupported(_ configuration: Configuration) -> Bool {
        (4...12).contains(configuration.columns)
            && (4...12).contains(configuration.rows)
            && (3...min(configuration.columns, configuration.rows)).contains(configuration.connect)
    }

    public static func initialState(for configuration: Configuration, firstSeat: Seat) -> State {
        State(configuration: configuration, firstSeat: firstSeat)
    }

    public static func apply(_ action: Action, by seat: Seat, to state: State) -> Result<State, RuleViolation> {
        guard let toAct = state.outcome.seatToAct else { return .failure(.gameOver) }
        guard toAct == seat else { return .failure(.notYourTurn) }
        guard (0..<state.configuration.columns).contains(action.column) else {
            return .failure(.columnOutOfRange(action.column))
        }
        guard state.isColumnOpen(action.column) else { return .failure(.columnFull(action.column)) }
        var next = state
        _ = next.place(seat, inColumn: action.column)
        return .success(next)
    }

    public static func outcome(of state: State) -> GameOutcome {
        state.outcome
    }

    /// Cells of every line of at least `connect` discs of `seat` passing through `cell`.
    static func winningCells(through cell: Cell, for seat: Seat, in state: State) -> Set<Cell> {
        var result: Set<Cell> = []
        for direction in directions {
            var line = [cell]
            for sign in [1, -1] {
                var next = Cell(column: cell.column + sign * direction.dc, row: cell.row + sign * direction.dr)
                while state.disc(at: next) == seat {
                    line.append(next)
                    next = Cell(column: next.column + sign * direction.dc, row: next.row + sign * direction.dr)
                }
            }
            if line.count >= state.configuration.connect {
                result.formUnion(line)
            }
        }
        return result
    }
}
