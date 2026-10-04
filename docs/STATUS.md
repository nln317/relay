# Status

Last updated 2026-10-04. Repo: private `nln317/relay`, branch `main`.

## Milestones

| Milestone | Status | Why |
|---|---|---|
| M0 Research + platform | **PASS** | Benchmark and docs written; app + Messages extension compile in Xcode 26.6 with zero warnings; package tests pass on Linux and macOS. |
| M1 Four in a Row parity | **PARTIAL** | Full loop implemented and covered by 83 automated tests. Sender side verified in the iOS 26.5 simulator (pick, move, change staged move, cancel, send, reopen own bubble). The receiver side, win/rematch over Messages, and anything on a physical device or between two devices need a second device and account, so they are untested. |

## Evidence (kept separate, brief §36)

### Automated tested
- `swift test` on Linux (Swift 6.1.3, Docker `swift:6.1-noble`): **83 tests passed** (~71 s).
- `swift test` on macOS 26.4.1 (Swift 6.3.3, Xcode 26.6): **83 tests passed** (~46 s).
- Suites: rules, randomized oracle (15,000 games, all 69 windows), bot, identifiers, protocol
  (incl. fuzzing), two-device conversation flow (simulated), ledger storage, analytics privacy.

### Build
- `xcodebuild -project Relay.xcodeproj -scheme Relay -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
  → **BUILD SUCCEEDED, 0 warnings** (after fix 5952a82; the first attempt failed with
  "Multiple commands produce .app" because PRODUCT_NAME was missing).

### Simulator tested (iPhone 17 Pro simulator, iOS 26.5)
- App launches to home: title, "Play in Messages" steps, practice list.
- Practice vs Casual bot: moves, bot replies, game to a win; result card ("You win!", 7 moves,
  Rematch), header record "You 1 – 0 Them", winning discs ringed, others dimmed.
- Messages (dummy conversation; no iMessage account, reaches nobody):
  - Relay is listed in the + menu with its placeholder icon (after a simulator reboot;
    Messages caches the old icon over an existing install).
  - Extension opens compact on the picker; selecting Four in a Row expands to the board.
  - Tapping a column inserts a bubble with the board image, caption "Four in a Row / Your turn".
  - Reopening the staged move shows it translucent; tapping another column replaces the staged
    bubble (one bubble, new board).
  - Deleting the staged bubble, then reopening Relay, shows a clean picker.
  - Sending: bubble in transcript; sheet shows "Waiting for their move".
  - Tapping the sent bubble opens "Their move", board not interactive (fixed in 98dbe18; it
    previously opened in the opponent's seat and allowed a move).
- Build: 0 warnings including asset catalogs.

### Physical device tested
- None.

### Two-device Messages tested
- None.

## Not tested
- Receiver side: opening a turn sent by another person, older-turn notice, diverged history.
- Finishing a game and rematching over Messages; no-move rematch challenge.
- Haptics (simulator has none), VoiceOver, Dynamic Type at large sizes, iOS 17 drag-to-resize.
- Anything on a physical iPhone; any real two-person conversation.
- App Group sharing between app and extension (needs a signing team).
- Mac/Android recipients (fallback URL is a placeholder domain).

## Known issues (prioritised)
1. **Group chats:** any member can answer a turn; conflicting answers are flagged, not prevented.
2. **Same Apple Account on two devices** sees its own moves as local on both; may show
   "Their move" on the wrong device. Detected as diverged history at worst.
3. **Placeholder icons only:** simple original app and iMessage icons (board with two discs), generated locally; final art is M4.
4. **Placeholder identifiers:** bundle id `dev.relay.*`, App Group `group.dev.relay.shared`,
   fallback host `relay.invalid`.
5. **No sound.** Haptics are implemented but unverified.
6. Staged-draft memory can outlive the compose field (if the user clears it while the
   extension is not running, reopening shows "ready to send" until they pick a move or send).
7. `turn_opened` is also recorded for the sender after `didStartSending` (analytics noise; no sink yet).
8. Randomized oracle test takes 50–70 s; fine for CI, slow for quick local runs.

## Human action required
See APP_STORE.md. Short list: Apple Developer team for device builds; real bundle id and App
Group; product name; domain for the fallback URL; app and iMessage icons; two iPhones with two
Apple Accounts for the two-device test.
