/// The cosmetics one player has equipped for one match, carried in the message
/// so the opponent can render them without owning them ("permission to equip,
/// not permission to render"; docs/MONETISATION.md).
///
/// Cosmetics are presentation only. Nothing here is ever passed to `GameRules`.
public struct CosmeticLoadout: Codable, Equatable, Sendable {
    /// Slot name (e.g. "disc", "board", "result-card") to item id.
    public var items: [String: CosmeticID]

    public static let none = CosmeticLoadout(items: [:])
    public static let maximumSlots = 12

    public init(items: [String: CosmeticID]) {
        self.items = items
    }

    /// Unknown slots and ids are kept but rendered as defaults by the UI. Oversized
    /// loadouts from a misbehaving peer are rejected so they cannot bloat storage.
    public var isWithinLimits: Bool {
        items.count <= CosmeticLoadout.maximumSlots
            && items.keys.allSatisfy { GameID.isValid($0) }
    }
}
