# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
