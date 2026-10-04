import Foundation
import RelayCore

/// Version of the message format as a whole (not of any game's rules).
public enum WireProtocol {
    /// The version this build writes.
    public static let currentVersion = 1
    /// The oldest version this build still reads.
    public static let minimumSupportedVersion = 1

    /// Messages URLs are not documented to have a hard size limit, but large URLs
    /// are known to fail. We refuse to write more than this and refuse to read
    /// anything grossly larger. See docs/GAME_PROTOCOL.md, "Size budget".
    public static let maximumEncodedPayloadLength = 4_000
    public static let maximumAcceptedURLLength = 16_000

    /// Placeholder fallback host. Opening the URL on a device without Relay lands
    /// on a web page explaining the game. `.invalid` is reserved (RFC 2606) and
    /// must be replaced with an owned domain before beta (docs/APP_STORE.md).
    public static let fallbackHost = "relay.invalid"
    public static let fallbackPath = "/play"

    enum QueryKey {
        static let version = "v"
        static let game = "g"
        static let payload = "p"
    }
}

/// Everything that can be wrong with a received message. Each case maps to a
/// calm, specific screen; none of them crash.
public enum ProtocolError: Error, Equatable, Sendable {
    case notARelayMessage
    case missingField(String)
    case oversized(length: Int)
    /// Sent by a newer Relay. The user needs to update.
    case unsupportedProtocolVersion(Int)
    /// Older than anything this build can read.
    case obsoleteProtocolVersion(Int)
    /// A game this build does not have (probably added in a later version).
    case unknownGame(String)
    case unsupportedRulesVersion(game: GameID, version: RulesVersion)
    case malformedPayload(String)
    case inconsistentHeader(String)
    /// The move history does not follow the rules. Possibly corrupted or tampered with.
    case illegalHistory(String)

    /// True when updating the app could fix it.
    public var isFixedByUpdating: Bool {
        switch self {
        case .unsupportedProtocolVersion, .unknownGame, .unsupportedRulesVersion: true
        default: false
        }
    }
}

/// Wire form of one match snapshot (protocol v1). Short keys keep URLs small.
/// The game state itself is never sent: receivers rebuild it from the actions.
struct WireEnvelope<Rules: GameRules>: Codable {
    var protocolVersion: Int
    var gameID: GameID
    var rulesVersion: RulesVersion
    var matchID: MatchID
    var firstSeat: Seat
    var turnNumber: Int
    var configuration: Rules.Configuration
    var actions: [Rules.Action]
    var previousMatchID: MatchID?
    var series: SeriesTally?
    var rivalryID: RivalryID?
    /// Equipped cosmetics per seat, keyed "1"/"2".
    var loadouts: [String: CosmeticLoadout]?
    /// Seat one wears seat two's colour. Omitted when false.
    var coloursSwapped: Bool?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "pv"
        case gameID = "g"
        case rulesVersion = "rv"
        case matchID = "m"
        case firstSeat = "f"
        case turnNumber = "n"
        case configuration = "c"
        case actions = "a"
        case previousMatchID = "pm"
        case series = "s"
        case rivalryID = "r"
        case loadouts = "lo"
        case coloursSwapped = "cs"
    }
}

/// Just enough of the envelope to route and version-check before full decoding.
struct WireHeader: Decodable {
    var protocolVersion: Int
    var gameID: String
    var rulesVersion: Int

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "pv"
        case gameID = "g"
        case rulesVersion = "rv"
    }
}

/// A match plus the presentation data that travels with it.
public struct MatchSnapshot<Rules: GameRules>: Equatable, Sendable {
    public var match: Match<Rules>
    public var loadouts: [Seat: CosmeticLoadout]

    public init(match: Match<Rules>, loadouts: [Seat: CosmeticLoadout] = [:]) {
        self.match = match
        self.loadouts = loadouts
    }
}

/// Encodes and decodes match snapshots as Messages URLs.
public enum MatchCodec {
    // MARK: Encoding

    public enum EncodingError: Error, Equatable {
        case payloadTooLarge(length: Int)
        case encodingFailed
    }

    public static func url<Rules: GameRules>(for snapshot: MatchSnapshot<Rules>) throws(EncodingError) -> URL {
        let match = snapshot.match
        let envelope = WireEnvelope<Rules>(
            protocolVersion: WireProtocol.currentVersion,
            gameID: match.header.gameID,
            rulesVersion: match.header.rulesVersion,
            matchID: match.header.matchID,
            firstSeat: match.header.firstSeat,
            turnNumber: match.turnNumber,
            configuration: match.configuration,
            actions: match.actions,
            previousMatchID: match.header.previousMatchID,
            series: match.header.series == .empty ? nil : match.header.series,
            rivalryID: match.header.rivalryID,
            loadouts: snapshot.loadouts.isEmpty
                ? nil
                : Dictionary(uniqueKeysWithValues: snapshot.loadouts.map { (String($0.key.rawValue), $0.value) }),
            coloursSwapped: match.header.coloursSwapped ? true : nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(envelope)
        } catch {
            throw .encodingFailed
        }
        let payload = Base64URL.encode(data)
        guard payload.count <= WireProtocol.maximumEncodedPayloadLength else {
            throw .payloadTooLarge(length: payload.count)
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = WireProtocol.fallbackHost
        components.path = WireProtocol.fallbackPath
        components.queryItems = [
            URLQueryItem(name: WireProtocol.QueryKey.version, value: String(WireProtocol.currentVersion)),
            URLQueryItem(name: WireProtocol.QueryKey.game, value: match.header.gameID.rawValue),
            URLQueryItem(name: WireProtocol.QueryKey.payload, value: payload),
        ]
        guard let url = components.url else { throw .encodingFailed }
        return url
    }

    // MARK: Decoding

    /// Reads the outer fields without decoding the game. Use to pick a game decoder.
    public static func peekGameID(in url: URL) throws(ProtocolError) -> GameID {
        let fields = try outerFields(of: url)
        return fields.game
    }

    /// Fully decodes and verifies a snapshot for a known game.
    /// Every action is replayed through the rules; nothing in the payload is trusted.
    public static func decode<Rules: GameRules>(_ url: URL, as rules: Rules.Type) throws(ProtocolError) -> MatchSnapshot<Rules> {
        let fields = try outerFields(of: url)
        guard fields.game == Rules.gameID else { throw .inconsistentHeader("game does not match decoder") }

        let header: WireHeader
        do {
            header = try JSONDecoder().decode(WireHeader.self, from: fields.payload)
        } catch {
            throw .malformedPayload("header")
        }
        guard header.protocolVersion == fields.version else { throw .inconsistentHeader("protocol version") }
        guard header.gameID == fields.game.rawValue else { throw .inconsistentHeader("game id") }
        let rulesVersion = RulesVersion(header.rulesVersion)
        guard rulesVersion == Rules.rulesVersion else {
            if rulesVersion > Rules.rulesVersion {
                throw .unsupportedRulesVersion(game: Rules.gameID, version: rulesVersion)
            }
            throw .malformedPayload("rules version \(header.rulesVersion) is not readable")
        }

        let envelope: WireEnvelope<Rules>
        do {
            envelope = try JSONDecoder().decode(WireEnvelope<Rules>.self, from: fields.payload)
        } catch {
            throw .malformedPayload("envelope")
        }
        guard envelope.turnNumber == envelope.actions.count else {
            throw .inconsistentHeader("turn number \(envelope.turnNumber) but \(envelope.actions.count) actions")
        }
        if let series = envelope.series, !series.isValid { throw .malformedPayload("series") }
        if let previous = envelope.previousMatchID, previous == envelope.matchID {
            throw .inconsistentHeader("match is its own rematch")
        }

        var loadouts: [Seat: CosmeticLoadout] = [:]
        for (key, loadout) in envelope.loadouts ?? [:] {
            // Cosmetics are optional decoration: drop bad entries instead of failing the move.
            guard let raw = Int(key), let seat = Seat(rawValue: raw), loadout.isWithinLimits else { continue }
            loadouts[seat] = loadout
        }

        let matchHeader = MatchHeader(
            matchID: envelope.matchID,
            gameID: envelope.gameID,
            rulesVersion: envelope.rulesVersion,
            firstSeat: envelope.firstSeat,
            previousMatchID: envelope.previousMatchID,
            series: envelope.series ?? .empty,
            rivalryID: envelope.rivalryID,
            coloursSwapped: envelope.coloursSwapped ?? false
        )
        do {
            let match = try Match<Rules>.replay(header: matchHeader, configuration: envelope.configuration, actions: envelope.actions)
            return MatchSnapshot(match: match, loadouts: loadouts)
        } catch {
            switch error {
            case .unsupportedConfiguration:
                throw .malformedPayload("configuration not supported")
            default:
                throw .illegalHistory(String(describing: error))
            }
        }
    }

    struct OuterFields {
        var version: Int
        var game: GameID
        var payload: Data
    }

    static func outerFields(of url: URL) throws(ProtocolError) -> OuterFields {
        let absolute = url.absoluteString
        guard absolute.count <= WireProtocol.maximumAcceptedURLLength else {
            throw .oversized(length: absolute.count)
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == WireProtocol.fallbackHost,
              components.path == WireProtocol.fallbackPath
        else {
            throw .notARelayMessage
        }
        let items = components.queryItems ?? []
        func value(_ name: String) throws(ProtocolError) -> String {
            let matches = items.filter { $0.name == name }
            guard matches.count == 1, let value = matches[0].value, !value.isEmpty else {
                throw .missingField(name)
            }
            return value
        }

        guard let version = Int(try value(WireProtocol.QueryKey.version)) else {
            throw .malformedPayload("version")
        }
        if version > WireProtocol.currentVersion { throw .unsupportedProtocolVersion(version) }
        if version < WireProtocol.minimumSupportedVersion { throw .obsoleteProtocolVersion(version) }

        let rawGame = try value(WireProtocol.QueryKey.game)
        guard let game = GameID(rawGame) else { throw .malformedPayload("game id") }
        guard GameDecoders.isKnown(game) else { throw .unknownGame(rawGame) }

        let encodedPayload = try value(WireProtocol.QueryKey.payload)
        guard let payload = Base64URL.decode(encodedPayload) else { throw .malformedPayload("payload encoding") }
        return OuterFields(version: version, game: game, payload: payload)
    }
}

/// RFC 4648 base64url without padding.
enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard string.allSatisfy({ allowed.contains($0) }) else { return nil }
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder == 1 { return nil }
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }
}
