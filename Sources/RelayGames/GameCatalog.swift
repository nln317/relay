import RelayCore

/// How a game appears in the picker. Presentation metadata only.
public struct GameDefinition: Equatable, Sendable, Identifiable {
    public enum Category: String, Sendable, CaseIterable {
        case board, skill, word
    }

    public var id: GameID
    public var displayName: String
    public var tagline: String
    public var category: Category
    public var typicalMinutes: ClosedRange<Int>
    /// SF Symbol used until original artwork exists (Milestone 4).
    public var symbolName: String

    public init(id: GameID, displayName: String, tagline: String, category: Category, typicalMinutes: ClosedRange<Int>, symbolName: String) {
        self.id = id
        self.displayName = displayName
        self.tagline = tagline
        self.category = category
        self.typicalMinutes = typicalMinutes
        self.symbolName = symbolName
    }
}

/// The games this build can play. Only playable games are listed: the picker
/// never shows "coming soon" filler (docs/GAME_ROADMAP.md).
public enum GameCatalog {
    public static let fourInARow = GameDefinition(
        id: FourInARow.gameID,
        displayName: "Four in a Row",
        tagline: "Line up four before they do.",
        category: .board,
        typicalMinutes: 2...6,
        symbolName: "circle.grid.3x3.fill"
    )

    public static let darts = GameDefinition(
        id: Darts.gameID,
        displayName: "Darts",
        tagline: "Count down from 101. Hit zero exactly to win.",
        category: .skill,
        typicalMinutes: 3...8,
        symbolName: "target"
    )

    public static let eightBall = GameDefinition(
        id: EightBall.gameID,
        displayName: "8 Ball",
        tagline: "Sink your group, then the 8.",
        category: .skill,
        typicalMinutes: 5...15,
        symbolName: "8.circle.fill"
    )

    public static let cupPong = GameDefinition(
        id: CupPong.gameID,
        displayName: "Cup Pong",
        tagline: "Sink all their cups first.",
        category: .skill,
        typicalMinutes: 3...8,
        symbolName: "cup.and.saucer.fill"
    )

    public static let playable: [GameDefinition] = [eightBall, cupPong, fourInARow, darts]

    public static func definition(for id: GameID) -> GameDefinition? {
        playable.first { $0.id == id }
    }
}
