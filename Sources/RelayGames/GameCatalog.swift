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

    public static let playable: [GameDefinition] = [fourInARow]

    public static func definition(for id: GameID) -> GameDefinition? {
        playable.first { $0.id == id }
    }
}
