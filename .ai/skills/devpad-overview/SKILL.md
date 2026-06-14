---
name: devpad-overview
description: Use this skill whenever working on the DevPad codebase — a native macOS developer utility (Swift/SwiftUI, macOS 13+) at /Users/bachbui/Desktop/source/dev-pad. Triggers on any file in DevPad/, DevPad.xcodeproj/, build_dmg.sh, or README.md. Provides the architectural overview, key singletons, sidebar Tool enum pattern, scene composition, and how the pieces fit together. Read this first before any DevPad work — then jump to a more specific skill (devpad-add-tool, devpad-conventions, devpad-macos-gotchas, devpad-release, devpad-review).
---

# DevPad — architectural overview

DevPad is a native macOS developer utility: a single window with a sidebar of tools, plus a menu-bar popover. No third-party dependencies. macOS 13+ deployment target, Swift 5, SwiftUI + AppKit where SwiftUI falls short.

## Project layout

```
DevPad/
├── DevPad.xcodeproj/                # Xcode project
├── DevPad/                          # Source
│   ├── DevPadApp.swift              # Scene composition (Window + MenuBarExtra + Settings)
│   ├── AppDelegate.swift            # Dock activation policy (.regular ↔ .accessory)
│   ├── MainWindowView.swift         # Sidebar nav with Tool enum + search field
│   ├── Models/
│   │   ├── AppSettings.swift        # Theme + language + dropShelfEnabled + purePasteEnabled
│   │   └── ClipboardItem.swift
│   ├── Utilities/                   # Engines / managers — no UI
│   │   ├── JSONFormatter.swift, XMLFormatter.swift, SQLFormatter.swift
│   │   ├── QRCode.swift, QRCamera.swift  (Vision-based camera scan)
│   │   ├── JWT.swift                 (decode + HMAC sign + RSA/ECDSA verify)
│   │   ├── RegexEngine.swift         (NSRegularExpression + named-group scanner)
│   │   ├── Hashing.swift             (CryptoKit + CommonCrypto, 8 algos + HMAC)
│   │   ├── DiffEngine.swift          (LCS line + word + hunk grouping)
│   │   ├── ClipboardManager.swift    (Timer + changeCount + Pure Paste)
│   │   ├── DropShelfManager.swift, DropShelfMonitor.swift
│   │   ├── DemoMode.swift            (--demo-fill seeding, #if DEBUG only)
│   │   └── Localization.swift        (EN + VI in-memory dicts)
│   ├── Views/                       # SwiftUI views, one per tab
│   │   ├── JSONFormatterView, XMLFormatterView, SQLFormatterView,
│   │   ├── URLParserView, QRGeneratorView, JWTInspectorView,
│   │   ├── RegexTesterView, HashGeneratorView, DiffCompareView,
│   │   ├── ClipboardHistoryView, ClipboardMenuBarView (tabbed popover),
│   │   ├── DropShelfView, DropShelfPanelView, MultiFileDragSource,
│   │   └── SettingsView
│   ├── Assets.xcassets/
│   ├── DevPad.entitlements          # app-sandbox + device.camera
│   └── Preview Content/
├── docs/screenshots/                # README screenshots
├── build_dmg.sh                     # Release build + DMG packaging
├── LICENSE, README.md
└── .ai/skills/                      # Shared instructions for AI coding agents
```

## Three scenes (`DevPadApp.swift`)

- `Window("DevPad")` — main window, renders `MainWindowView`. Width 1100, height 720.
- `MenuBarExtra(…)` — clipboard icon in macOS menu bar, opens a tabbed popover with Clipboard + Drop Shelf tabs.
- `Settings` — separate scene reachable via `⌘,`.

`AppDelegate` flips `NSApp.setActivationPolicy(.regular ↔ .accessory)` when the window opens/closes so closing the window hides the dock icon but keeps the app alive in the menu bar (Maccy/Bartender-style).

## Singletons (`@MainActor final class : ObservableObject`)

All accessed via `.shared`, live for the duration of the app, observed via `@EnvironmentObject` or `@StateObject`.

| Singleton | Owns | Used by |
|---|---|---|
| `AppSettings.shared` | theme, language, dropShelfEnabled, purePasteEnabled, pendingTool; `t(key)` localization lookup | every view that renders text |
| `ClipboardManager.shared` | clipboard history (Codable → UserDefaults), polling Timer, Pure Paste rewrite | ClipboardHistoryView, ClipboardMenuBarView, DemoMode |
| `DropShelfManager.shared` | shared URL list across popup / sidebar tab / menubar tab | DropShelfPanelView, DropShelfView, ClipboardMenuBarView, DropShelfMonitor |
| `DropShelfMonitor.shared` | global mouse + drag-pasteboard observer, NSPanel lifecycle | enabled/disabled from AppSettings.dropShelfEnabled |

`AppSettings.shared.t("key")` is the *only* way text reaches the UI. There is no other localization channel.

## Sidebar `Tool` enum (`MainWindowView.swift`)

This is the heart of the app — adding a tool means adding a case:

```swift
private enum Tool: String, CaseIterable, Identifiable, Hashable {
    case json, xml, sql, url, qr, jwt, regex, hash, diff, clipboard, dropshelf, settings

    var titleKey: String { switch self { case .json: return "sidebar.json"; … } }
    var icon:     String { switch self { case .json: return "curlybraces"; … } }   // SF Symbol
}
```

`MainWindowView` renders:
1. **Sidebar column** — search `TextField` at the top filters `Tool.allCases` by `settings.t(titleKey)` (works in either language). `List(filteredTools, selection: $selection)` below.
2. **Detail column** — `switch selection` maps each `Tool` case to its `View`, applies `.navigationTitle(settings.t("sidebar.<name>"))`.

The sidebar order is the same order tools appear in: `Features` bullets, the README sidebar table, and the screenshots grid.

## Per-tool view skeleton

Every tab follows the same shape — see `devpad-conventions` skill for the exact UI vocabulary:

```
VStack(spacing: 12) {
    modePicker            // segmented, centered, max-width 320 — IF multi-mode
    inputBar              // pattern field / text editor / drop zone
    flagBar / optionsBar  // optional
    errorBanner           // when error
    mainView              // result table / preview
    actionBar             // primary `⌘↵` button — `.borderedProminent`
}
.padding(16)
.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
.onAppear { if DemoMode.isOn, inputEmpty { input = DemoMode.sampleX; recompute() } }
```

Tools with multiple sub-modes (JWT decode/sign, QR generate/scan, regex match/replace, hash text/file/hmac) use a single `@State mode: Mode = .first` enum + segmented `Picker`.

## Engine ↔ View split

`Utilities/*.swift` files are pure logic — no SwiftUI, no `@MainActor`, no UI strings. Each defines an `XxxError: LocalizedError` enum with **English** `errorDescription` strings (intentional — engineers grep on these). The view layer wraps engine errors with a localized prefix:

```swift
Text("\(settings.t("xxx.error.prefix")): \(error.localizedDescription)")
```

This split lets engines be unit-tested standalone (none yet, but the option's there).

## Localization (`Utilities/Localization.swift`)

Two `[String: String]` dictionaries (`en`, `vi`) keyed identically. `AppSettings.t(key)` looks up the current language, falls back to English, then to the raw key.

Every `settings.t("…")` call **must** have its key in BOTH dictionaries. See `devpad-conventions` for the localization rules and `devpad-review` for the audit script.

## Demo mode (`Utilities/DemoMode.swift`)

Screenshot seeding for marketing. Launch with `--demo-fill` or `DEVPAD_DEMO_FILL=1` in env. Each view's `.onAppear` checks `DemoMode.isOn` and seeds its empty state. **Debug builds only** — `DemoMode.isOn` returns constant `false` in Release via `#if DEBUG`, so the entire injection path is dead-stripped.

## Window lifecycle

- Close red X → window hides, app keeps running in menu bar, dock icon disappears.
- Reopen via menu-bar popover → activation policy goes back to `.regular`, window comes up.
- Quit → `⌘Q` while window is focused, or the popover's Quit button. `applicationShouldTerminateAfterLastWindowClosed = false` prevents accidental quit-on-close.

## Where to dive next

- Adding a sidebar tool → **devpad-add-tool**
- UI / code / localization rules → **devpad-conventions**
- macOS / SwiftUI gotchas we've already hit → **devpad-macos-gotchas**
- Release build flags + DMG packaging → **devpad-release**
- Reviewing a change before commit → **devpad-review**
