---
name: devpad-release
description: Use when modifying DevPad's release build settings, packaging script (`build_dmg.sh`), entitlements (`DevPad.entitlements`), or anything that affects shipped binary size / signing / launch behaviour. Catalogues the Release configuration tuning currently in `project.pbxproj`, the DMG packaging flags, the DemoMode `#if DEBUG` gating, and the conventions around ad-hoc vs. signed builds.
---

# DevPad — release build & packaging

The Release configuration is tuned aggressively for small binary size. This skill documents what's set and why — so you don't lose those tweaks when editing the project file.

## Release-config build settings (project-level, in `DevPad.xcodeproj/project.pbxproj`)

These all live in the project-wide Release `XCBuildConfiguration`. **Don't drop any of them** unless you're explicitly tuning for speed instead of size.

| Setting | Value | Why |
|---|---|---|
| `LLVM_LTO` | `YES` | Whole-binary link-time optimization. Best inlining across modules. Slow link, smallest binary. |
| `SWIFT_OPTIMIZATION_LEVEL` | `-Osize` | Swift compiler favours size over speed. ~5-15% smaller than `-O` with ~5% runtime cost — fine for a utility app. |
| `SWIFT_COMPILATION_MODE` | `wholemodule` | Cross-file optimization within each module. |
| `DEAD_CODE_STRIPPING` | `YES` | Linker drops unused symbols. Pairs with `#if DEBUG`-gated demo path. |
| `STRIP_INSTALLED_PRODUCT` | `YES` | Strip debug symbols from the installed binary. |
| `STRIP_SWIFT_SYMBOLS` | `YES` | Strip Swift mangled symbols too (most of the binary on a SwiftUI app). |
| `STRIP_STYLE` | `all` | Strip everything not absolutely needed for runtime. |
| `DEPLOYMENT_POSTPROCESSING` | `YES` | Enables the post-build processing that actually runs the strip. |
| `ASSETCATALOG_COMPILER_OPTIMIZATION` | `space` | Asset compress favours small `.car` files. |
| `DEBUG_INFORMATION_FORMAT` | `dwarf-with-dsym` | dSYM is generated separately (kept for crash symbolication) but not embedded in the app. |
| `ENABLE_NS_ASSERTIONS` | `NO` | Strip `NSAssert` runtime checks. |

Debug config is unchanged — dev cycle in Xcode stays fast. The above only kick in on Release.

## Target-level build settings (the DevPad app target)

In both Debug + Release `XCBuildConfiguration` of the `DevPad` target:

- `ENABLE_APP_SANDBOX = YES` — sandbox is mandatory for Mac App Store, and we want it for safety.
- `ENABLE_HARDENED_RUNTIME = YES` — required for notarization (when you eventually sign).
- `ENABLE_USER_SELECTED_FILES = readonly` — auto-adds the user-selected-files entitlement; lets `NSOpenPanel` work.
- `INFOPLIST_KEY_NSCameraUsageDescription = "DevPad uses the camera to scan QR codes pointed at it."` — required for camera. Add a matching `INFOPLIST_KEY_*` for any new privacy-sensitive API.
- `INFOPLIST_KEY_NSHumanReadableCopyright = "Copyright © 2026 bachbnt. All rights reserved.";`
- `CURRENT_PROJECT_VERSION = 2` (build number) — bump on each release.
- `MARKETING_VERSION = 1.0.0` (user-facing version) — bump on each release.

## Entitlements (`DevPad/DevPad.entitlements`)

```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.device.camera</key><true/>
```

Both are explicit even though `ENABLE_APP_SANDBOX = YES` would auto-add the sandbox one — explicit is clearer to future maintainers. Add new entitlement keys here when a new tool needs a privacy-sensitive capability.

## DMG packaging (`build_dmg.sh`)

The script does the full Release build via `xcodebuild`, stages the `.app` plus an `/Applications` symlink, and packages with `hdiutil`.

Key flag:
```bash
hdiutil create … -format ULFO …
```

ULFO = lzfse-compressed read-only DMG. ~10-20% smaller than the legacy UDZO (zlib) format. Requires macOS 10.11+ to mount — we ship 13+ so this is fine. Don't downgrade back to UDZO without a reason.

The script defaults to ad-hoc signing (`CODE_SIGN_IDENTITY="-"`) — produces an unsigned, notarized-no app. First launch hits Gatekeeper; user has to right-click → Open. For a proper signed build pass `--signed` and the script will use whatever signing identity is configured in Xcode.

## DemoMode gating

`Utilities/DemoMode.swift` uses `#if DEBUG` so `isOn` returns constant `false` in Release:
```swift
static var isOn: Bool {
#if DEBUG
    if ProcessInfo.processInfo.arguments.contains(launchArgument) { return true }
    if ProcessInfo.processInfo.environment[environmentKey] != nil { return true }
#endif
    return false
}
```

Result: every `if DemoMode.isOn { … }` branch in view `.onAppear`s is dead code at compile time → LTO + dead-code-stripping removes the entire seeding pipeline from the Release binary. Sample string literals (`sampleJSON`, `sampleHashText`, …) may still ship as data symbols even if unreferenced — that's a few KB at most, acceptable.

Don't wrap individual view files with `#if DEBUG` — only the entry point (`isOn`) needs gating. View code reading `DemoMode.sampleX` compiles cleanly in Release; the dead `if isOn` branch never reaches it.

## Versioning a release

1. Bump `CURRENT_PROJECT_VERSION` (build number) and `MARKETING_VERSION` (semver) in the target's build settings — both Debug + Release.
2. Make sure `INFOPLIST_KEY_NSHumanReadableCopyright` is current.
3. Run `./build_dmg.sh` (or `./build_dmg.sh --signed`).
4. Verify `build/DevPad.dmg` mounts, the app launches, first-launch Gatekeeper warning appears (if ad-hoc), camera permission prompt works.
5. (Optional) If signed: `xcrun notarytool submit build/DevPad.dmg --wait` for notarization.

## Checking the result

```bash
# Binary size
du -h build/DerivedData/Build/Products/Release/DevPad.app/Contents/MacOS/DevPad

# DMG size
du -h build/DevPad.dmg

# Verify no debug symbols leaked
nm build/DerivedData/Build/Products/Release/DevPad.app/Contents/MacOS/DevPad | wc -l    # should be small

# Verify entitlements applied
codesign -d --entitlements - build/DerivedData/Build/Products/Release/DevPad.app
```

## What NOT to do in Release tuning

- Don't disable `ENABLE_APP_SANDBOX` to "make things work". Sandboxes are why DevPad doesn't need user trust for sensitive permissions.
- Don't disable `STRIP_*` — symbol stripping is roughly 30% of the size win.
- Don't enable `SWIFT_OPTIMIZATION_LEVEL = -Owholemodule` (a fictional value); the correct one is `-Osize` here.
- Don't ship with `DEBUG_INFORMATION_FORMAT = dwarf` only — keep `dwarf-with-dsym` so crashes can be symbolicated later. The dSYM lives next to the binary in `DerivedData`, don't bundle it into the `.app`.
- Don't ship `DemoMode.swift` without the `#if DEBUG` gate.
