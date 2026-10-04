# Testing

Four evidence categories are kept separate (brief §36). "Tested" without a category means nothing.

| Category | Meaning | Current state |
|---|---|---|
| AUTOMATED TESTED | `swift test` on RelayKit (unit + integration) | 83 tests passing on Linux (Swift 6.1.3) and macOS (Swift 6.3.3) |
| SIMULATOR TESTED | Built and exercised in the iOS Simulator | Sender side done on iOS 26.5: app, practice, pick → move → change → cancel → send → reopen. See STATUS.md |
| PHYSICAL DEVICE TESTED | Run on an iPhone | Not yet |
| TWO-DEVICE MESSAGES TESTED | Two iPhones, two Apple Accounts, real conversation | Not yet |

## Running the automated tests

```sh
swift test                      # macOS or Linux, from the repo root
```

On Linux without Swift installed, the Docker image works:
```sh
docker run --rm -v "$PWD":/src -w /src swift:6.1-noble swift test
```

Tests use Swift Testing (`import Testing`).

## What the automated suite covers

- **Rules (RelayGamesTests):** every win direction, both seats, 5-in-a-row, two lines in one
  move, draw on a full board, win on the 42nd disc, full/out-of-range columns, wrong seat,
  moves after the end, history replay errors with indices, overlong histories, unsupported
  configurations and variants, determinism, compact action encoding.
- **Oracle (RelayGamesTests):** 15,000 seeded random games; after every move the incremental
  win detection is compared with a naive whole-board scan, and all 69 possible winning
  windows are confirmed detected for both seats.
- **Bot:** wins when it can, blocks when it must, avoids handing over wins, always legal,
  stronger level beats casual.
- **Protocol (RelayMessagesTests):** round trip, frozen v1 payload, size budget, newer/older
  protocol, unknown game, newer rules, foreign URLs, missing/duplicated fields, malformed
  JSON variants, bad base64, truncation, header mismatches, illegal histories, oversize,
  bad cosmetics dropped, 2,000 random and 3,000 mutated payloads never crash.
- **Two-device flow (integration, simulated):** two `ConversationController`s with separate
  ledgers and a shared transcript play a full game, result, rematch (first mover alternates,
  record carried), no-move challenge, out-of-turn and post-game moves, older bubble, double-
  answer prevention, duplicate delivery, out-of-order arrival, diverged history, staged draft
  reopen and change, cancel send, extension termination with a staged draft, send without a
  callback, ledger loss, `didReceive`, malformed messages, persistence failure surfaced.
- **Privacy:** analytics events carry no participant tokens or UUIDs.

These simulate Messages with our own model of its behaviour, so they prove our logic, not
Apple's. The on-device checklist below is still required.

## Messages edge-case checklist (brief §28) — manual, two devices

| Case | Automated (simulated) | Two-device |
|---|---|---|
| Starting a game | ✓ | NOT TESTED |
| Cancelling send | ✓ | NOT TESTED |
| Opening own draft | ✓ | NOT TESTED |
| Opponent opening challenge | ✓ | NOT TESTED |
| Opponent sending turn | ✓ | NOT TESTED |
| Opening an older message | ✓ | NOT TESTED |
| Duplicate message | ✓ | NOT TESTED |
| Stale message | ✓ | NOT TESTED |
| Extension termination | ✓ | NOT TESTED |
| App termination | n/a (no app state in matches) | NOT TESTED |
| Device restart | ✓ (ledger on disk) | NOT TESTED |
| App update during active match | ✓ (versioned protocol + ledger schema) | NOT TESTED |
| Unsupported protocol version | ✓ | NOT TESTED |
| Malformed state | ✓ | NOT TESTED |
| Game already finished | ✓ | NOT TESTED |
| Rematch | ✓ | NOT TESTED |

Also verify on device: bubble image rendering in sent and received bubbles, compact →
expanded transitions, haptics, VoiceOver column labels, iOS 17 drag-to-resize.
