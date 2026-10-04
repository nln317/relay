# Status

Last updated 2026-10-04. Repo: private `nln317/relay`, branch `main`.

## Milestones

| Milestone | Status | Why |
|---|---|---|
| M0 Research + platform | **PASS** | Benchmark and docs written; app + Messages extension compile in Xcode 26.6 with zero warnings; package tests pass on Linux and macOS. |
| M1 Four in a Row parity | **PARTIAL** | Full loop implemented and covered by automated tests. On the owner's iPhone: app runs, drop animation and practice verified by the owner. Sender side verified in Messages in the iOS 26.5 simulator. Receiver side, win, rematch chain, older-turn notice and problem screens verified in the simulator through the two-phone rehearsal (same logic and views, no Messages framework). Physical-device and two-device Messages play need a signing team and a second iPhone and account, so they are untested. |
| M2 Darts | **PASS (owner-accepted feel), PARTIAL evidence** | Owner go-ahead 2026-10-04. Rules, integer scoring, bot, committed throws and Messages flow covered by automated tests (108 total). GamePigeon-style table (D-031) tuned on the owner's iPhone over many rounds; on 2026-10-04 23:34 the owner called the throw feel "decent enough" and closed the game. Not yet: two-device play, cosmetics hooks, sound. |

## Evidence (kept separate, brief §36)

### Automated tested
- `swift test` on Linux (Swift 6.1.3, Docker `swift:6.1-noble`): **106 tests passed** (~75 s).
- `swift test` on macOS 26.4.1 (Swift 6.3.3, Xcode 26.6): **106 tests passed** (Mac, round 11).
- Suites: rules, randomized oracle (15,000 games, all 69 windows), bot, identifiers, protocol
  (incl. fuzzing), two-device conversation flow (simulated), ledger storage, analytics privacy.

### Build
- `xcodebuild -project Relay.xcodeproj -scheme Relay -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
  → **BUILD SUCCEEDED, 0 warnings** (after fix 5952a82; the first attempt failed with
  "Multiple commands produce .app" because PRODUCT_NAME was missing).

### Simulator tested (iPhone 17 Pro simulator, iOS 26.5; latest round at 56f0277)
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
- Build: 0 warnings including asset catalogs. Built bundle ids `dev.relay.Relay` and
  `dev.relay.Relay.MessagesExtension`, extension `RelayAppGroup = group.dev.relay.shared`
  (from Config/Relay.xcconfig).
- Practice: rematch alternates the first mover and keeps the score; pass-and-play to a result
  ("Ember wins", header "Ember 1 – 0 Tide").
- Largest accessibility text size (AX3): board, header and home screen usable (home practice
  rows fixed in 89d57d2). iPhone SE (3rd gen): home, compact picker and board fit.

### Rehearsal tested (simulator, Debug "Two-phone rehearsal", D-021; not Messages evidence)
- Ava starts and moves; Ben's phone opens the bubble as "Your move" with correct seats and
  colours; turns alternate to a win.
- Winner's card "You win!", loser's "They win", win line ringed; record shows as soon as game 1
  ends (fixed in 56f0277).
- Loser's rematch: they move first, record carries over (left number = left pill), each person
  keeps their colour (D-024). A third game started by the other player alternates again.
- Opening an older bubble shows the latest position with "That was move 5…" and, when a rematch
  exists, "Rematch already started"; no playable stale board.
- Damaged message: "This game can't be opened" with a New game button that opens the picker.
  Newer version: "Update to play this", no button.
- Practice bots: Standard blocks an open three and takes its own win; Sharp blocks a row three
  at once and replies within about 3 s in the simulator.
- Free-account build (`RELAY_USE_APP_GROUP = NO`, D-025): builds, no App Group entitlement,
  stages a move in Messages with the fallback ledger.
- VoiceOver labels (read by a scratch XCUITest, 27f473f): columns read discs bottom to top from
  each player's side ("Column 3: you, you, you, you. 2 spaces free. Part of the winning line."),
  Ember/Tide in pass-and-play, header "Record: you 1, them 0". The "They played column N."
  announcement needs a device with VoiceOver.
- Five cold launches into Practice showed no stray first move (an earlier one-off sighting is
  treated as simulator tap timing).

### Darts (2026-10-04, rounds 18–28 on the owner's Mac)
- Builds at every round: device and simulator, 0 warnings. Installed on the owner's iPhone at
  each step; the owner tuned the throw by hand (no idle sway, heavier dart, aim from the
  whole swipe, log power curve, small pinned darts) and accepted the feel.
- Simulator: GamePigeon-style table on iPhone 17 Pro and SE (corners, plaques, checkout tag,
  points pop on screen, one-line banners, board clears for the next thrower); straight swipes
  land within a bull's width of centre; Four in a Row table matches the owner's screenshot.
- Simulator speed sweep (synthetic touches, 127fec8): soft swipes throw and fall low; the
  board spans roughly 150–1,800 pt/s of synthetic speed, which reads steeper than the owner
  reports on device. Retune only on owner feedback.
- Rehearsal (b8a5d3e): scores update after each dart; switching phones flies the other
  player's three darts in with pops and a counting score, then clears the board.
- Messages (dummy chat): bubbles show the "YOUR TURN" strip; the compact drawer shows the
  picture, "TAP SEND TO FINISH YOUR TURN" and an OPEN button. Installed on the owner's iPhone.

### Physical device tested
- iPhone 17 Pro Max, iOS 26.6.1, free Personal Team (`RELAY_USE_APP_GROUP = NO`): signed device
  build succeeded and installed. Launch waits on trusting the developer profile on the phone.

### Two-device Messages tested
- None.

## Not tested
- Receiver side inside real Messages (covered only by the rehearsal and automated tests).
- Finishing a game and rematching over real Messages; diverged history on a device.
- Haptics (simulator has none), a full VoiceOver pass on a device (move announcements), iOS 17 drag-to-resize, Sharp bot depth beyond one-move blocks.
- Anything on a physical iPhone; any real two-person conversation.
- App Group sharing between app and extension (needs a signing team).
- Mac/Android recipients (fallback URL is a placeholder domain).

## Known issues (prioritised)
1. **Group chats:** any member can answer a turn; conflicting answers are flagged, not prevented.
2. **Same Apple Account on two devices** sees its own moves as local on both; may show
   "Their move" on the wrong device. Detected as diverged history at worst.
3. **Placeholder icons only:** simple original app and iMessage icons (board with two discs), generated locally; final art is M4.
4. **Placeholder identifiers:** bundle id `dev.relay.*` and App Group `group.dev.relay.shared`
   (override in git-ignored `Config/Local.xcconfig`, D-022); fallback host `relay.invalid`.
5. **No sound.** Haptics are implemented but unverified.
6. Staged-draft memory can outlive the compose field (if the user clears it while the
   extension is not running, reopening shows "ready to send" until they pick a move or send).
7. **Reopening Relay with an unsent move** (via +, after swiping the sheet away) shows the game
   picker, not the staged move; Messages does not tell the extension about drafts. Starting a
   second game then stages a second bubble. Same in both App Group modes.
8. `turn_opened` is also recorded for the sender after `didStartSending` (analytics noise; no sink yet).
9. Randomized oracle test takes 50–70 s; fine for CI, slow for quick local runs.
10. **Darts bubble picture:** the darts in the last visit are barely visible at bubble size.

## Human action required
See APP_STORE.md. Short list: Apple Developer team, bundle id prefix and App Group, all in one
file (`Config/Local.xcconfig`); product name; domain for the fallback URL; app and iMessage icons; two iPhones with two
Apple Accounts for the two-device test.
