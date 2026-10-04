# Analytics

Code: `Sources/RelayAnalytics/Analytics.swift`. Status: events are defined and emitted by
`ConversationController`; **no network sink exists** (D-015). The extension uses `NoOpAnalytics`.

## Events (current)
`extension_open`, `game_picker_open`, `game_selected`, `challenge_prepared`, `turn_opened`,
`turn_prepared` (inserted, not sent), `turn_send_started` (Messages started sending; not
delivered), `turn_send_cancelled`, `match_completed` (local win/loss/draw, turns),
`rematch_started`, `message_rejected` (reason code). `practice_started` is defined but the
app does not emit it yet. Known noise: the extension re-resolves the screen after
`didStartSending`, which also records a `turn_opened` for the sender's own move.

Planned later: `rivalry_started`, `rivalry_completed`, `collection_view`, `purchase_started`,
`purchase_verified`, `cosmetic_equipped`.

## Rules
- Properties are a closed set: game, turn, result, turns, presentation, reason, opponent.
  A test asserts no participant tokens or UUIDs appear.
- Never collect conversation text, contact data or participant identifiers.
- Never emit "delivered" or "read"; Messages does not expose them.

## Business metrics (later)
Activation, returned-turn rate (`turn_opened` on the receiving side ÷ `turn_send_started`,
approximate because devices differ), match completion, matches per player, rematch rate,
Rivalry Set rate, D1/D7/D30, store view rate, preview rate, payer conversion, ARPPU,
revenue/MAU, refund rate. Retention before monetisation.
