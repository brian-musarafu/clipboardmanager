# Clipio

A fast, private, native macOS clipboard manager. Lives in the menu bar, keeps a
searchable history of everything you copy, expands text snippets, and adds
on-device intelligence — all without sending your data anywhere.

Built with SwiftUI + SwiftData, Swift 6, for macOS 14+.

---

## Features

### History
- Automatic capture of **text, images, and files** from the clipboard
- **Search**, **pin** important items to the top, and mark **favorites**
- **Category filters**: All / Text / Code / Links / Images / Files
- Click an item to **paste it straight into the focused field**; links open in
  the browser; files can be opened or revealed in Finder
- **Drag any item** into another app
- History survives restarts (local SwiftData store)

### Global shortcuts
- **⌘⇧V** — summon the quick-access panel from anywhere
- **⌘⇧1** — paste the most recent pinned item into the frontmost app

### Smart clipboard (on-device)
Click the ✨ button on a text item for context-aware actions:
- **Links** — open, copy, shorten (via is.gd)
- **Email** — compose, copy address
- **Color** (`#hex`, `rgb()`) — swatch preview, copy HEX/RGB
- **JSON** — pretty-print, validate
- **QR code** — generate from any text
- **AI** — detected language, extractive **summary**, and Apple **Translate**

### Snippets & text expansion
- A **snippet library** (menu-bar → Snippets) with triggers like `/sig`
- Type a trigger in **any app** and it expands instantly (no clipboard involved)
- **Variables**: `{{date}}`, `{{time}}`, `{{datetime}}`, `{{username}}`,
  `{{user}}`, `{{uuid}}`

### Images (AI)
- **OCR** — extract text from any image with on-device Vision, then copy it or
  save it to history

### Security & privacy
- Content marked concealed by **password managers is never captured**
- **Card numbers / SSNs** are detected, **redacted**, and **AES-256 encrypted**
  at rest (key in the login Keychain)
- Revealing, copying, or pasting a secret requires **Touch ID**
- **Private Mode** — pause all tracking with one click
- No analytics, no network calls except explicit user actions (link shortening,
  translation)

### Backup & sync
- **Export** history + snippets to **JSON**, or history to **CSV**
  (sensitive items are excluded from backups)
- **Import** a JSON backup (merges, skipping duplicates)
- **iCloud sync** is code-ready (see below)

### Convenience
- **Launch at Login** toggle
- Menu-bar only (no Dock icon)

---

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘⇧V | Open the quick-access panel |
| ⌘⇧1 | Paste the most recent pinned item |
| Esc | Dismiss the quick-access panel |

---

## Permissions

Clipio needs one system permission for two of its features:

- **Accessibility** (System Settings → Privacy & Security → Accessibility) —
  required to paste into other apps and to run global text expansion.
- **Touch ID / password** — prompted only when you reveal a sensitive item.

The app runs **outside the App Sandbox** (like other paste-capable clipboard
managers), which is why it's distributed by direct download rather than the Mac
App Store.

---

## Build & install

Requirements: Xcode 26+, macOS 14+.

```sh
# Debug build & run
xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager \
  -configuration Debug build -allowProvisioningUpdates

# Release build
xcodebuild -project ClipboardManager.xcodeproj -scheme ClipboardManager \
  -configuration Release build -allowProvisioningUpdates
```

Or just open `ClipboardManager.xcodeproj` in Xcode and press ⌘R.

The Release app installs to `/Applications/Clipio.app`.

---

## Enabling iCloud sync

Sync is wired in code — the models are CloudKit-compatible. The store is
currently **local** (`cloudKitDatabase: .none` in `AppEnvironment`); it is
deliberately *not* `.automatic`, because that stands up CloudKit mirroring on
the local store even without an iCloud account and can destabilise local data.
To enable real sync:

1. The Apple Developer **account holder accepts the current Program License
   Agreement** at developer.apple.com.
2. In Xcode → target → **Signing & Capabilities**, add the **iCloud** capability
   and check **CloudKit** (container `iCloud.com.brianmusarafu.ClipboardManager`).
3. Change `.none` to `.automatic` in `AppEnvironment.makeContainer()`.

> Note: sensitive (encrypted) items use a device-local Keychain key, so they
> won't decrypt on other devices. Consider excluding them from sync or moving
> the key to iCloud Keychain before enabling.

---

## Architecture

MVVM + a small service layer.

```
ClipboardManager/
├── App/            ClipboardManagerApp, AppEnvironment (object graph)
├── Models/         ClipboardItem, Snippet, ItemType, CategoryFilter
├── Services/       ClipboardMonitor, PasteService, HotKeyManager,
│                   TextExpansionService, KeyInjector, SmartContentDetector,
│                   SensitiveContentDetector, CryptoService, AuthService,
│                   AIService, BackupService, LoginItemService, …
├── ViewModels/     ClipboardViewModel, SnippetsViewModel
└── Views/          MainView, HistoryListView, ItemRowView, SearchBarView,
                    SmartDetailView, SnippetsView
```

Data is stored locally with SwiftData; sensitive fields are encrypted with
CryptoKit (AES-256-GCM).

---

*Author: Brian Musarafu*
