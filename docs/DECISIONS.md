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

**D-021 A debug "two-phone rehearsal" screen stands in for a second device.** The receiver
side could not be exercised in one simulator because Messages there has no second account.
The rehearsal runs two `ConversationController`s with separate ledgers and passes real
message URLs between them, rendering the production views. It is compiled only in Debug and
its results are reported separately from Messages and two-device evidence.

**D-022 Signing identifiers live in one xcconfig.** `Config/Relay.xcconfig` defines
`RELAY_BUNDLE_ID_PREFIX`, `RELAY_APP_GROUP` and an empty `DEVELOPMENT_TEAM`, then includes the
git-ignored `Config/Local.xcconfig`. Bundle ids, entitlements and the extension's
`RelayAppGroup` Info.plist key all derive from those settings, so the App Group the code reads
always matches the one it is entitled to.

**D-023 The app and extension are dark-only for now.** Both force `.preferredColorScheme(.dark)`
because the board, disc colours and bubble art were tuned on one dark palette. A light palette
needs its own contrast checks for the Ember and Tide discs, so it is deferred to the art pass
(M4) rather than shipped untested.

**D-024 Each person keeps their colour across rematches.** Rematches renumber seats (the
initiator becomes seat one, D-007), so colours used to follow the seat and swapped between
games. The header now carries `coloursSwapped` (wire key `cs`, omitted when false), flipped
whenever a seat-two player starts the rematch, and the UI paints seats through a
`SeatPalette`. An additive optional key, so protocol v1 still applies; messages without it
read as unswapped.

**D-025 The App Group is optional.** A free Apple Personal Team cannot sign App Groups, and
in Milestone 1 nothing outside the extension reads the recovery ledger. `RELAY_USE_APP_GROUP
= NO` in `Config/Local.xcconfig` switches both targets to `Config/NoAppGroup.entitlements` and
blanks the extension's `RelayAppGroup`, so the ledger falls back to the extension's own
container. Entitlements files are now hand-written rather than generated by XcodeGen. Turn the
App Group back on before the app needs to read the extension's state (stats, locker).

**D-026 Darts rules: plain countdown.** Start on 201 (101 and 301 are supported variants),
visits of three darts, exact zero wins, below zero is a bust that scores nothing. No "double
out": public reviews call GamePigeon's Darts rules confusing, and one sentence of rules beats
fidelity to pub darts. A round cap (10 rounds at 201) keeps games short; after it the lower
score wins, equal scores draw.

**D-027 A Darts action is a whole visit of landing points.** Strict alternation (D-005) still
holds, so Darts needed no change to `Match`. The rules score landing points with integer
maths and precomputed sector edges, so every device agrees on every score. Where a dart
lands is decided on the thrower's device (aim, sway, scatter); a modified client could fake
it, which is the accepted limit of a serverless design (ARCHITECTURE.md).

**D-028 Darts are committed as they are thrown.** Each dart goes into the ledger draft before
its landing is shown. Reopening the extension resumes the visit; deleting the staged message
keeps the visit, which can only be re-sent unchanged ("Send your darts"). Skill games cannot
swap a staged move (`allowsChangingStagedMove`), unlike Four in a Row (D-020).

**D-029 Throw by flicking a dart held below the board** (revised 2026-10-04 after device
feedback; it first used drag-to-aim with a drifting sight). The player swipes the dart up:
release speed sets how high it flies along a square-root curve (a soft flick drops low,
about 3 board widths a second reaches the bull (made heavier again on 2026-10-04), and extra force adds less and less
height so hard flicks do not overshoot easily), the line of the whole swipe sets left and right (mostly start to release, a fifth
release velocity, with leans under about 3 degrees flying straight, because reading only
the release made a thumb's natural hook throw crooked; the dart follows only half the
finger's sideways drift and leans along the swipe while held; Nathan, 2026-10-04),
and a small scatter is added, more for a wild flick. Measured in board widths so every
screen size feels the same. The landing point is committed when the dart leaves the hand;
the flight is animation only. The board hangs on a wall, so an over-hit or sliced
throw visibly misses and sticks in the wall. Every dart (the bot's and an arriving
opponent visit too) flies in on a shallow arc, shrinking with distance, and stays stuck
in the board until the next player picks up their dart, when the board clears (as in the
classic game); the scores and visit strip update as it lands. The dart in hand rests still (no idle sway, Nathan 2026-10-04). VoiceOver keeps "Throw at treble 20"-style actions. Constants
live in `DartsAim` and are expected to be tuned after more play.

**D-030 Our own dartboard look** (superseded by D-031 on 2026-10-04). Standard number
order and ring proportions in Relay's palette: sand and slate beds, Ember and Tide rings.

**D-031 Match the classic iMessage games' look first, re-skin later** (Nathan, 2026-10-04:
"do exactly their style then we'll just wrap ours"). Layout, flow, mechanics and generic
colours follow GamePigeon as seen in Nathan's screen recordings; every asset is our own
drawing (procedural wood wall, classic red/green/black/white board, our dart, plaques,
avatars), with no lifted images, sounds, name or logo and no pixel tracing. Darts is a
full-screen table: wood wall, big board at the top, a swaying dart below it, darts left
top left, menu top right, avatars and 3-digit score plaques in the bottom corners, a
"N to win" tag with the finishing segment lit, a points pop where each dart lands, the
other player's visit replayed on opening, and "WAITING FOR OPPONENT..." / "YOU WON!"
banners. Players are red and yellow. Darts now starts at 101 by default (201 and 301
remain presets). The visual layer is kept separate so the later re-skin is a swap.
Four in a Row gets the same treatment: light grey table, players at the top (avatar and
disc each, "You" on the left), a glossy blue board with a lip, moulded red and yellow
discs, help bottom left and a settings menu bottom right, with the same banners.
