---
name: devpad-conventions
description: Use when writing or modifying any Swift file in the DevPad codebase. Covers the UI vocabulary every tab shares (mode picker, action bar, empty state, error banner, drop zone, output preview), the localization rules (EN+VI mirror, English engine errors, `settings.t(...)` everywhere), Swift code style (`@MainActor` singletons, `@StateObject` ownership, comment style), and the threading rules (`DispatchQueue.main.async` not `Task { @MainActor }`, `[weak self]` always when crossing actor boundaries). Reach for this alongside devpad-add-tool when implementing new UI, and alongside devpad-review when checking existing code.
---

# DevPad code & UI conventions

These are non-negotiable across all tabs. If you find code that breaks them, fix the code — don't extend the inconsistency.

## UI vocabulary

### Mode picker (multi-mode tools)

Centered segmented control at the top. **Just** the picker, no Spacers, no buttons next to it (those go in the pattern bar or action bar instead):

```swift
private var modePicker: some View {
    Picker("", selection: $mode) {
        Text(settings.t("xxx.mode.a")).tag(Mode.a)
        Text(settings.t("xxx.mode.b")).tag(Mode.b)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .frame(maxWidth: 320)
}
```

The default VStack alignment is centred, which is what we want. **Never** wrap the picker in `HStack { Picker(); Spacer(); button }` — that left-aligns it and breaks consistency with the other tabs. Reference: JWTInspectorView, RegexTesterView, HashGeneratorView, QRGeneratorView.

### Action bar (primary action)

Footer HStack with a `Spacer` and the primary button on the right. Always `.borderedProminent`, always `⌘↵`, always `.disabled` when input is empty:

```swift
private var actionBar: some View {
    HStack {
        Spacer()
        Button {
            run()
        } label: {
            Label(settings.t("xxx.run"), systemImage: "wand.and.stars")
                .frame(minWidth: 120)
        }
        .keyboardShortcut(.return, modifiers: [.command])
        .buttonStyle(.borderedProminent)
        .disabled(input.isEmpty)
    }
}
```

For multi-mode tools the label can be dynamic (`mode == .a ? "Match" : "Apply"` style) — see RegexTesterView. The shortcut **must** stay `⌘↵` across all tabs.

### Empty state

When there's no input + no result, show an empty-state placeholder. Big light-weight SF Symbol + headline + hint:

```swift
private var placeholder: some View {
    VStack(spacing: 12) {
        Image(systemName: "asterisk")
            .font(.system(size: 44, weight: .light))
            .foregroundStyle(.secondary)
        Text(settings.t("xxx.empty.title")).font(.headline)
        Text(settings.t("xxx.empty.hint"))
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

### Error banner

Red triangle + red `Text` + red 10% opacity fill. Same shape across every tab:

```swift
private func errorBanner(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        Text("\(settings.t("xxx.error.prefix")): \(message)")
            .font(.callout)
            .foregroundStyle(.red)
        Spacer()
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.red.opacity(0.10)))
}
```

### Input editor (TextEditor with placeholder)

SwiftUI `TextEditor` has no built-in placeholder, so overlay one when empty. The exact padding values are tuned to match the editor's internal line-fragment padding on macOS 13:

```swift
ZStack(alignment: .topLeading) {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color.secondary.opacity(0.25))
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    TextEditor(text: $input)
        .font(.system(.body, design: .monospaced))
        .scrollContentBackground(.hidden)
        .padding(8)
    if input.isEmpty {
        Text(settings.t("xxx.placeholder"))
            .foregroundStyle(.tertiary)
            .font(.system(.body, design: .monospaced))
            .padding(.leading, 13)   // ← matches NSTextView's lineFragmentPadding
            .padding(.top, 8)
            .allowsHitTesting(false)
    }
}
```

### Drop zone

Dashed border, accent on hover, file metadata when populated. Reference: `dropZone` in QRGeneratorView, `dropZone` in HashGeneratorView.

```swift
.background(
    RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
)
.overlay(
    RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                      style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6]))
)
.onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in … }
```

### Output preview

Monospace, text-selectable, rounded `textBackgroundColor` fill, scrollable when long:

```swift
ScrollView {
    Text(output)
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(10)
}
.background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
.overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.secondary.opacity(0.25)))
.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
```

### Copy buttons

Per-row copy: `.borderless`, secondary color, `Image(systemName: "doc.on.doc")` with `.help(settings.t("common.copy"))`. Top-level "Copy all" or "Copy result" buttons: regular `.bordered` style with a `Label`.

## Code style

### File header

```swift
//
//  <FileName>.swift
//  DevPad
//
//  Brief one-paragraph description of what this file does. Mention
//  non-obvious algorithmic or framework choices.
//
```

### MARK separators

Use `// MARK: - Section name` to chunk long files into logical sections (Init, Public, Internal, Helpers, Delegate methods, etc.).

### Singletons & state

- **Singletons**: `@MainActor final class Foo: ObservableObject { static let shared = Foo(); private init() {…} }`. Never instantiate elsewhere.
- **View-local state**: `@State private var x: T`.
- **View-owned ObservableObject**: `@StateObject private var camera = QRCamera()` — created once per view lifetime.
- **App-wide ObservableObject**: `@EnvironmentObject private var settings: AppSettings` — injected via `.environmentObject(...)` at scene level.
- **Published mutations**: `@Published var x: T` for SwiftUI observation, `private(set)` if external writers shouldn't touch it.

### Comments — WHY not WHAT

Code shows what. Use comments for the *why*, especially when something looks weird:

```swift
// Critical: clear the metadata delegate BEFORE anything else. AVFoundation
// holds an unsafe ObjC-style reference to the delegate; if a callback is in
// flight on `queue` while ARC finishes us off, the dispatch lands on freed
// memory and the app crashes with EXC_BAD_ACCESS.
videoOutput.setSampleBufferDelegate(nil, queue: nil)
```

The codebase already has many examples — match that voice (terse, explanatory, occasionally wry).

## Localization rules

### Source of truth

`DevPad/Utilities/Localization.swift` is the only place strings live. Two dicts:
```swift
private static let en: [String: String] = [ "key": "English value", … ]
private static let vi: [String: String] = [ "key": "Vietnamese value", … ]
```

### The mirror rule

Every key in `en` MUST appear in `vi` and vice versa. The audit script in `devpad-review` enforces this.

### Lookup

Always through `AppSettings`:
```swift
@EnvironmentObject private var settings: AppSettings
…
Text(settings.t("xxx.title"))
Text(settings.t("xxx.statusFmt", count))   // %@ / %d format args supported
```

Never call `Localization.string(for:language:)` directly from a view — always go through `settings.t(...)` so the view re-renders when language changes.

### Engine errors

`Utilities/*Error: LocalizedError` enums return **English** in `errorDescription`. The view wraps with a localized prefix:

```swift
// Engine (Utilities/Hashing.swift)
case .invalidPattern(let msg): return msg   // English from NSRegularExpression

// View (Views/RegexTesterView.swift)
errorMessage = error.localizedDescription
…
Text("\(settings.t("regex.error.prefix")): \(message)")   // ↑ this gets localized
```

This is deliberate: engine errors should be precise / greppable / machine-readable. UI chrome around them is localized.

### Format strings

For pluralisation / interpolation:
```swift
"clipboard.itemCount":     "%d items",        // EN
"clipboard.itemCount":     "%d mục",          // VI
…
Text(settings.t("clipboard.itemCount", manager.items.count))
```

Use `%@` for strings, `%d` for ints. The `t(_:_)` variadic overload forwards to `String(format:arguments:)`.

## Threading & concurrency

### Hopping to main from a non-main queue

Use **`DispatchQueue.main.async`**, not `Task { @MainActor }`. The Task pool variant deterministically crashes on some macOS 13 runtimes when chained off a background `DispatchQueue.async`. We've already paid this lesson in QRCamera.swift.

```swift
queue.async { [session] in
    session.startRunning()
    let running = session.isRunning              // capture as immutable
    DispatchQueue.main.async { [weak self] in
        self?.isRunning = running
    }
}
```

### Capturing across actor boundaries

Swift 6 strict concurrency forbids capturing `var` state across actors. Hoist to `let` before crossing:

```swift
Task.detached {
    var out: [HashAlgorithm: Data] = [:]
    for algo in HashAlgorithm.allCases {
        out[algo] = try Hashing.hash(input, algorithm: algo)
    }
    let final = out                              // freeze
    await MainActor.run {
        self.digests = final                     // safe
    }
}
```

### Weak self everywhere there's an outliving callback

`@MainActor` classes don't auto-protect against use-after-free in AVFoundation / NSEvent / Timer callbacks. Always:

```swift
DispatchQueue.main.async { [weak self] in
    guard let self else { return }
    …
}
```

Especially in delegate methods that AVFoundation dispatches to via raw ObjC pointers (`AVCaptureMetadataOutputObjectsDelegate`, `AVCaptureVideoDataOutputSampleBufferDelegate`). See `devpad-macos-gotchas` for the dangling-delegate teardown recipe.

## File / type naming

- View files: `<Slug><Role>View.swift` (e.g. `JSONFormatterView`, `JWTInspectorView`, `HashGeneratorView`).
- Engine files: `<Slug>.swift` for namespaces / types (`JWT.swift`, `Hashing.swift`), `<Slug>Engine.swift` if it adds clarity (`RegexEngine.swift`, `DiffEngine.swift`).
- Manager files: `<Slug>Manager.swift` (`ClipboardManager`, `DropShelfManager`).
- Tool slugs are lowercase: `json`, `xml`, `qr`, `jwt`, `hmac`. CamelCased only in Swift identifiers.

## What NOT to do

- No third-party Swift packages. Stick to Foundation / SwiftUI / AppKit / CryptoKit / CommonCrypto / Vision / AVFoundation / Security framework.
- No `Localizable.strings` / `.xcstrings`. Strings live in `Localization.swift` so language switches at runtime without restart.
- No global functions for UI strings. Always through `settings.t(...)`.
- No `print(…)` left in committed code. Use `os.Logger` if you really need logging.
- No `force-unwrap` (`!`) unless you can prove unwrap will never fail. Prefer `guard let` with a sensible fallback / `return`.
- No "TODO:" comments without a tracked task. They rot.
