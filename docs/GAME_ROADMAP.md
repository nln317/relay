# Game roadmap

The GamePigeon catalogue is market validation for the kinds of games that work inside
Messages. We will not reproduce all 24. Each candidate is scored 1–5 on the brief's seven
criteria (higher is better; for complexity and session length, higher means *cheaper* or
*shorter*). Scores are product judgement from public descriptions, not data; re-rank from
player behaviour after beta.

Criteria: **Rep** replayability · **Fam** popularity/familiarity · **Cost** development cost
(5 = cheapest) · **Cos** cosmetic potential · **Soc** social competitiveness · **Len**
session shortness · **Orig** room for original differentiation.

## Ranked catalogue

| Rank | Game | Rep | Fam | Cost | Cos | Soc | Len | Orig | Total | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Four in a Row | 4 | 5 | 5 | 3 | 4 | 5 | 2 | 28 | Platform proof. **Done (M1).** |
| 2 | Darts | 4 | 4 | 3 | 5 | 4 | 4 | 4 | 28 | First skill game; proves "action is a throw" and anti-re-roll. **M2.** |
| 3 | 8-Ball | 5 | 5 | 1 | 5 | 5 | 2 | 4 | 27 | Flagship; physics + determinism work. **M3.** |
| 4 | Cup Pong | 4 | 5 | 3 | 5 | 5 | 4 | 3 | 29 | Highest social pull; reuses projectile code from Darts. |
| 5 | Basketball | 4 | 4 | 3 | 4 | 4 | 5 | 3 | 27 | Async score-attack; simple to verify. |
| 6 | Mini Golf | 5 | 4 | 2 | 5 | 4 | 3 | 5 | 28 | Course packs and seasonal content: strongest long-term differentiation. |
| 7 | Archery | 3 | 3 | 3 | 4 | 4 | 4 | 3 | 24 | Reuses projectile + wind. |
| 8 | 9-Ball | 4 | 3 | 4* | 4 | 4 | 3 | 2 | 24 | *Cheap once 8-Ball exists. |
| 9 | Word Hunt (original equivalent) | 5 | 4 | 3 | 2 | 5 | 5 | 4 | 28 | Needs our own word list and licence check; daily-challenge fit. |
| 10 | Checkers | 3 | 4 | 4 | 3 | 3 | 3 | 2 | 22 | Board framework reuse. |
| 11 | Chess | 4 | 5 | 2 | 3 | 4 | 1 | 2 | 21 | Rules are expensive (castling, en passant, promotion, draws); long sessions. |
| 12 | Dots and Boxes | 3 | 3 | 4 | 2 | 3 | 4 | 3 | 22 | Cheap, multi-move turns test the action model. |
| 13 | Sea Battle-style | 3 | 4 | 3 | 3 | 4 | 3 | 3 | 23 | Needs hidden information: our "full history in the message" model leaks ship positions. Requires a commit-reveal design first. |
| 14 | Gomoku | 3 | 2 | 5 | 2 | 3 | 4 | 2 | 21 | Nearly free on the Four in a Row board code. |
| 15 | Reversi | 3 | 3 | 4 | 2 | 3 | 4 | 2 | 21 | |
| 16 | Mancala | 3 | 3 | 4 | 3 | 3 | 4 | 2 | 22 | |
| 17 | Anagrams (original equivalent) | 4 | 3 | 3 | 1 | 4 | 5 | 3 | 23 | Word content architecture shared with Word Hunt. |
| 18 | Word Bites (original equivalent) | 3 | 2 | 3 | 1 | 4 | 5 | 3 | 21 | |
| 19 | Shuffleboard | 3 | 2 | 3 | 3 | 3 | 4 | 3 | 21 | |
| 20 | Knockout | 3 | 2 | 3 | 3 | 4 | 4 | 3 | 22 | Physics; simultaneous-move feel is hard async. |
| 21 | Tanks | 3 | 3 | 2 | 4 | 4 | 3 | 3 | 22 | Terrain destruction; later. |
| 22 | Filler | 2 | 1 | 4 | 1 | 3 | 4 | 2 | 17 | |
| 23 | 20 Questions | 2 | 3 | 3 | 1 | 3 | 2 | 3 | 17 | Free text in an extension; moderation questions. |
| 24 | Crazy 8 | 3 | 3 | 3 | 3 | 4 | 3 | 3 | 22 | Group play; hidden hands need commit-reveal. |

## Order of work

Four in a Row (M1) → Darts (M2) → 8-Ball (M3) → re-theme (M4) → Rivalry Sets (M5) →
Store (M6) → beta (M7) → Cup Pong → Basketball → Mini Golf → Archery → 9-Ball → one word
game → one strategy game → original games.

This follows the brief's suggested order. The only score-driven deviation worth noting:
Cup Pong totals slightly higher than Darts, but Darts is cheaper to make deterministic and
introduces the projectile and anti-re-roll infrastructure Cup Pong needs, so it stays first.

## Architecture flags raised by the catalogue

- **Non-alternating turns** (8-Ball extra shots, Cup Pong bonus throws, Dots and Boxes):
  `Match.lastActor` assumes strict alternation today. Generalise when Darts/8-Ball lands
  (DECISIONS.md D-005).
- **Hidden information** (Sea Battle, Crazy 8): the message is readable by both sides, so
  hidden state needs commit-reveal or per-player encryption. Do not start these until designed.
- **Physics determinism** (8-Ball, Mini Golf, Cup Pong): replaying shots on another device
  needs fixed-step, platform-stable maths, or the message must carry the simulated result
  (and accept trust in the sender's device). Decide in M3; see ARCHITECTURE.md.
- **Content** (word games): our own dictionary pipeline and licence review before any word game.

## Original game candidates (post-launch)

Evaluated briefly against Messages constraints (async, ≤ 5,000-character state, no server):

| Idea | Async fit | Notes |
|---|---|---|
| Putt Duel | Good | One hole, one shot each; reuses Mini Golf. Best first original. |
| Trick Shot | Good | Same layout for both; highest score wins. Needs deterministic seeded layouts. |
| Penalty Shootout | Good | Shooter and keeper choices commit-reveal across two messages. |
| Three-Game Gauntlet | Good | Aggregates tiny games; builds on Rivalry Sets. Signature format candidate. |
| Higher / Lower Duel | Good | Seeded deck; cheap. |
| Memory Duel | Good | Seeded pattern; screenshots can cheat it. |
| Word Chain | Medium | Needs a word list. |
| Quick Draw | Poor | Reaction time is unverifiable on the sender's device. |
| Air Hockey Shot | Medium | Physics determinism again. |
