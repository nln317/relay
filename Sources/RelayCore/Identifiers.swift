import Foundation

/// Identifies one match (one game from challenge to result). A rematch is a new match.
public struct MatchID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    /// Parses an untrusted string. Returns nil instead of trapping.
    public init?(string: String) {
        guard let uuid = UUID(uuidString: string) else { return nil }
        self.rawValue = uuid
    }

    public var description: String { rawValue.uuidString }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let uuid = UUID(uuidString: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid match id")
        }
        self.rawValue = uuid
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.uuidString)
    }
}

/// Identifies a Rivalry Set (a multi-game series). Reserved in protocol v1; unused until Milestone 5.
public struct RivalryID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init?(string: String) {
        guard let uuid = UUID(uuidString: string) else { return nil }
        self.rawValue = uuid
    }

    public var description: String { rawValue.uuidString }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let uuid = UUID(uuidString: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid rivalry id")
        }
        self.rawValue = uuid
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.uuidString)
    }
}

/// A short, stable, URL-safe slug naming a game, e.g. `four-in-a-row`.
/// Validated on construction because game ids arrive from other devices.
public struct GameID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public static let maximumLength = 32

    public init?(_ rawValue: String) {
        guard GameID.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// For compile-time constants only. Traps on an invalid literal, which is a programmer error.
    public init(constant: StaticString) {
        let value = constant.description
        precondition(GameID.isValid(value), "Invalid GameID constant \(value)")
        self.rawValue = value
    }

    public static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= maximumLength else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
        }
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let id = GameID(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid game id")
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Version of one game's rules. Bumped whenever the same action history could
/// produce a different result, so two devices never silently disagree.
public struct RulesVersion: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: RulesVersion, rhs: RulesVersion) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String { "r\(rawValue)" }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Identifies a cosmetic item. Unknown ids received from a newer client render
/// as the default cosmetic, never as an error.
public struct CosmeticID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(_ rawValue: String) {
        guard GameID.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let id = CosmeticID(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid cosmetic id")
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
