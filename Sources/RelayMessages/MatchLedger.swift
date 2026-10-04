import Foundation
import RelayCore

/// This device's memory of matches it has seen, kept so the extension can
/// recover after being terminated and can tell an old bubble from the latest one.
///
/// It separates four things that must never be confused (docs/GAME_PROTOCOL.md, "Draft recovery"):
/// 1. the last official state: the highest turn known to be in the transcript,
///    either received from the opponent or seen being sent from this device;
/// 2. the current local draft: a move chosen but not yet inserted (`draft`). Four in a Row
///    commits a move and inserts it in one step, so it has none. A Darts visit is built
///    dart by dart and each throw is committed here the moment it is made, so closing
///    the extension or deleting the staged message can never buy a re-throw;
/// 3. a completed but unsent action: inserted into the compose field, not yet sent
///    (`pendingOutgoing`). Never treated as official;
/// 4. the last locally known outgoing state: `official` with source `.sentFromThisDevice`.
///    "Sent" means Messages started sending it. It does not mean delivered or read.
public struct MatchLedger: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maximumEntries = 200

    public struct StoredSnapshot: Codable, Equatable, Sendable {
        public enum Source: String, Codable, Sendable {
            case received
            case sentFromThisDevice
            case insertedNotSent
        }

        public var url: URL
        public var turnNumber: Int
        public var source: Source

        public init(url: URL, turnNumber: Int, source: Source) {
            self.url = url
            self.turnNumber = turnNumber
            self.source = source
        }
    }

    /// Part or all of this device's next action, committed before it is sent.
    public struct Draft: Codable, Equatable, Sendable {
        /// The official turn this draft continues from; stale once the match moves on.
        public var turnNumber: Int
        /// The game's own JSON encoding of the (possibly partial) action.
        public var action: Data

        public init(turnNumber: Int, action: Data) {
            self.turnNumber = turnNumber
            self.action = action
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var matchID: MatchID
        public var gameID: GameID
        public var official: StoredSnapshot?
        public var pendingOutgoing: StoredSnapshot?
        public var draft: Draft?
        /// The seat this device plays in this match, once known.
        public var localSeat: Seat?
        /// The match this one is a rematch of, if any.
        public var previousMatchID: MatchID?
        /// Set once this device has started a rematch, so the result screen can say so.
        public var rematchMatchID: MatchID?
        public var updatedAt: Date

        public init(matchID: MatchID, gameID: GameID, updatedAt: Date) {
            self.matchID = matchID
            self.gameID = gameID
            self.updatedAt = updatedAt
        }
    }

    public var schemaVersion: Int
    public private(set) var entries: [MatchID: Entry]

    public init() {
        schemaVersion = MatchLedger.schemaVersion
        entries = [:]
    }

    public func entry(for matchID: MatchID) -> Entry? {
        entries[matchID]
    }

    /// A rematch of `matchID` this device knows about, started by either player.
    public func rematch(of matchID: MatchID) -> MatchID? {
        if let own = entries[matchID]?.rematchMatchID { return own }
        return entries.values.first { $0.previousMatchID == matchID }?.matchID
    }

    public mutating func update(_ matchID: MatchID, gameID: GameID, now: Date, _ change: (inout Entry) -> Void) {
        var entry = entries[matchID] ?? Entry(matchID: matchID, gameID: gameID, updatedAt: now)
        change(&entry)
        entry.updatedAt = now
        entries[matchID] = entry
        prune()
    }

    mutating func prune() {
        guard entries.count > MatchLedger.maximumEntries else { return }
        let keep = entries.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(MatchLedger.maximumEntries)
        entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.matchID, $0) })
    }
}

/// Persistence for the ledger. The extension and app share one file in the App Group.
public protocol LedgerStore: Sendable {
    func load() -> MatchLedger
    func save(_ ledger: MatchLedger) throws
}

/// JSON file store with atomic writes. A missing, unreadable or future-schema file
/// yields an empty ledger: losing the ledger only loses recovery hints, never game
/// state, because the transcript messages remain the source of truth.
public struct FileLedgerStore: LedgerStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> MatchLedger {
        guard let data = try? Data(contentsOf: fileURL),
              let ledger = try? JSONDecoder().decode(MatchLedger.self, from: data),
              ledger.schemaVersion == MatchLedger.schemaVersion
        else { return MatchLedger() }
        return ledger
    }

    public func save(_ ledger: MatchLedger) throws {
        let data = try JSONEncoder().encode(ledger)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

/// In-memory store for tests and previews.
public final class InMemoryLedgerStore: LedgerStore, @unchecked Sendable {
    private let lock = NSLock()
    private var ledger: MatchLedger

    public init(_ ledger: MatchLedger = MatchLedger()) {
        self.ledger = ledger
    }

    public func load() -> MatchLedger {
        lock.lock()
        defer { lock.unlock() }
        return ledger
    }

    public func save(_ ledger: MatchLedger) throws {
        lock.lock()
        defer { lock.unlock() }
        self.ledger = ledger
    }
}
