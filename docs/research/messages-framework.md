# Apple Messages framework notes for turn-based iMessage games

Compiled 2026-10-04. Most of this comes from developer.apple.com documentation, read through its JSON endpoint (`https://developer.apple.com/tutorials/data/documentation/messages/<page>.json`). The human-readable URLs are given below. Anything I could not source is marked **[inferred / unverified]**.

Base URL: `D = https://developer.apple.com/documentation/messages`

## 0. Framework basics
- The Messages framework is available on iOS 10+, iPadOS 10+ and Mac Catalyst 14+ (framework page: D).
- An iMessage app can be a standalone app (Messages-only, not shown on the home screen) or an extension inside a containing iOS app (D; WWDC16 session 204 https://asciiwwdc.com/2016/sessions/204).
- **iOS 17**: users can resize iMessage apps with a vertical pan gesture. Apps that do manual touch handling should use gesture recognizers, or return NO from `gestureRecognizerShouldBegin` (D, framework overview).
- **iOS/iPadOS 18.2**: a user can choose a default messaging app other than Messages (D).
- The HIG says iMessage apps are "Not supported in macOS, tvOS, visionOS, or watchOS". Its advice: put essential features in the compact view, and let people edit text only in the expanded view (https://developer.apple.com/design/human-interface-guidelines/imessage-apps-and-stickers).
- Camera or microphone use requires `NSCameraUsageDescription` / `NSMicrophoneUsageDescription`, or the app crashes (D).

## 1. MSMessagesAppViewController lifecycle (D/msmessagesappviewcontroller)
**Activation**
- `willBecomeActive(with:)` and `didBecomeActive(with:)` fire when the user picks the extension from the app drawer **and** when the user taps a transcript message created by the extension.
- `willResignActive(with:)` and `didResignActive(with:)` run before and after dismissal. Docs: "Avoid doing any time-consuming tasks... avoid making asynchronous calls, because the extension might terminate before the asynchronous tasks have completed." So game state must be persisted synchronously.
- `dismiss()` closes the extension and marks it for termination, which triggers the resign callbacks. If the input field has content, the keyboard is shown.

**Message selection and arrival**
- `willSelect(_:conversation:)` and `didSelect(_:conversation:)` fire when the user selects one of the app's messages while the extension is active, and also when a new message arrives while it is active.
- `didReceive(_:conversation:)` fires for new messages from *this* extension that arrive while it is active.
  - Apple's pattern: compare `message.session` with `conversation.selectedMessage?.session` and refresh the UI if they match.
  - **Race warning** from the docs: "There is an inherent race condition when multiple participants send messages using the same session object. You cannot guarantee the order in which the messages are received." Apple suggests storing state on a server (e.g. CloudKit) and sending only an ID.
- None of the select, receive, start-sending or cancel-sending callbacks fire for a controller in `.transcript` style or in the `.media` context.

**Sending**
- `didStartSending(_:conversation:)` fires when the user sends a message that was inserted into the input field. It "does not guarantee that the message will be successfully sent or delivered."
- `didCancelSending(_:conversation:)` fires when the user deletes the staged message from the input field.

**Presentation style**
- `willTransition(to:)` and `didTransition(to:)` fire on compact↔expanded changes, whether from the user's collapse/expand buttons or from `requestPresentationStyle(_:)`. They are not called for transcript-style controllers.
- `presentationStyle` is set as follows:
  - Opened from the app drawer: **compact**.
  - Opened by tapping one of the app's messages in the transcript: **expanded**.
  - The user can toggle the style, or the app can request a change.
- `requestPresentationStyle(_:)`: "the user should have ultimate control". You cannot request `.transcript`. Calling it from a transcript-style controller creates a new controller instance in the requested style.
- `presentationContext` (iOS 12+) is `.messages` (the "+" list in Messages) or `.media` (Stickers, camera, FaceTime effects). It is opted into with the `MSSupportedPresentationContexts` Info.plist key.

## 2. MSConversation (D/msconversation)
- **`insert(_ message:completionHandler:)`** (iOS 10+) places the message in the input field, and the user must tap Send.
  - Subsequent calls replace any message already in the input field.
  - It works only in the `.messages` context; in `.media` it fails with `apiUnavailableInPresentationContext`.
  - The completion handler runs on a background queue.
  - If the message reuses an existing session, no new bubble is added. On send, the old message moves to the bottom of the transcript and is updated.
  - Source: D/msconversation/insert(_:completionhandler:)-3g248
- **`send(_ message:completionHandler:)`** (iOS 11+) sends with no further tap, but "only in response to a user action while in the messages context".
  - It fails with `sendWhileNotVisible` if the app isn't visible, and with `sendWithoutRecentInteraction` if there was no recent touch.
  - Session reuse behaves the same as `insert`.
  - Source: D/msconversation/send(_:completionhandler:)-9krz
  - WWDC17 adds that "subsequent direct send calls will fail until we detect another user interaction" (https://asciiwwdc.com/2017/sessions/234).
  - In iOS 10 there was "no way for your extension to automatically send a message" (WWDC16 session 224, https://asciiwwdc.com/2016/sessions/224).
- `insertText`, `sendText`, `insertAttachment`, `sendAttachment` and sticker insert/send also exist.
- **`selectedMessage`** is the message the user tapped, set at launch if that tap opened the extension.
  - Note from the docs: if the message belongs to a session it "might not contain the most current data" and "is not updated when you receive new messages". Use `didReceive` for updates.
- **`localParticipantIdentifier`**: a UUID "scoped to this device", stable while the extension stays enabled. It **changes if the extension is disabled and re-enabled, or the app is reinstalled**.
- **`remoteParticipantIdentifiers`**: UUIDs scoped to this device, with the same stability caveats.
- `MSMessage.senderParticipantIdentifier` is likewise "scoped to the current device. Each device participating in the conversation will have a different UUID for the message's sender." So there is no cross-device identity: the same person has different IDs on each device. To decide whose turn it is, a game must embed its own player identity or seat in the URL payload **[inferred]**.
- **Drafts**: `MSMessage.isPending` (iOS 11+) is true while the message sits in the input field after `insert`. It becomes false at `didStartSending` and is false for received messages. Use it to tell whether `selectedMessage` is a staged draft or a transcript message (D/msmessage/ispending).

## 3. MSMessage (D/msmessage)
- `init()` creates a non-updatable message. `init(session:)` creates one that is part of an updatable session.
- **`url`** carries the app data, e.g. as query items (Apple's examples use `URLComponents.queryItems`).
  - The scheme must be **http, https or data**; custom schemes are not supported.
  - **The URL cannot be longer than 5,000 characters**. This is documented on the property page, and as error `MSMessageErrorCode.urlExceedsMaxSize` ("longer than the maximum allowed length (5,000 characters)").
  - On macOS, selecting the message loads the URL in a web browser, so it "should point to a web service that returns a meaningful result" (D/msmessage/url).
  - WWDC16: data URLs are not sent in the fallback form to older platforms; only http(s) URLs are (session 224).
- **`session`** is the `MSSession` passed at init, or nil.
- **`summaryText`**: when a later message in the same session is sent, Messages uses the earlier message's summaryText as a summary line in the transcript. If it is nil, the system provides a default description.
- **`accessibilityLabel`** is read by VoiceOver.
- **`shouldExpire`** (default false): if true, the message is deleted shortly after it is read, unless the recipient chooses to keep it.
- **`senderParticipantIdentifier`** is set when the message is inserted and is device-scoped (see above).
- **`isPending`**: see above.
- **`error`** is set if sending failed, and is nil otherwise.
- **`layout`** is an `MSMessageTemplateLayout` or `MSMessageLiveLayout`.

## 4. MSSession: how bubbles collapse (D/mssession)
- The first message in a session appears normally.
- When a later message uses the same session, **the previous bubble is removed** and the new one is added at the bottom.
- If the previous message had a `summaryText`, a summary line is left in its old position.
- Documented workflow for each move:
  1. Read state from `selectedMessage.url`.
  2. Build a new URL, layout and summaryText.
  3. Create `MSMessage(session: selectedMessage.session)`.
  4. Call `insert` (or `send`).
  5. The transcript updates when the user taps Send.
- `MSSession` has no properties or methods; it is only an identity token.
- For a rematch, create a new `MSSession` so a new bubble chain starts **[inferred]**.

## 5. Layouts
**`MSMessageTemplateLayout`** (iOS 10+, D/msmessagetemplatelayout) shows the extension icon plus one of `image`, `mediaFileURL` (video or audio), and the text fields `imageTitle`, `imageSubtitle`, `caption`, `subcaption`, `trailingCaption` and `trailingSubcaption`.
- The system sizes the bubble. Do not subclass it.
- `image`: the system crops 6 pt from the left and right edges and rounds the corners. If `image` is set, `mediaFileURL` is ignored.
- `caption` is black text at the bottom-left below the image and wraps to three lines.
- `imageTitle` is white text at the bottom-left over the image.

**`MSMessageLiveLayout`** (iOS 11+, D/msmessagelivelayout) renders the extension's own view inside the transcript bubble.
- It requires an `alternateLayout` (a template layout) for devices without the app, devices older than iOS 11, macOS and SMS. That includes the sender's *own* other devices if they lack the app.
- Each live bubble gets its own `MSMessagesAppViewController` instance in `.transcript` style, with `selectedMessage` set before `willBecomeActive`.
- Several instances can run at once: one per live bubble, one for a staged message in the input field, and one for the active main UI.
- Bubble size comes from `contentSizeThatFits(_:)`, which must return a size no larger than the one offered (protocol `MSMessagesAppTranscriptPresentation`).
- WWDC17 says these views should be "really light weight": no "3D game engine" in transcript views, and heavy content belongs in expanded mode (session 234).

## 6. Presentation styles (D/msmessagesapppresentationstyle)
- **compact**: replaces the keyboard area. Avoid text fields there, and do **not** use horizontal scrolling or horizontal-swipe gestures (because the compact area swipes between apps; WWDC16 224). To show the keyboard, request expanded.
- **expanded**: fills most of the screen.
- **transcript** (iOS 11+): live layout in the transcript or input field.
- Apple's IceCreamBuilder sample opens compact with a history list. "Add" calls `requestPresentationStyle(.expanded)`, and `willTransition` swaps child view controllers. All state is passed via `URLComponents.queryItems`. A template layout image shows the current state. The sample notes that `insert` "will not send it immediately... If you prefer to send the message immediately then use the send(_:completionHandler:) method" (D/icecreambuilder-building-an-imessage-extension).

## 7. Recipient without the app, Mac and Watch
- **iOS recipient without the app** sees the template or alternate layout. The app name is shown under the content, and tapping it opens the Messages App Store to install. This is documented for stickers in WWDC16 session 204 ("tapping on the piece of text will launch the Messages App Store"). For interactive messages it is **[inferred]**, consistent with the user reports in research_gamepigeon.md.
- **Live layouts** fall back to `alternateLayout` (docs above).
- **macOS**: clicking an iMessage-app message opens `message.url` in the web browser (D/msmessage/url; WWDC16 224: "will try and get this URL and open it in your web browser"). Per the HIG, iMessage apps do not run on macOS, even though the framework lists Mac Catalyst availability.
- **watchOS**: you "can hand off interactive messages to a device where you're able to compose a reply" (WWDC16 224). The Watch cannot play the game.
- **SMS/RCS (Android)**: the template layout is described as supporting "SMS devices", meaning a degraded image or link. In practice users see broken links or images (see the GamePigeon notes). Whether iMessage-app messages carry over RCS (iOS 18+) is **[unverified]**.

## 8. Restrictions and capabilities
- **Network**: not required. All state can travel in the ≤5,000-character URL. Apple recommends a server or CloudKit plus an ID only to avoid session race conditions (didReceive docs). A local-only design must handle out-of-order or simultaneous moves, e.g. with a move counter or sequence number in the URL **[inferred]**.
- **Memory**: Apple documents no specific limit for Messages extensions. Extensions have lower jetsam limits than apps in general, and community figures (roughly 100–120 MB for iMessage extensions) are **[unverified]**. WWDC17 tells developers to keep transcript views light.
- **In-app purchases**: supported. WWDC16 204: "you will be able to use in-app purchase within your application". Forum threads discuss StoreKit inside iMessage extensions, e.g. `restoreCompletedTransactions` problems (https://developer.apple.com/forums/thread/113565) and receipt handling (https://developer.apple.com/forums/thread/682434). GamePigeon itself is a working example with $1.99–$4.99 IAPs.
- **Sending without a tap**: impossible. `insert` needs the user to tap Send. `send` needs the app to be visible and to have a recent user touch, and each send uses up that touch.
- **Stickers**: 500 KB maximum; PNG, APNG, GIF or JPEG (MSMessageErrorCode; HIG).
- **Error codes** (D/msmessageerrorcode): fileNotFound, fileUnreadable, improperFileType, improperFileURL, stickerFileImproperFileAttributes, stickerFileImproperFileSize, stickerFileImproperFileFormat, urlExceedsMaxSize, sendWhileNotVisible, sendWithoutRecentInteraction, apiUnavailableInPresentationContext, unknown.
- **App icon sizes** for Messages: 148x110, 143x100, 120x90 / 180x135, 64x48 / 96x72, 54x40 / 81x60, plus 1024x1024 for the App Store (HIG).

## 9. App drawer and OS changes over time
- **iOS 10 (2016)**: launch of the app drawer above the keyboard and the Messages App Store (WWDC16 204).
- **iOS 11 (2017)**: drawer redesigned as an icon strip with favourites and recents. Live layouts, `send()` and `isPending` added (https://www.macrumors.com/how-to/messages-app-drawer-ios-11/; WWDC17 234).
- **iOS 17 (2023)**: the drawer strip was replaced by a **"+" button** left of the text field. It opens a list with Apple's built-in items first. Third-party apps are reached by swiping up or tapping **"More"**. Users can drag apps into the top section (about 10 fit on an iPhone 14 Pro). The Store sits under More (https://9to5mac.com/2023/08/03/where-are-imessage-apps-ios-17/). iOS 17 also added pan-to-resize for iMessage apps (D).
  - Consequence: third-party games are now two to three taps deep, which hurts discoverability **[inferred]**.
- **iOS 18 (2024)**: Send Later, emoji tapbacks, RCS and text effects. No iMessage-app API changes were reported (https://www.macrumors.com/guide/ios-18-messages/). The 18.2 default messaging app setting is noted in the docs (D).
- **iOS 26 (2025)**: polls, chat backgrounds, typing indicators in groups, and unknown-sender screening. Nothing new for iMessage apps was reported (https://www.macrumors.com/2025/06/11/ios-26-new-messages-app-features/).
  - The new **Apple Games app** adds asynchronous "Challenges" (one day to one week) and a "Play Together" tab with invite links. These are Apple-only features and a potential competitor to iMessage game packs (https://www.macrumors.com/guide/ios-26-games-app/).
  - Whether the Games app integrates with the Messages "+" menu is **[unverified]**.
