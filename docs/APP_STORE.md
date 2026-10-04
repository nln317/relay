# App Store preparation

Nothing here has been done; each step needs the owner (brief §52). Listed so they are ready.

## Human actions required before any device or TestFlight build
1. Apple Developer Program membership (paid; owner decision).
2. Choose real identifiers: bundle id prefix (replaces `dev.relay`), App Group
   (replaces `group.dev.relay.shared`). Update `project.yml` and `SharedStorage.appGroup`.
3. Set `DEVELOPMENT_TEAM` in Xcode or `project.yml`.
4. Product name and trademark check (Relay is a working name). Must not use "GamePigeon".
5. Domain for the message fallback URL (replaces `relay.invalid`) with a simple page for Mac
   and Android recipients.
6. App icons: app icon (1024²) and the iMessage app icon set (sizes in
   research/messages-framework.md §8). Original artwork (M4).
7. Privacy policy URL; App Privacy label ("Data Not Collected" for M1).
8. Age rating questionnaire (no violence in Four in a Row).

## Review notes to include later
- Explain that the app is played inside Messages (+ → More → Relay).
- No account needed; purchases are cosmetic only.
