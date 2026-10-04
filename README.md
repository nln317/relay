# Relay (working name)

Quick turn-based games with friends inside iMessage. GamePigeon proved the format; Relay
rebuilds it with better feel, a stronger social layer and a fair cosmetic business.
GamePigeon is a product benchmark only: no code, assets, names or text are taken from it.

Current milestone: **M1, Four in a Row**. See [docs/STATUS.md](docs/STATUS.md).

## Layout

| Path | What |
|---|---|
| `Package.swift`, `Sources/` | RelayKit: rules, protocol, Messages lifecycle logic, SwiftUI views |
| `Tests/` | Swift Testing suites (rules, oracle, protocol fuzzing, two-device flows) |
| `App/` | iPhone app: home + practice vs bots / pass and play |
| `MessagesExtension/` | iMessage extension: picker, board, send, result, rematch |
| `project.yml` | XcodeGen spec; `Relay.xcodeproj` is generated from it and committed |
| `docs/` | Product, benchmark, parity, roadmap, architecture, protocol, testing, status |

## Build and test

```sh
swift test                         # RelayKit tests (macOS or Linux)
open Relay.xcodeproj               # Xcode 15+ (iOS 17 SDK) — scheme "Relay"
xcodegen generate                  # only if you change project.yml
```

To run on a device: create `Config/Local.xcconfig` (git-ignored) with your
`DEVELOPMENT_TEAM`, `RELAY_BUNDLE_ID_PREFIX` and `RELAY_APP_GROUP`; both targets, the
entitlements and the extension's ledger location pick them up (example in
`Config/Relay.xcconfig`, details in docs/APP_STORE.md). To play in Messages, run the **Relay** scheme, then in Messages tap
**+ → Relay** (scroll down the list if needed).

## Docs
[PRODUCT](docs/PRODUCT.md) · [GAMEPIGEON_BENCHMARK](docs/GAMEPIGEON_BENCHMARK.md) ·
[PARITY_MATRIX](docs/PARITY_MATRIX.md) · [GAME_ROADMAP](docs/GAME_ROADMAP.md) ·
[ARCHITECTURE](docs/ARCHITECTURE.md) · [GAME_PROTOCOL](docs/GAME_PROTOCOL.md) ·
[TESTING](docs/TESTING.md) · [MONETISATION](docs/MONETISATION.md) ·
[ANALYTICS](docs/ANALYTICS.md) · [PRIVACY](docs/PRIVACY.md) · [APP_STORE](docs/APP_STORE.md) ·
[DECISIONS](docs/DECISIONS.md) · [STATUS](docs/STATUS.md) · [ROADMAP](docs/ROADMAP.md)
