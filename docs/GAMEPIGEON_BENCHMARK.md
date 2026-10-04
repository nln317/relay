# GamePigeon benchmark

GamePigeon is our product benchmark, not an engineering dependency. Everything here
comes from publicly observable behaviour: the App Store listing, reviews, press, Apple
Community threads and how-to guides. Nothing was decompiled, extracted or copied, and
none of its artwork, sounds, text or name is used in the product.

Sources and confidence markers are in [research/gamepigeon-public-sources.md](research/gamepigeon-public-sources.md).
Statements marked *(unverified)* there are treated as hypotheses until the owner supplies
screenshots or video (brief §24). Last updated 2026-10-04.

## Snapshot

| Fact | Value | Source quality |
|---|---|---|
| Developer | Vitalii Zlotskii | App Store listing |
| Launched | 13 Sep 2016 with iOS 10 | Wikipedia |
| Rating | 4.0 from about 234K ratings (US) | App Store listing |
| Latest version | 2.2.6, 16 Sep 2024, "Bug fixes" | App Store listing |
| Last new game | Word Bites, 2020 | Version history |
| Games listed | 24 (description says 25) | App Store listing |
| Business model | Free, ads between games, GamePigeon+ $4.99 one-time (no ads, avatar items, modes), cosmetic packs $1.99–$4.99 | App Store listing, Apple Community |

**Read:** a hugely popular format whose content and UX have been frozen for years. The
interaction model is validated; the execution is the opportunity.

## Feature-by-feature

Each entry: GamePigeon behaviour → what works → what feels dated or weak → our parity
behaviour → our eventual improvement → implementation status.

### 1. Getting in (app drawer)

- **GamePigeon behaviour:** on iOS 17+ the user taps "+", then GamePigeon (or "More", then GamePigeon). The extension opens compact with a grid of game tiles.
- **What works:** one destination for every game; no separate app to open.
- **Dated / weak:** the iOS 17 "+" menu buried all third-party iMessage apps two or three taps deep. That is Apple's change, and it hits us equally.
- **Our parity behaviour:** same entry point. The companion app's home screen tells people the exact path ("+ → More → Relay") and that they can drag Relay into the top section.
- **Eventual improvement:** onboarding that teaches the drag-to-top step once; a share-sheet invite from the app for friends who have never played.
- **Status:** PARTIAL. The extension exists and the app explains the path; the drawer itself is NOT TESTED on a device.

### 2. Game picker

- **GamePigeon behaviour:** a grid of game tiles with names and pictures. Some games (8-Ball, Darts, Archery) ask for a mode or difficulty first.
- **What works:** instantly legible: "choose something to play".
- **Dated / weak:** 24 tiles with no recents, favourites or grouping; mode pickers add a step before the first move; tiles look 2016-era.
- **Our parity behaviour:** a single vertical list of large tiles, playable games only. One tap starts the game. No mode screen for Four in a Row.
- **Eventual improvement:** Recents, Favourites, Quick Play / Skill / Board / Word sections once there are 6+ games; Random Game; sensible defaults with optional custom rules tucked behind a long-press.
- **Status:** PARITY for the one-game catalogue.

### 3. Starting a challenge (first move)

- **GamePigeon behaviour:** choosing a game puts an invite in the compose field; the user taps send. The invite usually carries **no move**: the sender sees "Waiting for opponent" and the recipient makes the first move (sourced for Gomoku; inferred generally).
- **What works:** zero thinking for the sender; the invite is cheap to send.
- **Dated / weak:** a full round trip is spent before anything happens. The recipient opens an empty board.
- **Our parity behaviour:** deliberately different (D-007). The challenger drops the first disc, and that move *is* the challenge. Same number of sender taps (pick game, tap column, send), one fewer round trip, and the recipient opens a game that has already started. A rematch started by whoever moved first last time sends a no-move challenge, so the first move alternates.
- **Eventual improvement:** per-game choice; for skill games (Darts, Pool) the challenger's first throw/break is the challenge, the same principle.
- **Status:** IMPROVED (automated tests only; NOT TESTED on device).

### 4. The turn message (bubble)

- **GamePigeon behaviour:** an image-and-caption bubble (template layout inferred). People without the app see only the image or are prompted to install. Exact caption text is unverified.
- **What works:** the board picture in the transcript tells you the state at a glance.
- **Dated / weak:** generic captions; Android recipients see broken links.
- **Our parity behaviour:** `MSMessageTemplateLayout` with a rendered board image, caption "Four in a Row" and a neutral subcaption that reads correctly on both sides ("New game · first move played", "Move 5 · tap to play", "Game over · four in a row!"). One `MSSession` per match so each move replaces the previous bubble and the transcript stays short; `summaryText` leaves a one-line trail. (A first version used `$participant` name tokens; the simulator showed them raw in the compose field, so they were removed, D-016.)
- **Eventual improvement:** themed result cards (brief §19); live layout for the final result only, if it proves light enough; a real fallback web page at the message URL for Mac and Android recipients (needs a domain: HUMAN ACTION).
- **Status:** PARTIAL. Simulator-tested: the bubble with board image appears in the compose field. Sent bubbles and the recipient side are NOT TESTED.

### 5. Receiving a turn

- **GamePigeon behaviour:** tap the bubble; the game opens expanded; you play and send.
- **What works:** direct, one tap to the board.
- **Dated / weak:** reported white screens and endless loading; the opponent's last move appears without context.
- **Our parity behaviour:** tap opens expanded straight onto the board. The opponent's last disc is *replayed* falling into place, so you see what changed. Header shows "You / Them" with whose turn it is.
- **Eventual improvement:** a short "last move" replay for every game; turn timers never, unless a mode opts in.
- **Status:** IMPROVED (logic tested; animation NOT TESTED).

### 6. Making a move and sending

- **GamePigeon behaviour:** for Gomoku you can adjust a marker, then tap Send; moves cannot be undone after sending.
- **What works:** commit is explicit.
- **Dated / weak:** an extra confirmation step in some games; no way to change your mind once the message is staged except deleting it.
- **Our parity behaviour:** tap a column, the disc drops, the extension collapses to show the message in the compose field, the user taps send. Before sending, reopening the staged bubble shows "Your move is in the message box. Tap send, or tap another column to change it"; choosing again replaces the staged message (Messages replaces an inserted message from the same session).
- **Eventual improvement:** per-game undo-before-send for skill games must *not* allow re-rolling a throw (see Known risks in GAME_PROTOCOL.md).
- **Status:** PARITY+ (logic tested; NOT TESTED on device).

### 7. Game over

- **GamePigeon behaviour:** the final bubble shows the winner (unverified detail).
- **What works:** the result lives in the chat.
- **Dated / weak:** nothing beyond win/lose; no record across games.
- **Our parity behaviour:** the winning line pulses, other discs dim, success haptic, a result card ("You win!", move count, rematch record). The bubble subcaption reads "Game over · four in a row!".
- **Eventual improvement:** beautiful themed result cards; Rivalry Sets.
- **Status:** IMPROVED (logic tested; visuals NOT TESTED).

### 8. Rematch

- **GamePigeon behaviour:** not documented publicly (unverified). Users ask for replays and history.
- **Our parity behaviour:** one "Rematch" button on the result card. First mover alternates. A running record ("Record 3–2") travels inside the message chain, so it needs no accounts and cannot be lost by reinstalling. If a rematch already exists, the old result says so instead of starting a duplicate.
- **Eventual improvement:** "Run it back" from the bubble itself; Rivalry Sets (best of 3 across games).
- **Status:** IMPROVED (automated tests only).

### 9. Stale, duplicate and broken messages

- **GamePigeon behaviour:** user reports of "message failed to send", white screens and freezes. Whether old bubbles can be replayed is unverified.
- **Our parity behaviour:** every message carries the full move history and is replayed through the rules on open, so a tampered or corrupted message is rejected with a specific screen instead of crashing. Opening an older bubble shows the latest known position with a notice and cannot be used to answer the same turn twice. Newer-version messages say "Update to play this".
- **Status:** IMPROVED (fuzz and edge-case tests; NOT TESTED on device).

### 10. Practice / single player

- **GamePigeon behaviour:** none. Reviews ask for bots and single-player.
- **Our parity behaviour:** the companion app has Four in a Row practice against three bot levels, plus pass-and-play.
- **Status:** IMPROVED (bot tested; UI NOT TESTED).

### 11. Monetisation

- **GamePigeon behaviour:** ads between games; GamePigeon+ $4.99 removes ads and unlocks avatar items and modes; per-game packs (Pool cues, Cup Pong cups, aircraft) at $1.99–$4.99.
- **What works:** simple, one-time purchases; no loot boxes or currencies.
- **Dated / weak:** ads interrupting social play; packs are unrelated per-game items; some *modes* sit behind the paywall.
- **Our approach:** no ads in Messages turns, ever. Cross-game cosmetic Collections. Opponents render your cosmetics without owning them. Never gate gameplay modes behind payment. See MONETISATION.md.
- **Status:** NOT STARTED (Milestone 6). The loadout field already exists in the protocol.

### 12. Group chats

- **GamePigeon behaviour:** most games are two-player even in groups; Crazy 8 supports 3–6.
- **Our approach:** M1 is designed for one-to-one chats. Seats are positional, not tied to people, so in a group anyone who opens a turn can answer it; two different answers to one turn are detected and flagged as diverged history, but not prevented. Proper group seating and Gauntlets come later; the protocol reserves `rivalryID`.
- **Status:** PARTIAL (known limitation, see STATUS.md; group behaviour NOT TESTED).

## Where GamePigeon is still better (today)

1. **Catalogue:** 24 games vs our 1.
2. **Proven on real devices** at enormous scale; ours has not run on a device yet.
3. **Artwork and sound:** ours uses placeholder shapes and SF Symbols, and has no sound.
4. **Bubble art:** theirs is finished; ours is a rendered board on a gradient.

## Where we are already better (by design; device-unverified)

1. First move travels with the challenge: one fewer round trip.
2. Opponent's last move is replayed on open.
3. Rematch record carried in the message, alternating first mover.
4. Change-your-move before sending, without re-roll exploits in turn-based games.
5. Every received message is validated by replay; corrupt or newer messages get a clear screen.
6. Practice bots and pass-and-play in the companion app.
7. Colour-blind-safe discs (ring vs dot marks) and VoiceOver labels on every column.
8. No ads.

## Open questions for owner-supplied footage (brief §24)

- Exact GamePigeon bubble caption wording and what the sender's own bubble says.
- Rematch flow: where the button is, whether it reuses the bubble.
- Tap count from "+" to first move for Four in a Row.
- What happens when the same bubble is opened twice after answering.
