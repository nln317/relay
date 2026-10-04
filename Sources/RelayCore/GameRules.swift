/// A deterministic, turn-based rules engine.
///
/// Deliberately small: it is shaped by one real game (Four in a Row) and the
/// known needs of the next two (Darts, 8-Ball). Grow it when a second game
/// proves a need, not before. See docs/DECISIONS.md, D-004.
///
/// Requirements on conforming types:
/// - `apply` must be a pure function: same state + action + seat gives the same result
///   on every device and every run. This is what lets a message carry only the
///   action history and each device rebuild and verify the state itself.
/// - Nothing cosmetic may be an input. Cosmetics never reach the rules.
public protocol GameRules: Sendable {
    associatedtype Configuration: Codable & Equatable & Sendable
    associatedtype State: Equatable & Sendable
    associatedtype Action: Codable & Equatable & Sendable
    associatedtype RuleViolation: Error & Equatable & Sendable

    static var gameID: GameID { get }
    static var rulesVersion: RulesVersion { get }
    /// Upper bound on actions in one match. Checked before replaying untrusted history.
    static func maximumActions(for configuration: Configuration) -> Int

    /// Returns false for configurations a peer could send that this client cannot honour.
    static func isSupported(_ configuration: Configuration) -> Bool
    static func initialState(for configuration: Configuration, firstSeat: Seat) -> State
    static func apply(_ action: Action, by seat: Seat, to state: State) -> Result<State, RuleViolation>
    static func outcome(of state: State) -> GameOutcome
}
