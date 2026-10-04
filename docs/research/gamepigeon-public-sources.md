# GamePigeon research notes (public sources only)

Compiled 2026-10-04. Sources: App Store listing, Wikipedia, press/student-newspaper articles, Apple Community threads, how-to guides.
No binaries or assets were inspected. Markers used below:
- **[sourced]**: stated directly by the linked source.
- **[weak source]**: from an SEO or AI-generated site (lilachbullock.com, grokipedia.com, pinkcrow.net, screenwiseapp.com). These sites contradict each other in places, so treat them as low confidence.
- **[inferred / unverified]**: my own inference, or memory not backed by a source.

Key URLs:
- App Store (US): https://apps.apple.com/us/app/gamepigeon/id1124197642
- App Store reviews: https://apps.apple.com/us/app/gamepigeon/id1124197642?see-all=reviews
- Wikipedia: https://en.wikipedia.org/wiki/GamePigeon

---

## 1. App Store listing facts (fetched 2026-10-04) [sourced: App Store URL above]
- Developer: **Vitalii Zlotskii**. Wikipedia and appshunter.io say the same. A jailbreak-tweak README calls the product "GamerDelights' GamePigeon" (https://github.com/donato-fiore/GameSeagull), which may be a seller or company name **[unverified]**.
- Price: **free, with in-app purchases**.
- In-app purchases listed (USD). The page shows the top 10:
  - GamePigeon+: $4.99
  - All Pool Cues: $4.99
  - Pool Cues - Evil Pack: $1.99
  - Pool Cues - Variety Pack: $1.99
  - Pool Cues - Animal Pack: $2.99
  - Pool Cues - Patterns Pack: $1.99
  - Cup Pong - Scary Pack: $1.99
  - Cup Pong - Variety Pack #1: $1.99
  - Cup Pong - Variety Pack #3: $1.99
  - All Aircrafts: $2.99 (presumably cosmetics for the Tanks/aircraft game **[inferred]**)
- Listed game catalogue (the description says **25 games**). The names below are as the listing gives them. That is 24 names, so the description's own count of 25 is probably off by one or uses an older count **[inferred]**:
  8-Ball, Mini Golf, Basketball, Cup Pong, Archery, Darts, Tanks, Sea Battle, Anagrams, Mancala, Knockout, Shuffleboard, Chess, Checkers, Four in a Row, Gomoku, Reversi, 20 Questions, Dots and Boxes, 9-Ball, Word Hunt, Word Bites, Filler, Crazy 8.
  - Poker was in the catalogue at launch and was later removed (Wikipedia). The old gamepigeonapp.com page still lists 8-Ball, Poker, Sea Battle, Anagrams and Gomoku with "More games are coming very soon!" (https://gamepigeonapp.com/).
- Rating: **4.0 / 5 from about 234K ratings** (US). appshunter.io reports 233K ratings and 3,717 reviews (https://appshunter.io/ios/app/1124197642). Wikipedia cites 162K at an earlier date.
- Requirements: **iOS 10.0 or later**, for iPhone, iPad and iPod touch. Size 108.8 MB. Age rating 13+ ("Frequent Cartoon or Fantasy Violence").
- Version: latest **2.2.6, dated 16 Sep 2024, "Bug fixes"**. Other versions: 2.2.5 (2023, bug fixes), 2.2.1 (2020, added Word Bites), 2.0 (2018, redesign with a new launcher and avatars). The app has had no new content for years.
- Release: **13 Sep 2016**, launching alongside iOS 10. It ranked #1 Top Free in the iMessage App Store about six months later (Wikipedia).

## 2. Messages flow from the user's side
- **Getting in.** On iOS 17 and later, the user taps "+" next to the text field, then GamePigeon, or "More" and then GamePigeon (https://www.igeeksblog.com/how-to-play-gomoku-on-imessage/, updated Oct 2025; https://9to5mac.com/2023/08/03/where-are-imessage-apps-ios-17/). Older guides describe the gray "A" App Store icon or ">" to show the app drawer (https://osxdaily.com/2020/11/06/how-play-games-messages-iphone-ipad/; https://friarslantern.news/8691/uncategorized/game-pigeon/).
- **Picking a game.** A grid of game tiles with names and pictures appears (osxdaily; friarslantern). In the compact drawer you swipe up the game menu (igeeksblog). Per Apple docs, an extension opened from the drawer starts in compact style, so the game grid is presumably the compact view **[inferred]**.
- **Options before sending.**
  - 8-Ball offers two modes, "8ball and 8ball+", and a choice of normal or hard difficulty (https://sharkscene.com/4013/entertainment/wanna-play-some-8ball/).
  - Darts has starting scores of 101, 201 or 301 [weak source: https://grokipedia.com/page/GamePigeon].
  - Archery has harder difficulty levels with a moving target [weak source: lilachbullock].
  - From memory, a mode or difficulty picker appears for several games before the invite is placed in the compose field **[inferred / unverified]**.
- **Sending.** Choosing a game puts an invite in the input field. The user can add a comment and then taps the send arrow (igeeksblog; osxdaily). This matches `MSConversation.insert`, where the user must tap Send **[inferred]**.
- **First move.**
  - Gomoku: the initiator's card shows "Waiting for Opponent" until the friend taps it. Black then moves first (igeeksblog).
  - "Your friend will have the first move so you'll have to wait until they play back" (friarslantern).
  - "The game cannot start until the recipient taps the message you sent" (osxdaily).
  - So the invite usually carries **no move**: the recipient opens it and the game starts **[sourced for Gomoku; general case inferred]**.
- **Bubble appearance.** "Friend receives the game card in the chat thread", and the opponent taps a "Play icon" and accepts (igeeksblog). An Apple Community user who did not have the app installed "could only see an image rather than play the actual game" (https://discussions.apple.com/thread/254884551, May 2023). This suggests a template layout with an image and a caption, not a live layout **[inferred]**. The exact caption text, for example "Your move", is **[unverified]**.
- **Opening a game.** Tapping the bubble opens the game in Messages' expanded or full presentation **[inferred from Apple docs: selecting a message launches the extension expanded]**.
- **Turn loop.** "You play a turn, it sends as a message, the other person taps it, plays their turn, sends it back" (https://www.lilachbullock.com/how-to-play-games-on-imessage/). In Gomoku you can adjust a marker before tapping "Send", and the move cannot be undone afterwards (igeeksblog). Every move notifies the other player (https://screenwiseapp.com/guides/ultimate-guide-to-imessage-games).
- **Multiple games.** Several games can run at once with different people (friarslantern). Earlier bubbles in the same game are probably replaced or collapsed by MSSession behaviour **[inferred / unverified]**.
- **Game end and rematch.** No source describes this. From memory, the final bubble shows the winner and the game screen offers a rematch that sends a new invite **[unverified]**. Users have asked for a way to rewatch past games (App Store review, 11 Jan 2022), which implies there is no replay feature.
- **Group chats.**
  - Crazy 8 supports 3–6 players and is "popular within group chats" (https://hsdial.org/2022/02/09/app-of-the-month-gamepigion/).
  - Most two-player games can be sent in a group thread, and the board games stay two-player [weak source: lilachbullock].
  - How the second player is chosen in a group (presumably whoever taps first) is **[unverified]**.
- **Recipient without the app.**
  - osxdaily says the recipient is prompted to install it from the App Store.
  - The Apple Community user saw only an image.
  - Android/SMS recipients get broken links or images: "the failure looks like a bug rather than what it is: a platform mismatch" [weak source: lilachbullock].
  - Apple's documented mechanism is the app-name attribution plus an install link; see research_messages.md.
- **Parental controls.** "game pigeon won't work if all the games on their device are shut off" (App Store review, 23 Dec 2025). A 2020 review raises the same issue.

## 3. Per-game notes (public descriptions only)
| Game | Rules / format | Controls | Length |
|---|---|---|---|
| **8-Ball** | Standard solids/stripes. Pocket your group, then the 8 in a called pocket [sourced: westwoodhorizon; pinkcrow]. Modes 8ball and 8ball+ (balls scattered at the start), normal or hard [sourced: sharkscene]. Spin via a red dot on the cue ball [weak: grokipedia]. | "position the cue where you want it and adjust how hard you push it" [sharkscene]. The GameSeagull cheat adds "trajectory line" and "disable hard mode", which implies hard mode limits the aim line **[inferred]**. | "Takes an extended period of time": the longest of the seven [westwoodhorizon] |
| **Darts** | Three darts per turn. Count down and hit the exact score to win [westwoodhorizon]. Start at 101, 201 or 301 [weak: grokipedia]. Called "a little convoluted and confusing". | Flick toward the board [weak: grokipedia] | Several turns **[inferred]** |
| **Four in a Row** | Connect-4 on a 6x7 grid. Four in a row in any direction wins [westwoodhorizon; weak: grokipedia]. | Tap a column **[inferred]** | "Rounds usually take under two minutes" [weak: lilachbullock]. Quick [westwoodhorizon]. |
| **Cup Pong** | Beer-pong style. Two throws per turn, and a hit removes a cup. Making both shots earns another turn [westwoodhorizon]. Cup count conflicts between sources: 9 [westwoodhorizon] vs 10 [weak: grokipedia]. First to clear all cups wins [game-solver.com review]. | Swipe or flick the ball upward [weak: grokipedia; lilachbullock] | Quick [westwoodhorizon] |
| **Basketball** | Three rounds, each a timed shooting period. The higher score wins [westwoodhorizon]. Round length conflicts: 45 s per round [weak: grokipedia] vs "24 seconds per turn" [weak: lilachbullock]. | Swipe up to shoot. Swipe speed and length set the arc [westwoodhorizon; grokipedia] | Short. "Requires no thinking" [westwoodhorizon]. |
| **Mini Golf** | Courses or levels change each game [westwoodhorizon]. Hole count conflicts: 9 [weak: lilachbullock] vs 18 [weak: grokipedia]. Wind is described as "rage-inducing" [weak]. | Swipe to putt [weak: grokipedia] | Called "only fun for one round" [westwoodhorizon] |
| **Archery** | Hit the bullseye while accounting for wind direction and strength. Distance increases each round [westwoodhorizon]. Three arrows per set, 10 points for a bullseye [weak: grokipedia]. Wind is visible in the cheat tweak's "wind elimination" and "fixed 50ft target distance" options, which implies variable distance [GameSeagull README]. | Draw and release **[inferred]** | Several rounds **[unverified]** |

Sources for the table:
- https://westwoodhorizon.com/2024/11/gamepigeon-games-tier-list/ (Nov 2024 student-newspaper tier list, firsthand)
- https://sharkscene.com/4013/entertainment/wanna-play-some-8ball/
- https://grokipedia.com/page/GamePigeon
- https://www.lilachbullock.com/gamepigeon-imessage-every-game-explained/
- https://game-solver.com/gamepigeon/

Most games also have a per-turn timer: the cheat tweak lists "Timer disabling" (GameSeagull README).

## 4. Monetisation
- **GamePigeon+ costs $4.99.** It is a one-time purchase, not a subscription, per an Apple Community answer that says "a quick look in the store suggests this is a one-time IAP" (https://discussions.apple.com/thread/252569602, Mar 2021). The listing does not show it as a subscription.
  - It removes ads and unlocks avatar accessories and game modes (appshunter.io; screenrant https://screenrant.com/play-gamepigeon-android-best-alternatives-apps/).
  - One reviewer says "lot of cool avatar items...you can only get by subscribing" (App Store review, 25 Oct 2023), using "subscribing" loosely.
  - Older or weak guides quote $2.99 to remove ads (screenwiseapp). That is probably an outdated price **[inferred]**.
- **Cosmetic packs** cost $1.99–$4.99: pool cues, Cup Pong cup sets and aircraft (App Store IAP list). Wikipedia also lists skins, avatar items, new game modes and ad removal.
- **Ads.**
  - In 2017 the developer tweeted that ads exist "To keep the servers up and running and to produce new games. You can disable ads by purchasing GamePigeon+" (https://x.com/gamepigeonapp/status/913534687041265666; seen in search snippet only, since the page is blocked to fetch).
  - Ads show between games [screenwiseapp; pinkcrow]. Parents' guides warn the ads are "designed to be clicked".
  - A YouTube video is titled "How To Fix Sudden Ads Appearing In GamePigeon" (https://www.youtube.com/watch?v=kHe2Yjq8pr4).
  - The tweet's mention of "servers" suggests some server component **[inferred]**.
- There are no loot boxes, currency or battle passes (screenwiseapp).

## 5. Complaints (with dates where known)
- **Stale content**: "no new content or updates" in seven years, and a request for "at least 6 new games" (App Store review, 2/5 stars, 14 Apr 2025). The last content update was in 2020 (version history).
- **Paywall and ads**: avatar items and modes sit behind GamePigeon+ (reviews dated 25 Oct 2023 and 19 Jun 2025).
- **Loading failures**:
  - "it just loads and loads and loads", fixed by turning Bluetooth off (review, 6 Jan 2022).
  - The app cannot be opened from Messages (review, 22 May 2023).
  - A white screen appears when opening an invite (https://imentality.com/gamepigeon-not-working-iphone-fix/, 2018–2022).
  - The app is stuck as a pending download after upgrading to a new iPhone, reported by six or more users (https://discussions.apple.com/thread/252344970, Jan 2021).
- **Send failures**: GamePigeon messages show "message failed to send" while ordinary texts go through (https://discussions.apple.com/thread/254762900, Apr 2023).
- **Freezes and bugs**: the game freezes mid-play (review, Nov 2018). Chess pawn promotion only allows queen or knight (review, 16 Jul 2025). 8-ball scoring is inconsistent and there are crashes (appshunter summary). There are sync glitches in multiplayer and group play [weak: grokipedia].
- **No instructions** in some games (review, Jul 2025). Darts rules are confusing (westwoodhorizon).
- **Missing features users ask for**: bots or single-player play, replays, achievements, a coin reward system, more customisation (reviews from 2018, 2020 and 2022).
- **iOS only**: the app does not work in chats with Android users (screenrant; lilachbullock).
- **Cheating**:
  - Jailbreak tweaks such as GameSeagull (v2.1, Feb 2024) add aim lines, remove wind, give auto hole-in-one, disable timers and "win spoofing".
  - Win spoofing suggests that game results are decided on the client **[inferred]**.
  - Web "solvers" exist for word games and Tanks (https://gamepigeon.win/).
  - Specific reports of screenshot or re-open exploits were **not found in sources [unverified]**.
- "Game expired" or "message failed to load" error strings: **not found in sources [unverified]**.

## 6. Known strengths
- No separate app to open: games sit inside the conversation and play is asynchronous ("Great way to connect with friends"; "amazing for long distance", review dated Jun 2025).
- A broad catalogue of familiar games, mostly free (App Store listing).
- Short sessions suit teenage social use. Gen Z teens cite it as a reason to use iMessage (Wikipedia). One user plays about 10 games a day (hsdial).
- Physics games such as 8-Ball and Cup Pong were praised in the press. The Daily Dot noted 8-Ball's responsive controls (Wikipedia).
- Monetisation is simple: one $4.99 unlock plus cosmetics, with "No loot boxes" (screenwiseapp).
