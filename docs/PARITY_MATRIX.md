# Parity matrix

Status values: NOT STARTED · PARTIAL · PARITY · IMPROVED · NOT APPLICABLE.
"Parity" and "Improved" here mean the behaviour is implemented and covered by automated
tests. None of it has run on a simulator or device yet (see STATUS.md); that evidence
is tracked separately in TESTING.md. Last updated 2026-10-04 (end of Milestone 1, cloud part).

| Feature | GamePigeon reference | Our current implementation | Parity status | Our improvement | Priority |
|---|---|---|---|---|---|
| Entry from "+" drawer | Opens compact game grid | Messages extension opens compact on the picker | PARTIAL (device-unverified) | Companion app teaches "+ → Relay" (scroll if needed) | P0 |
| Game picker | Grid of 24 tiles, some with mode screens | One-tap list of playable games only | PARITY | Recents/Favourites/sections once catalogue ≥ 6 | P1 |
| Start challenge | Invite with no move; recipient starts | Challenger's first move is the challenge (D-007); alternate on rematch | IMPROVED | Saves one round trip | P0 |
| Turn message | Image + caption bubble | Template layout, rendered board, neutral caption, one MSSession per match | PARTIAL | Themed result cards later | P0 |
| Received-turn UX | Tap opens game | Tap opens expanded board; opponent's last disc replays falling | IMPROVED | Last-move replay for all games | P0 |
| Make and send move | Adjust then send; no undo after send | Tap column → drop → auto-insert → user taps send; reopen staged bubble to change move | PARITY+ | Change-move without re-roll exploits | P0 |
| Waiting state | "Waiting for opponent" | "Their move" status on own bubble | PARITY | — | P0 |
| Game-over UX | Winner shown | Pulsing winning line, dimmed others, success haptic, result card | IMPROVED | Themed cards, share | P0 |
| Rematch | Unverified | One button; alternates first mover; record carried in message; each person keeps their colour (D-024); duplicate-rematch guard | IMPROVED | Rivalry Sets | P0 |
| Stale / duplicate messages | Unverified | Shows latest known turn; blocks double answers; idempotent | IMPROVED | — | P0 |
| Malformed / newer-version messages | White screens reported | Specific "damaged" / "update to play" screens, never a crash (fuzzed) | IMPROVED | — | P0 |
| Draft recovery after termination | Unverified | Ledger keeps staged move; transcript reconciles sends | IMPROVED | — | P0 |
| Practice / single player | None (users ask for it) | App: 3 bot levels + pass and play | IMPROVED | Practice for every game | P1 |
| Four in a Row | 6×7 Connect-4 | Full rules, 81-test suite incl. 15k-game oracle | PARITY (GamePigeon-style table, D-031) | Colour-blind-safe discs, VoiceOver columns | P0 |
| Darts | 101/201/301 countdown, flick | 101 countdown (201/301 supported), straight finish, 10-round cap; GamePigeon-style table (D-031); swipe the dart up to throw (speed sets height, line sets direction); throws committed as made | PARTIAL (automated tests; device-unverified) | One-line rules, no re-throws, VoiceOver throw actions, live score preview | P1 (M2) |
| 8-Ball | Two modes, cue drag + power | — | NOT STARTED | Flagship physics and cosmetics | P1 (M3) |
| Cup Pong | 9–10 cups, flick | — | NOT STARTED | — | P2 |
| Basketball | 3 timed rounds, swipe | — | NOT STARTED | — | P2 |
| Mini Golf | Course per game, swipe | — | NOT STARTED | Course packs | P2 |
| Archery | Wind, distance grows | — | NOT STARTED | — | P3 |
| Other 17 games | See GAME_ROADMAP.md | — | NOT STARTED | — | P3+ |
| Cosmetics | Per-game packs | Loadout field in protocol only | NOT STARTED | Cross-game Collections, social rendering | P1 (M6) |
| Purchases | GamePigeon+ $4.99 + packs | — | NOT STARTED | StoreKit 2 non-consumables, no gameplay paywall | P1 (M6) |
| Ads | Between games | None | NOT APPLICABLE | Never inside a Messages turn | — |
| Avatars / profile | Avatar items (paid) | — | NOT STARTED | Profile identity in app | P3 |
| Game settings / modes | Mode picker before some games | Standard rules only; protocol accepts variants | PARTIAL | Optional custom rules, never a mandatory screen | P2 |
| Group chats | Mostly 2-player; Crazy 8 3–6 | 1:1 design; diverged answers flagged | PARTIAL | Gauntlets (later) | P3 |
| Accessibility | Unknown | Shape-marked discs, column labels, Dynamic Type text | IMPROVED (unverified on device) | Full VoiceOver pass in M4 | P1 |
| Sound | Present | None yet | NOT STARTED | Premium sound design (M4) | P2 |
| Original visual identity | GamePigeon's own | Placeholder dark theme, Ember/Tide discs | PARTIAL | Full re-theme in M4 | P2 |
