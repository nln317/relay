import Foundation
import RelayCore
import RelayGames
@testable import RelayMessages
import Testing

typealias C4 = FourInARow

func makeMatch(_ columns: [Int], firstSeat: Seat = .one, series: SeriesTally = .empty) throws -> Match<C4> {
    let header = MatchHeader(gameID: C4.gameID, rulesVersion: C4.rulesVersion, firstSeat: firstSeat, series: series)
    return try Match<C4>.replay(header: header, configuration: .standard, actions: columns.map(C4.Action.init(column:)))
}

/// Builds a URL with arbitrary JSON in the payload, for tampering tests.
func rawURL(json: String, version: String? = "1", game: String? = "four-in-a-row", host: String = WireProtocol.fallbackHost) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = host
    components.path = WireProtocol.fallbackPath
    var items: [URLQueryItem] = []
    if let version { items.append(URLQueryItem(name: "v", value: version)) }
    if let game { items.append(URLQueryItem(name: "g", value: game)) }
    items.append(URLQueryItem(name: "p", value: Base64URL.encode(Data(json.utf8))))
    components.queryItems = items
    return components.url!
}

let validJSON = #"{"a":[3,3],"c":{"h":6,"k":4,"w":7},"f":1,"g":"four-in-a-row","m":"6F1B2C3D-0000-4000-8000-000000000001","n":2,"pv":1,"rv":1}"#

@Suite("Wire protocol")
struct WireProtocolTests {
    @Test func roundTripPreservesEverything() throws {
        let match = try makeMatch([3, 4, 3], firstSeat: .two, series: SeriesTally(seatOneWins: 2, seatTwoWins: 1, draws: 1))
        let loadouts: [Seat: CosmeticLoadout] = [.one: CosmeticLoadout(items: ["disc": CosmeticID("neon-disc")!])]
        let snapshot = MatchSnapshot(match: match, loadouts: loadouts)
        let url = try MatchCodec.url(for: snapshot)
        let decoded = try MatchCodec.decode(url, as: C4.self)
        #expect(decoded == snapshot)
        #expect(try GameDecoders.decode(url) == .fourInARow(snapshot))
        #expect(url.scheme == "https")
    }

    @Test func handwrittenV1PayloadDecodes() throws {
        // Freezes the v1 wire format: if this breaks, old messages in people's
        // conversations stop opening. Bump the protocol version instead.
        let snapshot = try MatchCodec.decode(rawURL(json: validJSON), as: C4.self)
        #expect(snapshot.match.actions == [.init(column: 3), .init(column: 3)])
        #expect(snapshot.match.header.matchID == MatchID(string: "6F1B2C3D-0000-4000-8000-000000000001"))
        #expect(snapshot.match.outcome == .inProgress(toAct: .one))
        #expect(snapshot.match.header.coloursSwapped == false)
    }

    @Test func longestDartsGameFitsTheSizeBudget() throws {
        // Every visit three darts at the far edge of reach, all misses, for the longest preset.
        let configuration = Darts.Configuration(startingScore: 301, rounds: 12)
        let wide = Darts.Action(hits: Array(repeating: Darts.Hit(x: -3_999, y: -3_999), count: 3))
        let header = MatchHeader(gameID: Darts.gameID, rulesVersion: Darts.rulesVersion)
        let match = try Match<Darts>.replay(header: header, configuration: configuration, actions: Array(repeating: wide, count: 24))
        #expect(match.outcome.isFinished)
        let url = try MatchCodec.url(for: MatchSnapshot(match: match))
        #expect(url.absoluteString.count < 5_000)
        #expect(try GameDecoders.decode(url) == .darts(MatchSnapshot(match: match)))
    }

    @Test func swappedColoursRoundTrip() throws {
        let header = MatchHeader(gameID: C4.gameID, rulesVersion: C4.rulesVersion, coloursSwapped: true)
        let match = try Match<C4>.replay(header: header, configuration: .standard, actions: [.init(column: 2)])
        let url = try MatchCodec.url(for: MatchSnapshot(match: match))
        #expect(try MatchCodec.decode(url, as: C4.self).match.header.coloursSwapped)
    }

    @Test func fullGameFitsComfortablyInTheSizeBudget() throws {
        let draw = [3, 4, 4, 6, 0, 3, 5, 2, 6, 5, 0, 6, 5, 0, 3, 6, 5, 6, 1, 3, 1, 3, 6, 5, 2, 0, 5, 3, 4, 4, 0, 1, 1, 1, 0, 1, 4, 2, 4, 2, 2, 2]
        var items: [String: CosmeticID] = [:]
        for index in 0..<CosmeticLoadout.maximumSlots { items["slot-\(index)"] = CosmeticID("a-long-cosmetic-name-\(index)")! }
        let loadout = CosmeticLoadout(items: items)
        let snapshot = MatchSnapshot(match: try makeMatch(draw), loadouts: [.one: loadout, .two: loadout])
        let url = try MatchCodec.url(for: snapshot)
        // Apple's documented limit for MSMessage.url is 5,000 characters.
        #expect(url.absoluteString.count < 5_000)
        #expect(try MatchCodec.decode(url, as: C4.self).match.outcome == .draw)
    }

    @Test func newerProtocolAsksForAnUpdate() {
        let url = rawURL(json: validJSON, version: "2")
        #expect(throws: ProtocolError.unsupportedProtocolVersion(2)) { try GameDecoders.decode(url) }
        #expect(ProtocolError.unsupportedProtocolVersion(2).isFixedByUpdating)
    }

    @Test func obsoleteProtocolIsRejected() {
        #expect(throws: ProtocolError.obsoleteProtocolVersion(0)) { try GameDecoders.decode(rawURL(json: validJSON, version: "0")) }
    }

    @Test func unknownGameAsksForAnUpdate() {
        #expect(throws: ProtocolError.unknownGame("mini-golf")) { try GameDecoders.decode(rawURL(json: validJSON, game: "mini-golf")) }
    }

    @Test func newerRulesAskForAnUpdate() {
        let json = validJSON.replacingOccurrences(of: #""rv":1"#, with: #""rv":2"#)
        #expect(throws: ProtocolError.unsupportedRulesVersion(game: C4.gameID, version: RulesVersion(2))) {
            try GameDecoders.decode(rawURL(json: json))
        }
    }

    @Test func foreignURLsAreNotOurs() throws {
        #expect(throws: ProtocolError.notARelayMessage) { try GameDecoders.decode(URL(string: "https://example.com/play?v=1")!) }
        #expect(throws: ProtocolError.notARelayMessage) { try GameDecoders.decode(rawURL(json: validJSON, host: "evil.example")) }
        #expect(throws: ProtocolError.notARelayMessage) { try GameDecoders.decode(URL(string: "data:text/plain,hello")!) }
    }

    @Test func missingFieldsAreReported() {
        #expect(throws: ProtocolError.missingField("v")) { try GameDecoders.decode(rawURL(json: validJSON, version: nil)) }
        #expect(throws: ProtocolError.missingField("g")) { try GameDecoders.decode(rawURL(json: validJSON, game: nil)) }
        #expect(throws: ProtocolError.missingField("p")) {
            try GameDecoders.decode(URL(string: "https://relay.invalid/play?v=1&g=four-in-a-row")!)
        }
    }

    @Test func duplicatedQueryFieldsAreRejected() {
        let url = URL(string: rawURL(json: validJSON).absoluteString + "&v=1")!
        #expect(throws: ProtocolError.missingField("v")) { try GameDecoders.decode(url) }
    }

    @Test(arguments: [
        "not json",
        "",
        "{}",
        "[]",
        #"{"pv":1,"g":"four-in-a-row","rv":1}"#,
        #"{"a":"3","c":{"h":6,"k":4,"w":7},"f":1,"g":"four-in-a-row","m":"6F1B2C3D-0000-4000-8000-000000000001","n":1,"pv":1,"rv":1}"#,
        #"{"a":[3],"c":{"h":6,"k":4,"w":7},"f":3,"g":"four-in-a-row","m":"6F1B2C3D-0000-4000-8000-000000000001","n":1,"pv":1,"rv":1}"#,
        #"{"a":[3],"c":{"h":6,"k":4,"w":7},"f":1,"g":"four-in-a-row","m":"not-a-uuid","n":1,"pv":1,"rv":1}"#,
        #"{"a":[3.5],"c":{"h":6,"k":4,"w":7},"f":1,"g":"four-in-a-row","m":"6F1B2C3D-0000-4000-8000-000000000001","n":1,"pv":1,"rv":1}"#,
        #"{"a":[3],"c":{"h":600,"k":4,"w":7},"f":1,"g":"four-in-a-row","m":"6F1B2C3D-0000-4000-8000-000000000001","n":1,"pv":1,"rv":1}"#,
        #"{"a":[3],"c":{"h":6,"k":4,"w":7},"f":1,"g":"four-in-a-row","m":"6F1B2C3D-0000-4000-8000-000000000001","n":1,"pv":1,"rv":1,"s":{"w1":-4,"w2":0,"d":0}}"#,
    ])
    func malformedPayloadsAreRejected(json: String) {
        #expect(throws: ProtocolError.self) { try GameDecoders.decode(rawURL(json: json)) }
    }

    @Test func badBase64IsRejected() {
        let url = URL(string: "https://relay.invalid/play?v=1&g=four-in-a-row&p=%%%%")
        if let url {
            #expect(throws: ProtocolError.self) { try GameDecoders.decode(url) }
        }
        let url2 = URL(string: "https://relay.invalid/play?v=1&g=four-in-a-row&p=abc$def")!
        #expect(throws: ProtocolError.malformedPayload("payload encoding")) { try GameDecoders.decode(url2) }
    }

    @Test func truncatedPayloadIsRejected() throws {
        let good = try MatchCodec.url(for: MatchSnapshot(match: try makeMatch([3, 3, 4])))
        let truncated = URL(string: String(good.absoluteString.dropLast(9)))!
        #expect(throws: ProtocolError.self) { try GameDecoders.decode(truncated) }
    }

    @Test func headerMismatchesAreRejected() {
        let json = validJSON.replacingOccurrences(of: #""pv":1"#, with: #""pv":0"#)
        #expect(throws: ProtocolError.inconsistentHeader("protocol version")) { try GameDecoders.decode(rawURL(json: json)) }
        let wrongCount = validJSON.replacingOccurrences(of: #""n":2"#, with: #""n":5"#)
        #expect(throws: ProtocolError.inconsistentHeader("turn number 5 but 2 actions")) { try GameDecoders.decode(rawURL(json: wrongCount)) }
        let selfRematch = validJSON.replacingOccurrences(of: #""f":1"#, with: #""f":1,"pm":"6F1B2C3D-0000-4000-8000-000000000001""#)
        #expect(throws: ProtocolError.inconsistentHeader("match is its own rematch")) { try GameDecoders.decode(rawURL(json: selfRematch)) }
    }

    @Test func illegalHistoryIsRejected() {
        let overfull = validJSON
            .replacingOccurrences(of: #""a":[3,3]"#, with: #""a":[3,3,3,3,3,3,3]"#)
            .replacingOccurrences(of: #""n":2"#, with: #""n":7"#)
        #expect(throws: ProtocolError.self) { try GameDecoders.decode(rawURL(json: overfull)) }
        do {
            _ = try GameDecoders.decode(rawURL(json: overfull))
        } catch {
            guard case .illegalHistory = error else {
                Issue.record("expected illegalHistory, got \(error)")
                return
            }
        }
        let movesAfterWin = validJSON
            .replacingOccurrences(of: #""a":[3,3]"#, with: #""a":[0,0,1,1,2,2,3,4]"#)
            .replacingOccurrences(of: #""n":2"#, with: #""n":8"#)
        #expect(throws: ProtocolError.self) { try GameDecoders.decode(rawURL(json: movesAfterWin)) }
    }

    @Test func oversizedURLsAreRejectedBeforeParsing() {
        let huge = URL(string: "https://relay.invalid/play?v=1&g=four-in-a-row&p=" + String(repeating: "A", count: 20_000))!
        #expect(throws: ProtocolError.oversized(length: huge.absoluteString.count)) { try GameDecoders.decode(huge) }
    }

    @Test func badCosmeticsAreDroppedNotFatal() throws {
        let json = validJSON.replacingOccurrences(
            of: #""f":1"#,
            with: #""f":1,"lo":{"1":{"items":{"disc":"neon-disc"}},"7":{"items":{}},"2":{"items":{"Bad Slot":"x"}}}"#
        )
        let snapshot = try MatchCodec.decode(rawURL(json: json), as: C4.self)
        #expect(snapshot.loadouts == [.one: CosmeticLoadout(items: ["disc": CosmeticID("neon-disc")!])])
    }

    @Test func randomGarbageNeverCrashes() {
        var rng = SeededGenerator(seed: 99)
        for _ in 0..<2_000 {
            let length = Int.random(in: 0..<300, using: &rng)
            let bytes = (0..<length).map { _ in UInt8.random(in: 0...255, using: &rng) }
            let payload = Base64URL.encode(Data(bytes))
            let url = URL(string: "https://relay.invalid/play?v=1&g=four-in-a-row&p=\(payload)")!
            #expect(throws: ProtocolError.self) { try GameDecoders.decode(url) }
        }
    }

    @Test func mutatedValidPayloadsNeverCrash() throws {
        var rng = SeededGenerator(seed: 7)
        let base = Array(validJSON.utf8)
        for _ in 0..<3_000 {
            var bytes = base
            for _ in 0..<Int.random(in: 1...4, using: &rng) {
                bytes[Int.random(in: 0..<bytes.count, using: &rng)] = UInt8.random(in: 32...126, using: &rng)
            }
            let url = rawURL(json: String(decoding: bytes, as: UTF8.self))
            // Either a clean decode of a legal game or a ProtocolError. Never a crash.
            if let snapshot = try? GameDecoders.decode(url) {
                #expect(snapshot.turnNumber <= 42)
            }
        }
    }

    @Test func base64URLRoundTrips() {
        for length in 0..<40 {
            let data = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 &* 37) })
            #expect(Base64URL.decode(Base64URL.encode(data)) == data)
        }
        #expect(Base64URL.decode("A") == nil)
    }
}
