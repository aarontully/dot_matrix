# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
