<h1 align="center">Dot Matrix</h1>

<p align="center">
  <b>A modern, cross-platform Matrix chat client built with Flutter.</b><br>
  Secure, fast, and beautifully designed for every device you own.
</p>

## What is Dot Matrix?

Dot Matrix is a **decentralized chat application** that connects you to the [Matrix](https://matrix.org) ecosystem. Unlike traditional messaging apps, Matrix gives you full control over your conversations — no single company owns your data, and you can host your own server or join any public homeserver.

Built from the ground up in **Flutter**, Dot Matrix runs natively on **Android, iOS, macOS, Linux, Windows, and Web** — one codebase, every platform.

---

## Core Features

### End-to-End Encryption
- Messages are encrypted using **Matrix's OLM/Megolm protocol** via `flutter_olm`
- Automatic key sharing and encrypted history recovery
- Lock icon indicators show when a conversation is fully encrypted

### Rich Messaging
- **Text** with full link preview and tappable URLs
- **Images & GIFs** with pinch-to-zoom full-screen viewer (`photo_view`)
- **Video** playback with inline thumbnails
- **Audio & Voice Messages** — record, send, and play voice notes inline
- **File Attachments** — share any document from your device

### Intuitive Chat Interactions
- **Swipe to Reply** — swipe any message to start a threaded reply
- **Message Actions** — reply, copy, forward, delete, edit, or react with emoji
- **Quick Reactions** — double-tap a message to open the emoji picker
- **Scheduled Messages** — compose a message now and send it later
- **Typing Indicators** — see when others are typing (without broadcasting your own)

### Organized & Polished UI
- **Date Separators** — messages are grouped by Today, Yesterday, or calendar date
- **Scroll-to-Bottom FAB** — quickly jump to the latest message when scrolled up
- **Keyboard Dismiss on Scroll** — swipe the conversation to hide the keyboard
- **Read Receipts** — know when your message has been delivered and synced
- **Unread Badges** — room list shows unread counts at a glance
- **Reply Threads** — tap a reply to jump directly to the original message

### Themes & Personalization
- Full **Material 3** design system support
- Adaptive light and dark modes that follow your system preference
- Custom color schemes and dynamic surface styling

---

## Screenshots

> Add your own screenshots to the repo root and reference them here.

| Room List | Chat | Attachments |
|-----------|------|-------------|
| `screenshots/rooms.png` | `screenshots/chat.png` | `screenshots/attach.png` |

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| **Framework** | Flutter 3.9+ |
| **State Management** | GetX |
| **Protocol** | Matrix SDK (`matrix` package) |
| **Encryption** | flutter_olm + flutter_openssl_crypto |
| **Local Cache** | Hive |
| **Media** | Cached Network Image, Photo View, Just Audio, Flutter Sound |
| **Pickers** | Image Picker, File Picker |
| **Navigation** | GetX named routes |

---

## Supported Platforms

| Platform | Status |
|----------|--------|
| Android | ✅ Supported |
| iOS | ✅ Supported |
| macOS | ✅ Supported |
| Linux | ✅ Supported |
| Windows | ✅ Supported |
| Web | ✅ Supported |

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.9 or newer
- A Matrix homeserver account (or run your own with [Synapse](https://github.com/element-hq/synapse))

### Installation

```bash
git clone <repo-url>
cd dot_matrix
flutter pub get
flutter run
```

### Build for Production

```bash
# Android
flutter build apk
flutter build appbundle

# iOS / macOS
flutter build ios
flutter build macos

# Linux
flutter build linux

# Windows
flutter build windows

# Web
flutter build web
```

---

## Architecture Highlights

- **GetX Controllers** manage room lists, timelines, auth state, and settings
- **Hive** persists auth tokens and room metadata locally
- **flutter_secure_storage** keeps credentials safe behind platform keychains
- **CachedNetworkImage** ensures media loads instantly on revisits
- **GetX reactive streams** power real-time sync and typing indicator updates

---

## Security & Privacy

- Your credentials are stored in the OS secure keychain
- All conversations support optional end-to-end encryption
- No telemetry or analytics are collected by the app itself
- Data lives on your chosen homeserver, not on a proprietary backend

---

## Roadmap

- [x] End-to-end encryption
- [x] Voice messages
- [x] Scheduled messages
- [x] Message reactions & edits
- [x] Reply threads
- [ ] Push notifications
- [ ] Spaces & sub-rooms
- [ ] Message search
- [ ] Custom themes / accent colors

---

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

---

## License

This project is proprietary and maintained by **House Tully**.

<p align="center">Built with 💙 by House Tully</p>
