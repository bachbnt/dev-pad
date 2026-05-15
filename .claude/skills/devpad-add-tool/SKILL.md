---
name: devpad-add-tool
description: Use when adding a new tool/tab to the DevPad sidebar (e.g. "thêm tính năng X", "add a YAML formatter", "make a new tab for …"). Step-by-step recipe covering every file that must change: utility, view, Tool enum wiring, localization (EN + VI), DemoMode sample, project.pbxproj registration (4 places per file), and README updates. Use together with devpad-overview and devpad-conventions.
---

# Adding a new sidebar tool to DevPad

The "add tool" task touches the same set of files every time. Follow this checklist in order — skipping a step almost always means missing localization keys, an unregistered file the linker can't find, or a stale README.

## Step 1. Decide the slug

Pick a single lowercase identifier (no spaces, no hyphens) that will become:
- the `Tool.<slug>` enum case
- the `sidebar.<slug>` localization key
- the `<Slug>View.swift` / `<Slug>.swift` filenames (CamelCased)

Examples already in the project: `json`, `xml`, `sql`, `url`, `qr`, `jwt`, `regex`, `hash`, `diff`, `clipboard`, `dropshelf`, `settings`.

## Step 2. Create the engine (if there's non-trivial logic)

`DevPad/Utilities/<Slug>.swift`. Pure Swift, no SwiftUI imports, no `@MainActor`. Defines:
- The data types the view operates on
- An `enum <Slug>Error: LocalizedError` with **English** `errorDescription` strings
- Static methods or an `enum <Slug>Engine` namespace for the operations

Reference: `Hashing.swift`, `RegexEngine.swift`, `JWT.swift`.

If the tool needs no engine (e.g. URL parser delegates to Foundation's `URLComponents`), skip this step.

## Step 3. Create the view

`DevPad/Views/<Slug>FormatterView.swift` or `<Slug>View.swift`. Standard skeleton:

```swift
import SwiftUI
import AppKit

private enum <Slug>Mode: String, CaseIterable, Identifiable {
    case modeA, modeB
    var id: String { rawValue }
}

struct <Slug>View: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var mode: <Slug>Mode = .modeA
    @State private var input: String = ""
    @State private var output: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            modePicker
            inputEditor
            if let errorMessage { errorBanner(errorMessage) }
            outputView
            actionBar
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if DemoMode.isOn, input.isEmpty {
                input = DemoMode.sample<Slug>
                run()
            }
        }
    }

    private var modePicker: some View { /* segmented Picker, frame(maxWidth: 320) */ }
    private var inputEditor: some View { /* TextEditor with placeholder overlay */ }
    private var outputView:  some View { /* table / preview */ }
    private var actionBar:   some View { /* footer HStack with primary button */ }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text("\(settings.t("<slug>.error.prefix")): \(message)").font(.callout).foregroundStyle(.red)
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.red.opacity(0.10)))
    }

    private func run() {
        do {
            output = try <Slug>Engine.compute(input)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    <Slug>View()
        .environmentObject(AppSettings.shared)
        .frame(width: 1000, height: 700)
}
```

See `devpad-conventions` for the exact UI vocabulary (mode picker, action bar, empty state, error banner).

## Step 3. Wire `Tool` enum in `MainWindowView.swift`

Edit `DevPad/MainWindowView.swift` in **three** places:

1. Add to the enum cases (preserve sidebar order — usually after the most related tool):
```swift
private enum Tool: …, Hashable {
    case json, xml, sql, url, qr, jwt, regex, hash, <slug>, diff, clipboard, dropshelf, settings
    …
}
```

2. Add to `titleKey` switch:
```swift
case .<slug>: return "sidebar.<slug>"
```

3. Add to `icon` switch (pick an SF Symbol from SF Symbols.app):
```swift
case .<slug>: return "<sf-symbol-name>"
```

4. Add to the detail body's switch on `selection`:
```swift
case .<slug>:
    <Slug>View()
        .navigationTitle(settings.t("sidebar.<slug>"))
```

## Step 4. Add localization keys

Edit `DevPad/Utilities/Localization.swift`. **Every** key MUST appear in BOTH the `en` and `vi` dictionaries — the audit script (see `devpad-review`) refuses to ship if one is missing.

EN side, inserted in sidebar order:
```swift
"sidebar.<slug>": "Slug Tool Name",
```

EN section for the tool (placeholder, error prefix, button labels, etc.):
```swift
// <Slug>
"<slug>.placeholder":  "Type or paste …",
"<slug>.run":          "Run",
"<slug>.error.prefix": "Invalid <slug>",
"<slug>.empty.title":  "…",
"<slug>.empty.hint":   "…",
```

VI side — mirror every key:
```swift
"sidebar.<slug>": "Tên tiếng Việt",
"<slug>.placeholder":  "Gõ hoặc dán …",
…
```

`settings.t("<slug>.statusFmt", count)` is supported for `%@` / `%d` format args.

## Step 5. Add DemoMode sample

Edit `DevPad/Utilities/DemoMode.swift`. Add a `static let sample<Slug>: String = "…"` constant with realistic content (long enough to be visually interesting in a screenshot). Reference: `sampleJSON`, `sampleRegexPattern`, `sampleHashText`.

For tools with shared singletons (clipboard, drop shelf) seed via `bootstrap()` instead.

## Step 6. Register both new files in `project.pbxproj`

This trips people up the most. Each new `.swift` file must be added in **four** places inside `DevPad.xcodeproj/project.pbxproj`:

1. **`PBXBuildFile` section** — `B0000XX0...A /* <Name>.swift in Sources */ = {…; fileRef = B0000XX0...B; };`
2. **`PBXFileReference` section** — `B0000XX0...B /* <Name>.swift */ = {…; path = <Name>.swift; …};`
3. **The folder's `PBXGroup` children list** — Utilities/ or Views/ depending on file role.
4. **`PBXSourcesBuildPhase.files`** — `B0000XX0...A /* <Name>.swift in Sources */,`

The project uses a `B0000XX0...` ID convention: pick the next sequential hex pair after the highest existing one (currently around `B0000041`). Letter `A` for `PBXBuildFile`, `B` for `PBXFileReference`.

Use this verification grep after editing — every new file should have exactly 4 occurrences:
```bash
grep -c "<Name>.swift" DevPad.xcodeproj/project.pbxproj   # → 4
```

## Step 7. Permissions and entitlements (if applicable)

If the tool uses a privacy-sensitive API:
- Camera → `INFOPLIST_KEY_NSCameraUsageDescription` in pbxproj (both Debug + Release target configs) + `com.apple.security.device.camera` in `DevPad.entitlements`.
- Microphone → `INFOPLIST_KEY_NSMicrophoneUsageDescription` + `com.apple.security.device.audio-input`.
- Files outside picker → not needed (the project already has `ENABLE_USER_SELECTED_FILES = readonly`).
- Network → `com.apple.security.network.client` in entitlements.

## Step 8. Update README

Edit `README.md`:
1. **Tagline** (`A native macOS developer utility — …`) — add a comma-separated phrase for the new tool.
2. **Features** bullet — describe modes, key features, what makes it useful.
3. **Screenshots grid** — add an image cell `<img src="docs/screenshots/<slug>120526.png">`. You can leave the file missing — README falls back gracefully — and capture it later via demo mode.
4. **Sidebar table** in "Main window" section — add a row with the tab description.
5. **Per-tool notes** section — explain non-obvious behaviour (algorithm choices, error handling, security limits).
6. **Project structure tree** — add the new utility + view file.
7. **Implementation notes** — single bullet describing the architecture decision (e.g. "uses NSRegularExpression because …").
8. **Keyboard shortcuts table** — update the `⌘↵` row to mention the new tool's primary action.

## Step 9. Verify

Run brace balance + localization audit (see `devpad-review` skill). Both must pass.

```bash
# brace balance
python3 - <<'PY'
import re, glob
for p in glob.glob('DevPad/**/*.swift', recursive=True):
    s = open(p).read()
    s = re.sub(r'(?s)"""(?:[^\\]|\\.)*?"""', '""', s)
    s = re.sub(r'(?s)#"(?:[^"\\#]|\\.)*"#', '""', s)
    s = re.sub(r'"(?:\\.|[^"\\])*"', '""', s)
    s = re.sub(r'//.*', '', s)
    s = re.sub(r'(?s)/\*.*?\*/', '', s)
    o, c = s.count('{'), s.count('}')
    if o != c: print(p, o, c)
PY
```

Then in Xcode: ⌘B. If it builds clean, you're done.

## Common mistakes — gotchas to check before committing

- Forgot to add the new key to **VI** dictionary → silent fallback to EN, ugly mix
- Registered the file in only 3 of 4 pbxproj places → Xcode shows the file but linker can't find symbols
- Used `Text("Hello")` instead of `Text(settings.t("xxx.hello"))` → hardcoded English
- Used `.foregroundStyle(.accentColor)` instead of `.foregroundStyle(Color.accentColor)` → macOS 13 compile error
- Used `Task { @MainActor in … }` from a background `DispatchQueue.async` closure → deterministic crash on macOS 13 (see `devpad-macos-gotchas`)
- Used `errorDescription` returns a localized string → engines should stay English; let view wrap the prefix
- Forgot to update sidebar table row count in README ("eleven tabs" / "twelve tabs")
- Forgot the screenshots grid (3×N layout, even if image doesn't exist yet)
