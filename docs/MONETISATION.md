# Monetisation

Status: design only. Implementation is Milestone 6. Nothing in M0/M1 charges money.

## Benchmark
GamePigeon: ads between games; GamePigeon+ $4.99 one-time (no ads, avatar items, modes);
per-game packs $1.99–$4.99 (Pool cues, Cup Pong cups, aircraft). No currencies or loot boxes.

## Our model
- **Cosmetics are the business.** Non-consumable StoreKit 2 purchases first. No currencies
  until behaviour shows a need.
- **Collections, not random packs.** One aesthetic across games (e.g. a "Neon Nights"
  collection: Pool cue/table/balls, Darts barrels/flights, Four in a Row discs/board,
  universal result card and victory animation).
- **Hypothesis price points:** mini pack ≈ A$2.99, full collection ≈ A$6.99, premium ≈
  A$9.99. Always display StoreKit's localised `displayPrice`; never hardcode a price.
- **Purchase = permission to equip, not permission to render.** Loadouts travel in the
  message (`lo` field, already in protocol v1). Opponents see your cosmetics without owning
  them. Unknown cosmetic ids render as defaults.
- **No pay-to-win.** Cosmetics cannot change aim, power, hitboxes, collisions, scoring, turn
  length, moves, friction, pocket size or visibility. Enforced structurally: `GameRules`
  takes no cosmetic input, and rules tests run without any cosmetics.
- **No gameplay modes behind payment** (a GamePigeon complaint).
- **Ads:** none in Messages turns. Possibly optional rewarded ads in the app later, only if
  policy and economics justify it.
- Games must not depend on StoreKit. RelayCommerce will sit beside the games, not under them.

## Social loop (no dark patterns)
Player A equips a collection → B sees it in their match → B can tap to preview in the app →
B may buy. No nags, no countdown offers, no prompts mid-turn.
