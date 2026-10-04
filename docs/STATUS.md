# Status

Last updated 2026-10-04. Repo: private `nln317/relay`, branch `main`.

## Milestones

| Milestone | Status | Why |
|---|---|---|
| M0 Research + platform | **PASS** | Benchmark and docs written; app + Messages extension compile in Xcode 26.6 with zero warnings; package tests pass on Linux and macOS. |
| M1 Four in a Row parity | **PARTIAL** | Full loop implemented and covered by automated tests; app, practice and the extension's pick → move → insert → send path verified in the iOS 26.5 simulator. Not yet verified: opening a received turn in Messages, draft replacement on device, and any physical-device or two-device play. |

## Evidence (kept separate, brief §36)

### Automated tested
- `swift test` on Linux (Swift 6.1.3, Docker `swift:6.1-noble`): **81 tests passed** (~73 s).
- `swift test` on macOS 26.4.1 (Swift 6.3.3, Xcode 26.6): **81 tests passed** (~50 s).
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
- Messages: Relay is listed in the + menu; extension opens compact on the picker; selecting
  Four in a Row expands to the board ("You go first"); tapping a column inserts a bubble with
  the board image and caption "Four in a Row / New game · first move played" (since changed to "Your turn", D-018); compact sheet
  shows "Your move is ready. Tap send."
- Sent in the simulator's dummy conversation (no iMessage account, reaches nobody): bubble
  in transcript with same image and caption; sheet switches to "Waiting for their move".

### Physical device tested
- None.

### Two-device Messages tested
- None.

## Not tested
- Tapping a sent or received bubble to open the extension (receiver flow, older-turn notice).
- Changing a staged move by reopening the draft (Messages' replace-in-compose-field behaviour).
- `didCancelSending` when deleting a staged message.
- Rematch from inside Messages; no-move challenge.
- Haptics (simulator has none), VoiceOver, Dynamic Type at large sizes, iOS 17 drag-to-resize.
- Anything on a physical iPhone; any real two-person conversation.
- App Group sharing between app and extension (needs a signing team).
- Mac/Android recipients (fallback URL is a placeholder domain).

## Known issues (prioritised)
1. **Group chats:** any member can answer a turn; conflicting answers are flagged, not prevented.
2. **Same Apple Account on two devices** sees its own moves as local on both; may show
   "Their move" on the wrong device. Detected as diverged history at worst.
3. **No iMessage app icon** (blank placeholder in the + menu) and no app icon. Needs original art.
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
