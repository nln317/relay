# Decisions

Newest last. Each: decision, reasoning, consequences.

**D-001 Working name "Relay".** Module names in the brief are Relay*, so the product is
called Relay until branding (M4). Bundle prefix `dev.relay` and App Group
`group.dev.relay.shared` are placeholders the owner replaces with their own identifiers.

**D-002 Pure Swift package for everything decidable.** Rules, protocol and Messages
lifecycle logic live in RelayKit and never import Messages, UIKit or StoreKit. Lets the most
important logic be tested on Linux (where M0/M1 were written) and keeps views thin.

**D-003 State travels in the message; no server.** Every message carries the full action
history (≤ 5,000-character URL). No accounts, no backend, no network permission. Apple
suggests a server for session races; we instead detect races (turn numbers, prefix checks).
Revisit for Rivalry Sets across devices or group gauntlets.

**D-004 Small `GameRules` protocol, built from one game.** Per brief §26. Extract shared
concepts when Darts exists.

**D-005 Strict alternation assumed for now.** `Match.lastActor` derives the actor from the
action index. 8-Ball and Cup Pong break this; generalise in M2/M3 by letting rules report
the actor of each action.

**D-006 Replay, don't trust.** Receivers rebuild state from actions, so corrupted or
tampered histories are rejected and results are computed, not read. Physics games will need
deterministic simulation to keep this property (ARCHITECTURE.md).

**D-007 The challenger makes the first move.** GamePigeon's invite carries no move, costing
a round trip before anything happens. Ours puts the first move in the challenge with the
same number of taps. Rematches alternate who moves first, so a rematch started by the
previous first mover is a no-move challenge. Reversible via
`ConversationController.challengerMovesFirst`.

**D-008 Seats are positional, not identity-bound.** Participant IDs are per device and
change on reinstall (Apple docs). Seat = derived from who produced the snapshot and whether
this device sent it. Limit: group chats and multi-device accounts (GAME_PROTOCOL.md).

**D-009 One MSSession per match, new session per rematch.** Moves replace the previous
bubble (short transcript); each finished game leaves its result bubble behind.

**D-010 Placeholder visual identity.** Dark slate board with Ember (coral, ring mark) and
Tide (teal, dot mark) discs. Chosen to be clearly not GamePigeon's look and colour-blind
safe. Replaced in M4.

**D-011 App targets in Swift 5 mode, package in Swift 6.** The app and extension sources
were written where they could not be compiled. Swift 6 strict concurrency errors in UIKit /
Messages callbacks would block the first Mac build for little gain, so they compile in
Swift 5 mode with complete checking as warnings. Move to Swift 6 after a green Mac build.

**D-012 Move commits immediately, then auto-inserts after 450 ms.** Tapping a column drops
the disc and stages the message without an extra "Send" button inside the extension (the
Messages send button is the confirmation). Changing your mind = reopen the staged bubble
and tap another column. Keeps tap count at GamePigeon parity or better.

**D-013 Compact presentation shows a summary card, not the board.** Apple advises against
cramped interaction in compact; the board needs height. Picking a game requests expanded.

**D-014 XcodeGen spec plus committed project.** `project.yml` is the source; the generated
`Relay.xcodeproj` is committed so XcodeGen is optional for contributors.

**D-015 No analytics network sink yet.** The event funnel is defined and tested for
privacy, but nothing leaves the device until a provider and privacy policy are chosen.

**D-016 Neutral bubble captions, no `$participant` tokens.** Captions appear identically
to both players. The first version wrote "`$<participant id>` wins!", relying on Messages
substituting names; in the iOS 26.5 simulator the raw token showed in the compose-field
preview. Captions now say what happened without naming anyone; Messages already shows who
sent each bubble. Revisit on a real two-device test.

**D-017 Generate the Xcode project with XcodeGen's setting presets.** The first generated
project lacked presets (PRODUCT_NAME etc.) because the Linux XcodeGen binary could not find
them, and Xcode failed with "Multiple commands produce .app". Regenerated with presets.

**D-018 In-progress bubbles say "Your turn".** Owner request (2026-10-04): use GamePigeon's
familiar wording instead of a move counter. The text addresses the recipient; the sender's
own copy reads the same, which matches the benchmark. Finished games still say
"Game over · four in a row!" or "Game over · it's a draw".

**D-019 The seat this device already played wins over participant identifiers.** In the
iOS 26.5 simulator, the sender's own sent bubble reported a sender identifier different from
the local one, so it opened in the opponent's seat and allowed a move as them. The ledger's
stored seat is now authoritative once set, and is never overwritten by a later open.
Participant identifiers only decide the seat on first contact with a match.

**D-020 After staging a move, the board stays interactive.** The extension shows the
official position with the staged move as a ghost; tapping another column replaces the
staged message (same MSSession). Previously the board locked after insert, contradicting
the "tap another column to change it" copy.
