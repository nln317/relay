# Game protocol (v1)

Each interactive message is a versioned, self-contained snapshot of one match. Code:
`Sources/RelayMessages/WireProtocol.swift`. Frozen by the test `handwrittenV1PayloadDecodes`.

## Transport

`MSMessage.url`:

```
https://relay.invalid/play?v=1&g=four-in-a-row&p=<base64url(JSON envelope)>
```

- `https` because Messages only accepts http, https or data URLs, and a Mac recipient's
  browser opens the URL. `relay.invalid` is a reserved placeholder; it must become an owned
  domain with a fallback page before beta (APP_STORE.md, human action).
- `v` and `g` are duplicated outside the payload so a client can say "update to play this"
  without decoding anything it doesn't understand.
- Apple's documented limit is 5,000 characters. We refuse to *write* payloads over 4,000
  characters and refuse to *read* URLs over 16,000 before parsing. A complete 42-move game
  with two maximal cosmetic loadouts is tested to stay under 5,000.

## Envelope (JSON, short keys)

| Key | Field | Notes |
|---|---|---|
| `pv` | protocolVersion | Must equal `v` |
| `g` | gameID | Slug, validated `[a-z0-9-]{1,32}`; must equal `g` |
| `rv` | rulesVersion | Per game. Newer than ours → "update to play" |
| `m` | matchID | UUID |
| `f` | firstSeat | 1 or 2. Seat 1 is always the challenger |
| `n` | turnNumber | Must equal number of actions |
| `c` | configuration | Game-specific; Four in a Row `{w,h,k}` |
| `a` | actions | Full history; Four in a Row: column integers |
| `pm` | previousMatchID | Optional; rematch link; must differ from `m` |
| `s` | series | Optional `{w1,w2,d}` rematch record in this match's seat numbering |
| `r` | rivalryID | Reserved for Rivalry Sets; unused in v1 |
| `lo` | loadouts | Optional `{"1": {"items": {slot: cosmeticID}}}`; presentation only |

The game **state is never sent**. Receivers rebuild it by replaying `a` through the rules.

## Validation (in order)

1. URL length ≤ 16,000; host and path are ours; exactly one each of `v`, `g`, `p`.
2. `v` within [minimum, current] → else `unsupportedProtocolVersion` (update) or `obsoleteProtocolVersion`.
3. `g` is a valid slug and a known game → else `unknownGame` (update).
4. `p` is strict base64url → JSON header decodes; `pv`/`g` match the outer fields.
5. `rv` equals ours → newer is `unsupportedRulesVersion` (update).
6. Full envelope decodes with strong types (UUIDs, seats, slugs).
7. `n == a.count`; series valid; `pm ≠ m`.
8. Configuration supported; `a.count ≤ maximumActions`; every action replays legally with
   strict turn order and nothing after the game ends → else `illegalHistory`.
9. Bad cosmetic entries are dropped, never fatal.

No force-unwraps on received data. Fuzz tests feed 2,000 random payloads and 3,000 mutated
valid payloads; every one either decodes to a legal game or throws `ProtocolError`.

## Who am I? (seat resolution)

Messages participant identifiers are scoped to each device and change on reinstall, so
they cannot identify a player across devices. Instead:

- The device that produced a snapshot is the seat of its last action (or seat 1 at turn 0).
- `MSMessage.senderParticipantIdentifier == conversation.localParticipantIdentifier` tells
  us whether *this* device sent it.
- So: `localSeat = senderIsLocal ? producedBy : producedBy.opponent`.

This holds for one-to-one chats. Known limits: in a group chat any member can answer a turn;
the same Apple Account on two devices sees its own messages as local on both. Both cases
end as "diverged history", detected and shown, not prevented.

## Draft recovery (brief §29)

The ledger keeps four states apart:

| State | Where | Authoritative? |
|---|---|---|
| Last received official state | `official` with source `received` | Yes |
| Current local draft | not persisted: Four in a Row commits and inserts in one step | n/a |
| Completed unsent action | `pendingOutgoing` (inserted into compose field) | **Never** |
| Last locally known outgoing state | `official` with source `sentFromThisDevice` (from `didStartSending`) | Yes, but "send started", not "delivered" |

Rules:
- Opening any non-pending bubble reconciles: higher turn wins; same turn with a different
  history keeps the first seen and shows a notice; an opened older bubble shows the latest
  known position and cannot be answered again.
- A pending draft older than or equal to the official turn is discarded.
- If the extension dies after insert, the draft is remembered; if the user then sends it,
  opening the sent bubble reconciles the ledger.
- Re-inserting in the same `MSSession` replaces the staged message (Apple-documented), which
  is how "change your move" works.

## Terminology

"Inserted" = placed in the compose field. "Send started" = `didStartSending`. We never
claim "delivered" or "read"; Messages does not expose either to extensions.

## Versioning policy

- Additive optional fields: keep `v`, old clients ignore unknown keys.
- Any change that makes an old client misread a message: bump `v`.
- Any rules change that could change an outcome for the same history: bump that game's `rv`.
- Keep decoders for every `v` and `rv` still plausibly sitting in people's transcripts.

## Known risks (next games)

- **Re-roll in skill games:** if a Darts throw is computed when the player releases, they
  could cancel the staged message and throw again. Plan for M2: the throw result is committed
  to the ledger at release, and reopening shows the committed throw, not a fresh attempt.
  (A determined user with a modified client can still cheat; see ARCHITECTURE.md.)
- **Hidden information** needs commit-reveal; not supported by v1.
