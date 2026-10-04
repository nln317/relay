# Privacy

- **No account, no server, no network access** in M1. Game state travels inside iMessage
  messages, which are end-to-end encrypted by Apple between iMessage users.
- **What is in a message:** game id, match id (random UUID), move history, rematch record,
  equipped cosmetic ids. No names, no contact data. Bubble captions never name anyone.
- **On device:** a small ledger file (≤ 200 recent matches: match ids, message URLs, seat,
  timestamps) in the App Group container, used only for recovery.
- **Participant identifiers** are used transiently to tell "sent by me" from "sent by them"
  and are never stored or sent anywhere.
- **Analytics:** no sink exists yet; the planned events contain no personal data (ANALYTICS.md).
- App Store privacy label for M1 would be "Data Not Collected". Re-evaluate when analytics or
  StoreKit ships.
