# DevPad — Claude skills

This folder contains six skills that document the DevPad codebase's conventions, architecture, and gotchas in enough detail that Claude (or a new human contributor) can work on this project without re-discovering the painful lessons.

## How to install

Move (or copy) the contents of this folder into `.claude/skills/` at the repo root:

```bash
mv skills/devpad-* .claude/skills/
```

Claude will auto-discover them. Each skill's `description` field declares when it should fire — Claude reads them lazily.

## The six skills

| Skill | When it fires | What it covers |
|---|---|---|
| **devpad-overview** | First touch of any DevPad file | Project layout, scenes, singletons, sidebar `Tool` enum, per-tool view skeleton, engine ↔ view split, localization model, demo mode. Read first. |
| **devpad-add-tool** | "thêm tính năng X" / "add a new tab for …" | Step-by-step recipe for adding a sidebar tool: utility, view, `Tool` enum wiring, EN+VI localization, `DemoMode` sample, `pbxproj` registration (4 places per file), README updates, verify. |
| **devpad-conventions** | Writing or editing any Swift file | UI vocabulary (mode picker, action bar, empty state, error banner, drop zone, output preview), code style (`@MainActor` singletons, `@StateObject`, comments), localization rules (mirror EN/VI, English engine errors, `settings.t(...)`), threading (`DispatchQueue.main.async` over `Task { @MainActor }`). |
| **devpad-macos-gotchas** | Touching AVFoundation, AppKit layer-hosting, SwiftUI macOS-13 quirks, Swift concurrency across actors, NSPasteboard, CommonCrypto, CryptoKit | 15 specific gotchas with **symptom → root cause → fix**. Includes AVCaptureMetadataOutput rejecting .qr, layer-hosting `makeBackingLayer`, Task @MainActor crash on macOS 13, delegate teardown race, etc. |
| **devpad-release** | Editing Release build settings, `build_dmg.sh`, `DevPad.entitlements`, demo mode gating | Release tuning (`LLVM_LTO`, `-Osize`, `STRIP_*`, `DEPLOYMENT_POSTPROCESSING`, asset compress, etc.), DMG `-format ULFO`, ad-hoc vs signed builds, versioning, what NOT to change. |
| **devpad-review** | Auditing a change before commit | Per-concern checklists (UI, concurrency, engine, build config, localization) plus ready-to-run bash audit scripts (brace balance, EN/VI mirror, pbxproj 4-place sanity, hardcoded-string scan). |

## Recommended reading order for a newcomer

1. `devpad-overview` — read it end-to-end (~5 min).
2. Skim `devpad-conventions` — understand the UI vocabulary before opening any `Views/` file.
3. Scan `devpad-macos-gotchas` headings — know what's lurking when you touch AVFoundation or SwiftUI.
4. Open `devpad-review` for the audit scripts — bookmark them. Run before every commit.
5. `devpad-add-tool` and `devpad-release` are reference material — pull them up when the task matches.

## Why six skills instead of one big doc?

Each skill stays focused so Claude only loads what's relevant. A regex-engine review doesn't need the DMG packaging notes; an architecture overview shouldn't bury the AVFoundation gotchas. The Skill tool's `description` field acts as a router — keep them tight and Claude will pick the right one without re-reading everything.

## Updating the skills

When you discover a new gotcha worth remembering:
- Same category as an existing skill → append it there (especially `devpad-macos-gotchas`, which is meant to grow).
- New category that doesn't fit → add a new skill folder following the same pattern.

Keep the `description` field one or two sentences of plain English that names every trigger phrase. That's what determines whether Claude reaches for the skill.
