# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

## [v1.0.11-alpha] - 2026-05-29

### Changed
- **First-time device setup** — onboarding now focuses on verifying the device only; encrypted-history backup restore stays available from Settings > Encryption instead of blocking first-time setup completion.

### Fixed
- **Reopen crypto-key restore failure** — `AuthController._init()` now passes the stored `olm_account` back to the Matrix SDK when restoring a session. Previously the SDK ignored the saved crypto state whenever `newToken` was supplied, generated a fresh Olm account on every app launch, and then failed to upload the conflicting device keys. This caused users to be silently logged out on every reopen.
- **Notification setup retries** — local/Firebase notification initialization is retried when enabling notifications or rebinding after app restore, so a transient startup failure no longer leaves notifications unavailable for the rest of the run.
- **Verification completion state** — device setup now marks verification complete immediately after a successful SAS flow and rechecks verification state before refreshing the screen.

## [v1.0.10-alpha] - 2026-05-27

### Fixed
- **Android secure-storage recovery** — corrupted encrypted storage entries now recover back to a clean signed-out state instead of surfacing `BAD_DECRYPT` / `BadPaddingException` startup errors when `flutter_secure_storage` cannot decrypt saved app secrets.

## [v1.0.9-alpha] - 2026-05-27

### Fixed
- **Startup blocked by notification setup** — app launch and saved-session restore no longer wait for local notification/plugin initialization before showing the UI, and the Android notification icon resource has been restored to the pre-`v1.0.7-alpha` vector so notification setup failures stop freezing the app on open.

## [v1.0.8-alpha] - 2026-05-27

### Fixed
- **Opening-screen startup hang** — restoring a saved Matrix session no longer waits indefinitely on remote token validation before the app can open. When the homeserver is slow or temporarily unreachable, Dot Matrix now falls back to the cached local session instead of leaving the launch loader stuck.

## [v1.0.7-alpha] - 2026-05-27

### Changed
- **Device verification target picker** — starting verification now shows your other logged-in sessions first instead of blindly targeting the most recently active device, with verified sessions surfaced at the top so you can choose which device should receive the SAS prompt.
- **App icon sizing** — tightened the source logo padding and regenerated the launcher/web/desktop icon sets so the Dot Matrix mark reads larger in the app icon surfaces and tray-like system UI.

## [v1.0.6-alpha] - 2026-05-26

### Added
- **In-room search** — chats now include a dedicated room search flow so you can quickly jump to matching messages without backing out to the home screen.
- **Persistent scheduled messages** — scheduled sends are now saved locally per room and restored after app restarts instead of disappearing when the process is killed.
- **Spaces management** — added a Spaces management screen for creating, renaming, and deleting spaces from inside the app.
- **Android notification actions** — incoming message notifications now expose direct actions to open the room or mark it as read.
- **Android video PiP** — the fullscreen video player can now enter Android picture-in-picture mode on supported devices.

### Changed
- **Video playback controls** — the fullscreen player now includes quick seek controls and playback-speed selection alongside the scrubber.
- **Push gateway storage** — configured push gateway URLs now live in secure storage instead of the plain local settings box, with stricter validation before registration.
- **Matrix media auth** — authenticated media and avatar fetches now use Matrix media URLs directly instead of forwarding bearer headers through redirectable image requests.
- **Transport hardening** — Matrix HTTP traffic and direct media downloads now validate HTTPS certificates against pinned/build-configured fingerprints and remember trusted certificates per host for subsequent sessions.

### Fixed
- **Startup failure handling** — app startup now surfaces storage/bootstrap failures instead of crashing or hanging on a blank screen when local settings or Firebase setup are unavailable.
- **Stored-session restore** — saved Matrix sessions now keep error states visible, stop booting through connectivity failures, and always reuse the validated token during client initialization.
- **Bridge media timeline performance** — bridge placeholder resolution now preindexes candidate media events instead of scanning the full timeline for every message.
- **Mention rendering performance** — mention normalization now rewrites visible mentions in a single tokenized pass rather than running a replacement regex for every room participant.
- **Redacted and dated timeline rendering** — redacted messages now render as deleted, and chat timestamps/date separators now respect local device time.
- **Typing and room actions** — typing notifications are now sent to the room as you compose, Matrix user IDs are validated before starting a DM, and the unused translation action has been removed.
- **Session and encryption helpers** — room/account-data waits now time out safely, bridge-identity sync is shared through Matrix account data, and avatar uploads keep the original source quality instead of being double-compressed.
- **Room and notification edge cases** — room member counts are consistent, bot-name filtering no longer strips names like "Robot", notification IDs stay positive, and sync notifications can still appear while the app is inactive.

## [v1.0.5-alpha] - 2026-05-26

### Added
- **Notification opt-in onboarding** — fresh sign-ins now get a one-time prompt asking whether DotMatrix should turn notifications on, and the choice is saved for later.
- **`@` mention suggestions in chat** — the composer now suggests room members as you type `@`, including bridged accounts, and inserts Matrix-resolvable mentions for the selected user.
- **Basic other-user profile screen** — member rows in Chat Info now open a lightweight profile view showing avatar, name, Matrix ID, bridge detection, and a quick local action to mark that account as one of your bridge identities.
- **Visible-member room avatars** — one-to-one bridged chats now derive header avatars from the same filtered visible members list, so your own bridge identities and bridge bots do not leak back into the room avatar.

### Changed
- **Notification preferences** — the in-app Notifications screen now requests system permission when you enable alerts and explains the current local-alert versus background-push behavior more clearly.
- **Notification gateway setup** — the Notifications screen now lets you save or clear the Matrix push gateway URL that DotMatrix registers for real background delivery.
- **Automatic gateway reuse** — DotMatrix now tries to reuse an existing Matrix HTTP pusher on the account before asking for any manual push gateway configuration.
- **Built-in gateway fallback** — DotMatrix can now fall back to an app-wide default Matrix push gateway configured at build time, so first-time Matrix users do not need to enter a push URL manually.
- **Push setup guidance** — the project docs and Firebase runtime logging now call out the exact Android, iOS, APNs, and Matrix push-gateway pieces still required for real background delivery.
- **Bridge identity updates refresh rooms immediately** — adding or removing an "also me" account now refreshes room summaries right away so member counts and bridge filtering stay in sync.
- **Media scrolling path is lighter** — chat bubbles now cache resolved media preview state, decode preview images closer to display size, and defer full encrypted video downloads until you actually tap the video instead of doing that work while scrolling.
- **Audio recording** — migrated from `flutter_sound` to `record` for broader platform support (Windows, macOS, iOS, Android).
- **Audio playback** — migrated from `just_audio` to `audioplayers` for broader platform support (Windows, macOS, iOS, Android, Web, Linux).
- **`pubspec.yaml` dependencies**:
  - Removed `flutter_sound: ^9.2.13` and `just_audio: ^0.9.46`
  - Added `record: ^5.2.0` and `audioplayers: ^6.0.0`
  - `version`: `1.0.2+3` → `1.0.5-alpha+4`

### Fixed
- **Mention name rendering** — sent and received mentions now display as readable `@Name` text in the timeline instead of raw Matrix mention syntax or bridged MXIDs.
- **Live message notifications** — DotMatrix now raises real local notifications for new Matrix events, including mentions/highlighted activity, while suppressing alerts for your own sends and the room you already have open.
- **Android Firebase config discovery** — `google-services.json` now lives in `android/app/`, allowing the Google Services plugin to generate the Firebase resource values that `Firebase.initializeApp()` expects at runtime.
- **Activity feed scope** — the Activity tab now only surfaces interactions that are directly related to you: replies to your messages, mentions of you, and reactions to your messages. General messages from others in group chats are no longer shown here.
- **Camera/gallery send stability** — picked image previews now decode at thumbnail size, camera/gallery imports are resized before staging, and image/video sends avoid an extra byte-copy so sending large photos is much less likely to freeze or crash the composer.
- **Unverified-device send confirmation** — encrypted chats now warn before sending when the room has unverified Matrix devices, so people can choose whether to share room keys with those devices.
- **Media send-state badges** — image, video, audio, and upload-placeholder bubbles now show the same pending/sent/error status indicator as text messages, driven from the underlying Matrix event status.
- **Session removal re-authentication** — removing another signed-in device now handles Matrix homeservers that require password confirmation for device deletion instead of failing with a forbidden error.
- **Fresh-session trust detection** — device setup, post-login verification prompts, chat warnings, and the Sessions list now treat the current device as trusted only after the session is actually signed by your account, which fixes cases where a brand-new login incorrectly showed as already verified.
- **Olm to-device decryption failures on reinstall** — added a guard in `AuthController._init()` that resets the stored session when the local Matrix database is missing but credentials still exist in secure storage. This prevents the app from reusing an old `deviceId` with a fresh Olm account, which breaks decryption of cross-device messages.
- **macOS dynamic library loading** — added `/opt/homebrew/lib` to `LD_RUNPATH_SEARCH_PATHS` and extended the Flutter embed build script to copy `libcrypto.3.dylib` and `libolm.3.dylib` into the app bundle's `Contents/Frameworks` directory after each build. Also installed `libolm` via Homebrew, which the Matrix SDK requires for E2EE on desktop.
- **macOS keychain access (debug)** — removed `com.apple.security.app-sandbox` from `DebugProfile.entitlements` so `flutter_secure_storage` can access the keychain during unsigned local debug builds. The sandbox remains enabled in `Release.entitlements` for production.

## [v1.0.4-alpha] - 2026-05-20

### Added
- **Video thumbnail generation helper** (`lib/utils/video_thumbnail_helper.dart`) — centralizes local poster-frame extraction for sent and decrypted videos using `fc_native_video_thumbnail`, and reads basic video metadata (width, height, duration) for richer Matrix video events.
- **Guided device setup screen** (`lib/screens/device_setup_screen.dart`) — introduces a friendlier checklist-based flow for recovery and device verification, with progress, clear next actions, and a live status snapshot.

### Changed
- **Outgoing video sends** — videos are now sent as proper `MatrixVideoFile` events with metadata and an uploaded JPEG thumbnail, so clients have a real preview frame instead of a blank white/black box with only a play icon.
- **Video bubble preview behavior** — unencrypted video bubbles now prefer Matrix thumbnail URLs for in-chat preview instead of trying to decode the raw video download URL as if it were an image.
- **Chat timeline rendering** — the chat screen now caches sorted message views, reply targets, read-receipt anchors, and room-key banner state instead of recomputing them on ordinary composer/focus rebuilds.
- **Message bubble media detection** — visual-media, audio, caption, and room-key state are now derived once when room events are built, reducing per-bubble regex scanning during scroll.
- **Encryption setup entry points** — first login, the Home menu nudge, and Encryption settings now all route into the same device setup guide, so recovery and verification follow one consistent path.

### Fixed
- **Post-login blank screen** — replaced the empty auth loading state with a proper loader screen so signing in no longer flashes a black gap between the login form and the app.
- **Fresh-login recovery and verification flow** — new-device onboarding now waits for the app shell, offers recovery-key restore first when Secure Backup is available, shows a clear info dialog when it is not, and then prompts for device verification or explains when no other device is available.
- **Missing device verification prompt after sign-in** — the verification listener and onboarding prompt now run after a new login, which fixes cases where device verification never appeared on first sign-in.
- **Encryption status clarity** — the status UI now tracks current-device verification separately from encrypted-history recovery, so setup progress is easier to understand at a glance.
- **Room-key warnings after verification** — completing device verification now refreshes Secure Backup, room timelines, and settings so stale "Waiting for room key" warnings clear properly.
- **Camera capture preview flow** — taking a photo now stages it in the compose preview strip instead of bypassing the preview and jumping straight into send logic.
- **Attachment preview crashes with picked videos** — pending media previews no longer try to decode videos as still images; video selections now render with a safe thumbnail/placeholder tile.
- **Shared media captions** — image/video shares that include meaningful text now render that text beneath the media instead of showing only the picture.
- **Blank video previews before playback** — fixed the issue where video messages could appear as an empty black/white rectangle until tapped. New videos sent from the app now include a thumbnail, and encrypted received videos can generate a local fallback poster if the event is missing thumbnail metadata.
- **Remote video fallback rendering** — when a video has no preview image available, the bubble now falls back to a clean tappable video placeholder instead of surfacing a broken-image style failure state.
- **Bridge-embedded image display** — fixed "Waiting for attachment" messages from the Google Messages bridge (and similar bridges using `fi.mau.gmessages.raw_debug_data`) not rendering. `_isVisualMedia` now detects base64 image signatures inside bridge raw debug data, and `_MediaAttachmentBubble._loadMedia` extracts and decodes the embedded image bytes directly.
- **Bridge image pixelation** — bridge-embedded images now decode their actual pixel dimensions via `decodeImageFromList`, and the display size is capped to the native resolution so small images are no longer upscaled and blurred. Also switched to `BoxFit.contain` with `FilterQuality.high` for cleaner rendering.
- **Media URL candidate ordering** — full-resolution download URLs are now added to preview candidates before thumbnail fallbacks, preventing small 250×250 thumbnails from being displayed scaled up.
- **Chat scroll stutter in long rooms** — removed noisy per-bubble debug logging and eliminated repeated reply-resolution scans during list builds, which reduces hitching when scrolling back through message history.

## [1.0.1] - 2026-05-18

### Added
- **Emoji-based device verification** — initiate interactive verification from Encryption Settings. Picks the most recently active other device, sends a SAS verification request, and displays emoji comparison for manual confirmation. Supports both outgoing (tap "Verify Device") and incoming (auto-popup when another device initiates) verification flows.
- **Device verification dialog** (`lib/widgets/device_verification_dialog.dart`) — full-screen dialog that handles all KeyVerification states: accept/decline incoming requests, show 7 emoji pairs for comparison, "They match"/"Don't match" buttons, and success/failure states.
- **Incoming verification listener** — `AuthController` subscribes to `client.onKeyVerificationRequest` and auto-opens the verification dialog when another device requests verification.

### Changed
- **Removed "Ask devices again" buttons** from home screen and chat screen recovery nudges. Replaced with "Open recovery tools" button that navigates to Encryption Settings.
- **Encryption Settings UI** — "Ask verified devices" / "Ask devices again" buttons replaced with single **"Verify Device"** button (icon: `verified_user_outlined`).
- **`Client` constructor** — added `verificationMethods: {KeyVerificationMethod.emoji}` to enable SAS emoji verification in the Matrix SDK.

### Fixed
- **Verification request targeting** — previously sent to only the first device or broadcasted with `*` (which only reaches already-verified devices). Now queries server device list, sorts by `lastSeenTs`, and sends to the most recently active device specifically.
- **Auto-refresh after verification** — after the verification dialog closes, automatically calls `ssss.maybeRequestAll()` + `requestMissingEncryptionKeys()` + `refreshSettings()` so the recovery nudge disappears without requiring manual navigation.

## [1.0.0] - 2026-05-18

### Added
- **Custom `DotMatrixLoader`** widget — replaces generic `CircularProgressIndicator` across the app with a 5×5 animated dot-grid wave (like an LED matrix display)
- **`DotMatrixLoadingText`** helper widget for pairing the loader with text labels
- **Logo** (`assets/logo.svg` / `assets/logo.png`) — dot-matrix themed chat bubble icon
- **Launcher icons** via `flutter_launcher_icons` — logo applied as app icon on Android, iOS, Web, Windows, and macOS
- **Comprehensive README** — replaced 4-line stub with full project documentation including features, tech stack, supported platforms, build commands, architecture highlights, security notes, and roadmap
- **`CHANGELOG.md`** — this file to track all future changes
- **Read receipt avatars** — Messenger-style overlapping avatar circles appear below the most recent outgoing message that other users have read. Shows up to 3 reader avatars with a "+N" overflow indicator. Excludes the sender's own read receipt.
- **Media download** — download button added to fullscreen image viewer and video player. Saves encrypted/unencrypted images and videos directly to the device gallery using the `gal` package.
- **Haptic feedback** — added tactile vibration across key interactions: long-press message (medium impact), double-tap to react (light impact), swipe-to-reply (medium impact), send message (light impact), copy (light impact), action sheet taps (light impact), delete (medium impact), and room list taps (selection click).

### Changed
- **Bundle identifier** updated from `com.example.dot_matrix` → `com.housetully.dotmatrix` across all platforms:
  - Android: `namespace`, `applicationId`, `MainActivity.kt` package + directory structure
  - iOS/macOS: `PRODUCT_BUNDLE_IDENTIFIER` (app + test targets), `AppInfo.xcconfig` copyright
  - Linux: `APPLICATION_ID` in `CMakeLists.txt`
- **`pubspec.yaml` metadata**:
  - `version`: `0.1.0` → `v1.0.0-alpha`
  - `description`: `"A new Flutter project."` → `"Dot Matrix - A secure, cross-platform Matrix chat client with end-to-end encryption, rich messaging, and a modern Material 3 interface."`
  - Added `assets/logo.png` to `assets` block
  - Added `flutter_native_splash` and `flutter_launcher_icons` to `dev_dependencies`

### Fixed
- **Removed outgoing typing notifications** — app no longer broadcasts when the local user is typing, while still displaying other users' typing status

### Chat QoL Improvements
- **Keyboard dismiss on scroll** — swipe the message list to hide the keyboard
- **Scroll-to-bottom FAB** — floating action button appears when scrolled up, jumps to latest message
- **Date separators** — messages grouped by "Today", "Yesterday", or full date
- **Swipe-to-reply** — swipe any message left/right to initiate a reply
- **Message timestamps** — shown on text, media, image, video, and audio bubbles

### Known Issues / Notes
- iOS launcher icon may contain an alpha channel — set `remove_alpha_ios: true` in `flutter_launcher_icons` config before App Store submission

---

## [0.1.0] - Pre-release
- Initial Flutter project scaffold
- Matrix SDK integration
- Basic chat, room list, and authentication flow
