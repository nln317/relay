# Architecture

Relay (working codename) is an iPhone app with a Messages extension. Messages is the
social play surface; the app is practice, identity, cosmetics and stats.

## Shape

```
Relay.xcodeproj  (generated from project.yml by XcodeGen; committed)
├─ Relay (iOS app target)                 App/
│    Home, Practice (bots, pass-and-play)
├─ RelayMessagesExtension (Messages ext.) MessagesExtension/
│    MessagesViewController  ← thin adapter over Messages framework
│    ExtensionModel          ← UI state, intents
│    ExtensionRootView       ← picker / play / problem screens
└─ RelayKit (local Swift package)          Package.swift, Sources/
     RelayCore       IDs, Seat, GameOutcome, SeriesTally, GameRules, Match, CosmeticLoadout
     RelayGames      FourInARow rules, FourInARowBot, GameCatalog
     RelayMessages   Wire protocol (MatchCodec), AnyMatchSnapshot, MatchLedger,
                     ConversationController (lifecycle → screens, drafts, recovery)
     RelayAnalytics  Event enum, sink protocol (no network sink yet)
     RelayUI         SwiftUI board, picker, play screen, result card, theme
```

RelayCommerce (StoreKit) is deliberately absent until Milestone 6. The only commerce-shaped
type today is `CosmeticLoadout` in RelayCore, because it travels in messages.

## Dependency rules

- RelayCore depends on nothing but Foundation.
- RelayGames depends on RelayCore. Games never import UI, Messages or StoreKit.
- RelayMessages depends on RelayCore, RelayGames, RelayAnalytics. **It does not import the
  Messages framework.** All lifecycle logic is expressed with `OpenedMessage` (url, sender
  is local, is pending), so it runs and is tested on Linux.
- RelayUI is the only module with SwiftUI. Every file is wrapped in `#if canImport(UIKit)`.
- The app and extension targets are thin: they translate platform callbacks and host views.

Result: everything that decides game outcomes, whose turn it is, and what is safe to send is
in modules that build and test anywhere Swift runs.

## The core loop

```
User taps bubble ─► MessagesViewController.willBecomeActive / didSelect
                    └─► OpenedMessage(url, senderIsLocal, isPending)
                         └─► ConversationController.screen(for:)
                              ├─ GameDecoders.decode(url)  (validate + replay every move)
                              ├─ reconcile with MatchLedger (older turn? diverged? pending draft?)
                              └─► ConversationScreen: picker | play(PlaySession) | problem(error)
User taps column  ─► ExtensionModel.play(column:)
                    └─► ConversationController.prepareMove → OutgoingMessage (url + caption)
                         └─► MessagesViewController.insert: MSMessage(session:), template layout,
                              conversation.insert → controller.didInsert (ledger: pending)
User taps send    ─► didStartSending → controller.didStartSending (ledger: official, "sent from this device")
User deletes it   ─► didCancelSending → controller.didCancelSending (ledger: drop pending)
```

## Game abstraction

`GameRules` (RelayCore) is intentionally small: configuration, state, action, violation,
`initialState`, `apply`, `outcome`, `maximumActions`, `isSupported`. `Match<Rules>` holds a
header, configuration and **action history**; state is always derived by replaying actions.
This gives validation of received messages for free, deterministic results on both devices,
and a natural "replay the last move" animation.

The brief lists more concepts (GameRenderer, PlayerState, TurnState, CosmeticDefinition…).
They are not created yet on purpose (brief §26): they will be extracted when Darts shows
what is actually shared. Known pressure points:

- Strict alternation (`Match.lastActor`) will not hold for 8-Ball or Cup Pong. Plan: let the
  rules report the actor of each action (D-005).
- `AnyMatchSnapshot` is an enum with one case per game. Adding a game means adding a case
  and the compiler lists every switch to update. Revisit if the catalogue passes ~10 games.

## Physics games (M2/M3 plan, not built)

Replaying a shot on the receiving device requires bit-identical simulation across devices
and OS versions. Two options, to be decided with evidence in M2/M3:
1. Deterministic fixed-step simulation in integer / fixed-point maths inside RelayGames
   (no SpriteKit physics in the rules); SpriteKit only renders.
2. The sender's device simulates and the message carries the result; the receiver trusts it.
   Simpler, but a modified client can forge results (GamePigeon appears to work this way,
   given public "win spoofing" cheats).
Leaning to (1) for 8-Ball because outcomes are the product.

## Persistence

- Source of truth for a match: the transcript messages themselves.
- `MatchLedger` (JSON in the App Group container, schema-versioned, ≤ 200 entries) only adds
  recovery hints: latest official turn, staged draft, local seat, rematch links. Losing it
  never loses a game (tested).
- Writes are synchronous and atomic, because Messages may terminate the extension right after
  resign callbacks.

## Resource constraints

The extension loads no assets beyond SwiftUI shapes and SF Symbols; the bubble image is
rendered on demand at 300×225 pt ×3. No singletons; the controller is owned by the model,
the model by the view controller.

## Concurrency and language mode

RelayKit compiles in Swift 6 language mode. The app and extension targets use Swift 5 mode
with complete concurrency checking as warnings (D-011), because they could not be compiled
in the cloud environment where they were written; tighten to Swift 6 once a Mac build is green.
