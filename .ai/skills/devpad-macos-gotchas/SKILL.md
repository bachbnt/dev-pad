---
name: devpad-macos-gotchas
description: >-
  Use whenever DevPad code does anything with AVFoundation, AppKit layer-hosting,
  SwiftUI on macOS 13, Swift concurrency across actors, NSPasteboard,
  drag-and-drop, CommonCrypto, or CryptoKit. Catalogues the specific gotchas this
  codebase has already encountered, with the symptom, root cause, and current fix.
  Cross-reference it whenever touching the corresponding engine.
---

# DevPad — macOS / SwiftUI gotchas we've already hit

Each gotcha lists: **symptom** → **root cause** → **fix** (with file reference). If you see the symptom, jump straight to the fix.

## 1. AVCaptureMetadataOutput rejects `.qr` on some Macs

**Symptom**: `*** -[AVCaptureMetadataOutput_Tundra setMetadataObjectTypes:] Unsupported type found - use -availableMetadataObjectTypes`. Setting `metadataObjectTypes = [.qr]` even directly outside the config block throws.

**Cause**: Some Mac webcam configurations don't expose `.qr` in `availableMetadataObjectTypes`. Filtering returns empty → no detections.

**Fix**: Use `AVCaptureVideoDataOutput` + Vision's `VNDetectBarcodesRequest` instead. The Vision pipeline doesn't depend on AVCaptureMetadataOutput's symbology list. See `DevPad/Utilities/QRCamera.swift` for the full implementation. Per frame, pull `CVPixelBuffer`, run a Vision request synchronously on the delegate queue, hop to main for `@Published` update.

## 2. AppKit layer-hosting view — `wantsLayer = true` then `layer = …` is wrong

**Symptom**: `AVCaptureVideoPreviewLayer` set as `view.layer` but doesn't render — or worse, crashes with `EXC_BAD_ACCESS` inside CoreAnimation.

**Cause**: Setting `wantsLayer = true` first makes AppKit create its own backing layer; assigning `layer = customLayer` afterwards leaves the auto-created layer in place on some macOS versions.

**Fix**: Override `makeBackingLayer()` to return your custom layer, then set `wantsLayer = true`:
```swift
final class PreviewNSView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true                    // AppKit calls makeBackingLayer() now
    }
    override func makeBackingLayer() -> CALayer {
        previewLayer.videoGravity = .resizeAspectFill
        return previewLayer
    }
    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
```
Reference: `CameraPreviewView` in `QRGeneratorView.swift`.

## 3. `Task { @MainActor }` from a non-main `DispatchQueue` deterministically crashes on macOS 13

**Symptom**: `EXC_BAD_ACCESS (code=1, address=0x19000004190)` at `ldrb [x0, #0x20]` somewhere in the Swift task pool. Happens reliably when you do:
```swift
queue.async { [session] in
    session.startRunning()
    Task { @MainActor [weak self] in
        self?.isRunning = session.isRunning
    }
}
```

**Cause**: Suspected Swift runtime bug interacting with @MainActor isolation on macOS 13 — the Task scheduler trips on the captured non-Sendable state.

**Fix**: Use traditional GCD instead. Same intent, predictable behaviour:
```swift
queue.async { [session] in
    session.startRunning()
    let running = session.isRunning
    DispatchQueue.main.async { [weak self] in
        self?.isRunning = running
    }
}
```
Reference: `QRCamera.swift` — every cross-thread hop uses `DispatchQueue.main.async`, never `Task { @MainActor }`.

## 4. AVFoundation delegate teardown race

**Symptom**: `EXC_BAD_ACCESS` somewhere in `objc_msgSend` after the user leaves the camera tab. The `@StateObject` was just deallocated.

**Cause**: `AVCaptureMetadataOutput`/`AVCaptureVideoDataOutput` hold an unsafe (ObjC) reference to the delegate. While ARC is tearing down `self`, a callback can still be in flight on the delegate queue → dispatch lands on freed memory.

**Fix**: Clear the delegate **before** stopping or before ARC kicks in. `setSampleBufferDelegate(nil, queue: nil)` flushes pending callbacks on the queue:
```swift
deinit {
    videoOutput.setSampleBufferDelegate(nil, queue: nil)
    if session.isRunning { session.stopRunning() }
}
func stop() {
    videoOutput.setSampleBufferDelegate(nil, queue: nil)
    queue.async { session.stopRunning() ; … }
}
func start() {
    if session.inputs.isEmpty {
        try configureSession()      // first time
    } else {
        videoOutput.setSampleBufferDelegate(self, queue: queue)  // restart path: re-attach
    }
    queue.async { session.startRunning() ; … }
}
```
Same pattern as Apple's AVCam sample code.

## 5. SwiftUI `TextEditor` on macOS 13 doesn't paint attributed backgrounds

**Symptom**: You produce an `AttributedString` with `.backgroundColor` runs and bind it to a SwiftUI `Text` / `TextEditor` — the background colour doesn't render.

**Cause**: macOS 13's SwiftUI text stack ignores the `backgroundColor` attribute for inline runs.

**Fix**: Drop down to `NSTextView` via `NSViewRepresentable`. Apply attributes to the `textStorage` directly. Restore the caret across re-renders so the user doesn't lose typing position. Reference: `HighlightedTextView` in `RegexTesterView.swift`.

## 6. `pasteboard.types.contains(.fileURL)` false-positives on text drags

**Symptom**: Drop Shelf pops open when the user is just selecting text in another app.

**Cause**: Some apps (browsers) advertise `.fileURL` as a pasteboard type even when the actual data isn't a real file URL — e.g. a web URL or rich text.

**Fix**: Actually decode the URLs with `.urlReadingFileURLsOnly: true`. Only treat as a file drag if the resulting array is non-empty:
```swift
private func pasteboardFileURLs(_ pb: NSPasteboard) -> [URL] {
    let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    return (pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL]) ?? []
}
```
Reference: `DropShelfMonitor.swift`.

## 7. Drag-OUT from our own shelf trips the auto-close logic

**Symptom**: User drags a file *out of* the Drop Shelf into Finder — shelf closes mid-operation or right after, looking glitchy.

**Cause**: The global drag monitor sees a new drag session with file URLs (the ones we just sent out), assumes a fresh drag-in from another app, snapshots count, and on mouse-up sees the count unchanged → closes the shelf.

**Fix**: Compare drag URLs to the shelf's URL set. If superset, this is a drag-out — skip the entire arming logic:
```swift
let shelfSet = Set(DropShelfManager.shared.urls)
if !shelfSet.isEmpty, dragUrls.allSatisfy({ shelfSet.contains($0) }) {
    return   // drag-out, ignore
}
```
Reference: `DropShelfMonitor.handleDrag` in `DropShelfMonitor.swift`.

## 8. `CC_MD2` / `CC_MD4` deprecation warnings spam the build log

**Symptom**: Build emits 4+ warnings about CC_MD2/CC_MD4 being deprecated. They still link and run, but the noise is unpleasant.

**Cause**: Apple marks these symbols `API_DEPRECATED` since macOS 10.15 — the warning is documentation, not behaviour.

**Fix**: Re-import the symbols via `@_silgen_name` with private aliases that skip the SDK's availability attribute:
```swift
@_silgen_name("CC_MD2")
private static func _CC_MD2(_ data: UnsafeRawPointer?,
                            _ len: CC_LONG,
                            _ md: UnsafeMutablePointer<UInt8>) -> UnsafeMutablePointer<UInt8>?
```
Reference: `Hashing.swift` bottom section. SHA-224 doesn't need this — `CC_SHA224` isn't deprecated.

## 9. `.foregroundStyle(.accentColor)` standalone doesn't compile

**Symptom**: `Type 'ShapeStyle' has no member 'accentColor'`.

**Cause**: macOS 13's type inference can't always promote bare `.accentColor` to the `ShapeStyle` requirement.

**Fix**: Use `Color.accentColor` explicitly:
```swift
.foregroundStyle(Color.accentColor)        // works
.foregroundStyle(isOn ? Color.accentColor : .primary)   // works — context-driven inference
```

## 10. `onChange(of:initial:_:)` is macOS 14+

**Symptom**: New-style `onChange` overload doesn't compile on macOS 13 target.

**Fix**: Stick to the single-closure form `onChange(of: x) { newValue in … }`. The old API is fine.

## 11. SwiftUI `.onDrop` callback races AppKit's mouseUp

**Symptom**: You sample some state right after mouse-up to decide whether the user dropped onto our view, but the `.onDrop` handler hasn't fired yet.

**Cause**: SwiftUI's drop handler runs after AppKit's drop-target dispatch, which itself runs after the global mouse-up event.

**Fix**: Give a 100 ms grace before sampling. `DispatchQueue.main.asyncAfter(deadline: .now() + 0.1)` is the right tool — async without backpressure, no Task pool.
Reference: `DropShelfMonitor.handleMouseUp`.

## 12. macOS sandbox: camera needs entitlement + Info.plist + Privacy & Security toggle

**Symptom**: First call to `AVCaptureDevice.requestAccess(for: .video)` crashes the app (`NSGenericException` mentioning Privacy.framework).

**Cause**: Missing `NSCameraUsageDescription` in Info.plist OR missing `com.apple.security.device.camera` entitlement (or both).

**Fix**:
- pbxproj: `INFOPLIST_KEY_NSCameraUsageDescription = "DevPad uses the camera to scan QR codes pointed at it.";` in **both** Debug and Release target build settings.
- `DevPad/DevPad.entitlements`: add `<key>com.apple.security.device.camera</key><true/>` and also `<key>com.apple.security.app-sandbox</key><true/>` to make the sandbox explicit (build settings auto-merge but explicit is clearer).

Same pattern for any privacy-sensitive capability.

## 13. `AVCaptureMetadataOutput.metadataObjectTypes` quirk — set order matters

**Symptom**: Delegate is wired up but never fires.

**Cause**: `availableMetadataObjectTypes` is empty if accessed inside `beginConfiguration()/commitConfiguration()` block — your filter ends up assigning `[]` and the engine never reports anything.

**Fix**: Set delegate + types **after** `commitConfiguration()`. Note that for QR specifically we now use Vision (gotcha #1) and don't have this problem anyway, but the lesson applies to any AVCaptureOutput.

## 14. `panel.isMovableByWindowBackground = true` steals child mouseDown for drag-out

**Symptom**: Trying to drag files OUT of the floating Drop Shelf moves the panel instead.

**Cause**: When a panel has `isMovableByWindowBackground = true`, AppKit treats any mouseDown on the panel's content as a window-drag handle unless the child opts out.

**Fix**: Inside the drag-source `NSView`, override `mouseDownCanMoveWindow` to return `false`:
```swift
override var mouseDownCanMoveWindow: Bool { false }
```
Reference: `DragSourceHostView` in `MultiFileDragSource.swift`.

## 15. Empty / partial `commitConfiguration` after early throw leaves session in begin state

**Symptom**: Errors thrown inside `beginConfiguration()` leave the AVCaptureSession in a half-configured state — subsequent operations behave weirdly.

**Fix**: Always `commitConfiguration()` before throwing:
```swift
session.beginConfiguration()
guard session.canAddInput(input) else {
    session.commitConfiguration()      // ← cleanup BEFORE throw
    throw CameraError.cannotAddInput
}
session.addInput(input)
…
session.commitConfiguration()
```
Reference: `configureSession()` in `QRCamera.swift`.

## 16. `NSNumber as? Bool` is true for 0 and 1

**Symptom**: JSON Formatter printed `[1, 0]` as `[true, false]`.

**Cause**: Swift bridges any `NSNumber` holding 0 or 1 to `Bool`, so `value as? Bool` can't tell a JSON boolean from a JSON number coming out of `JSONSerialization`.

**Fix**: Test the CoreFoundation type instead: `CFGetTypeID(n) == CFBooleanGetTypeID()`. Applies anywhere you walk a `JSONSerialization` / plist object graph. (`JSONFormatter` itself no longer uses `JSONSerialization` — see #18 — but `JWT.swift` still does.)

## 17. NSPasteboard: secrets, big images, and the main thread

**Symptom**: Passwords copied from a password manager show up in clipboard history; copying a large screenshot stalls the UI.

**Cause**: Apps mark secrets with the `org.nspasteboard.ConcealedType` / `TransientType` / `AutoGeneratedType` pasteboard types (nspasteboard.org) — they only help if the clipboard watcher checks for them. And `readObjects(forClasses: [NSImage.self])` decodes the whole bitmap, then TIFF→PNG re-encoding is CPU-heavy.

**Fix**: Check `ClipboardHistory.shouldSkip(pasteboardTypes:)` before reading any content. Prefer `pasteboard.data(forType: .png)` as-is; for `.tiff`, grab the `Data` on main and convert on a background queue. Reference: `ClipboardManager.checkPasteboard`.

## 18. `JSONSerialization` loses key order, duplicate keys and number text

**Symptom**: Formatting the same JSON twice printed the keys in a different order; `12345678901234567890` or `1.0` came back changed.

**Cause**: `JSONSerialization.jsonObject` builds an unordered `[String: Any]` (Swift's per-process hash seed randomizes iteration order), keeps only the last of duplicate keys, and parses numbers into `NSNumber` / `Double`.

**Fix**: A formatter must not use it. `JSONFormatter` has its own strict parser into an order-preserving tree that keeps number source text verbatim. Use `JSONSerialization` only where you need Foundation types and don't care about order (e.g. reading claims in `JWT.swift`). Tab indentation is done while writing, never by post-replacing spaces in the output, or spaces inside string values get rewritten too.

## 19. The sandbox silently blocks process listing and signalling; only the first sbpl rule counts

**Symptom**: A sandboxed app calling `proc_listpids` / `proc_pidinfo` on other processes gets `0` back with `errno == EPERM` and no entry in the system log; `kill(pid, 0)` on another process fails with `EPERM`. An "empty" result looks exactly like "nothing is listening".

**Cause**: App Sandbox denies `process-info-*` for other processes and `signal` to anything but itself, and denies them without reporting. `com.apple.security.temporary-exception.sbpl` can re-allow them, but only the FIRST S-expression in the string is applied — a second `(allow …)` line is silently dropped. `(allow process-info* (target others))` also does not cover `proc_listpids`; that operation needs a rule without a `(target …)` filter.

**Fix**: One combined rule in `DevPad.entitlements`: `(allow process-info-listpids process-info-pidinfo process-info-pidfdinfo signal)`. In code, never trust an empty scan: `PortScanner.listeningPorts()` throws `.accessDenied` when no process other than our own was readable. To re-verify after any change, compile the engine into a tiny CLI with an embedded Info.plist (`-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist`), `codesign -f -s - --entitlements <file>` it with the real entitlements, start a throwaway `python3 -m http.server`, and check that scan and kill both work. Unit tests can't do this: the test bundle isn't sandboxed.

## 20. A bare `Color` (e.g. `Color.clear`) is greedy in both directions

**Symptom**: A table header row (or any `HStack` row) is suddenly hundreds of points tall and pushes the content below it down or out of view.

**Cause**: `Color.clear.frame(width: 70)` only fixes the width. A `Color` view accepts any height, so a stack row containing it grows to whatever the parent offers.

**Fix**: Give spacer-like colors an explicit height as well (`Color.clear.frame(width: 70, height: 1)`), or use `Spacer().frame(width: 70)`. Reference: the header in `PortKillerView.swift`.

**Checking layout without Screen Recording / Accessibility permission**: render the view offscreen instead of screenshotting it — compile all of `DevPad/` except `DevPadApp.swift` plus a small `main.swift` with `-D DEBUG`, host the view in an `NSHostingView` placed in an `NSWindow`, run the run loop for about a second, then `bitmapImageRepForCachingDisplay` + `cacheDisplay` and write the PNG. Launch it with `--demo-fill` for deterministic data, and render EN/VI, light/dark and a narrow width.

## 21. `URL(string:)` accepts any `scheme:rest`, including `WIFI:…`

**Symptom**: Decoding a Wi-Fi QR (`WIFI:T:WPA;S:Net;P:secret;;`) offered an "Open as link" button that does nothing useful.

**Cause**: `URL(string:)` happily parses `WIFI:T:WPA;…` as a URL with scheme `wifi`, so `URL(string: payload)?.scheme != nil` is true for any `word:…` payload.

**Fix**: Decide the payload kind first (`QRPayload.classify`) and only offer Open for plain text. A menu-style `Picker` inside a `Grid` cell also centres itself in a wide column: give it `.frame(maxWidth: .infinity, alignment: .leading)` so it lines up with the text fields below. Reference: `QRGeneratorView.swift`.

## 22. Offscreen window capture: vibrancy and glass render wrong, and demo runs touch real data

**Symptom**: A window rendered with `cacheDisplay` shows the selected sidebar row as a solid black pill (label and icon lost) and the Liquid Glass sidebar-toggle as an empty circle. `layer.render(in:)` is worse (wrong scale, missing content), `CGWindowListCreateImage` is unavailable in current SDKs, and ScreenCaptureKit may raise a permission prompt.

**Cause**: Vibrant / glass effect views need the window server's backdrop, which an offscreen draw doesn't have.

**Fix**: `DemoMode.captureScreenshotIfRequested` (Debug only) captures twice — once as is, once with another tool selected — and recolours the black pill from the second capture (dark glyphs on a light row → white glyphs on the accent colour), then draws the `sidebar.left` glyph into the glass platter. Measure the pill along its middle line only, or black text in the detail pane stretches it. A Debug build shares the installed app's sandbox container (same bundle id), so a screenshot run would show the real clipboard history and write demo values into real settings: build it with `PRODUCT_BUNDLE_IDENTIFIER=com.bachbnt.DevPad.shots` and run that.
