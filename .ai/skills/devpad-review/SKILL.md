---
name: devpad-review
description: Use when reviewing a code change in DevPad before commit / merge — whether you wrote the change yourself or are auditing someone else's. Covers a per-concern checklist (sidebar wiring, localization, pbxproj registration, threading, UI patterns, engine vs. view split, release config preservation) plus ready-to-run bash audit scripts (brace balance, localization mirror, pbxproj sanity, hardcoded-string scan). Pair with devpad-conventions for the "why" behind each check.
---

# DevPad — code review checklist & audit scripts

Use this as a final pass before any commit. Most of these checks take seconds to run.

## Quick audit scripts (paste into shell, project root = `/Users/bachbui/Desktop/source/dev-pad`)

### Brace balance — every Swift file balanced?

```bash
python3 - <<'PY'
import re, glob
bad = []
for p in sorted(glob.glob('DevPad/**/*.swift', recursive=True)):
    s = open(p).read()
    s = re.sub(r'(?s)"""(?:[^\\]|\\.)*?"""', '""', s)
    s = re.sub(r'(?s)#"(?:[^"\\#]|\\.)*"#', '""', s)
    s = re.sub(r'"(?:\\.|[^"\\])*"', '""', s)
    s = re.sub(r'//.*', '', s)
    s = re.sub(r'(?s)/\*.*?\*/', '', s)
    o, c = s.count('{'), s.count('}')
    if o != c: bad.append((p, o, c))
if bad:
    for p, o, c in bad: print(f"UNBALANCED {p}: opens={o} closes={c}")
else:
    print("All Swift files brace-balanced ✓")
PY
```

### Localization audit — EN and VI mirror?

```bash
python3 - <<'PY'
import re, glob
referenced = set()
for p in glob.glob('DevPad/**/*.swift', recursive=True):
    for m in re.finditer(r'\.t\(\s*"([^"]+)"', open(p).read()):
        referenced.add(m.group(1))

loc = open('DevPad/Utilities/Localization.swift').read()
en_match = re.search(r'private static let en:.*?\[(.*?)^\s*\]', loc, re.S|re.M)
vi_match = re.search(r'private static let vi:.*?\[(.*?)^\s*\]', loc, re.S|re.M)
def keys(t): return set(re.findall(r'"([^"]+)":\s*"', t))
en, vi = keys(en_match.group(1)), keys(vi_match.group(1))

print(f"EN keys: {len(en)}  |  VI keys: {len(vi)}  |  Referenced in code: {len(referenced)}")
miss_en, miss_vi = sorted(referenced - en), sorted(referenced - vi)
en_only, vi_only = sorted(en - vi), sorted(vi - en)
print(f"Missing in EN: {miss_en if miss_en else 'none ✓'}")
print(f"Missing in VI: {miss_vi if miss_vi else 'none ✓'}")
print(f"EN-only      : {en_only if en_only else 'none ✓'}")
print(f"VI-only      : {vi_only if vi_only else 'none ✓'}")
PY
```

The keys-only-in-one-language report catches stale entries. The referenced-but-missing report catches typos.

Note: keys accessed dynamically (via `<Type>.labelKey` constants, `FlagOption.titleKey`, enum `.rawValue`-based lookups) won't appear in `referenced` — the audit's blind spot. Spot-check those when adding new dynamic keys.

### pbxproj sanity — every registered Swift file in 4 places?

```bash
python3 - <<'PY'
import re, glob
pbx = open('DevPad.xcodeproj/project.pbxproj').read()
issues = []
for p in glob.glob('DevPad/**/*.swift', recursive=True):
    name = p.split('/')[-1]
    count = pbx.count(name)
    if count != 4:
        issues.append((name, count))
if issues:
    for n, c in issues: print(f"WRONG COUNT {n}: {c} (expect 4: BuildFile + FileReference + group + Sources phase)")
else:
    print("All Swift files registered in 4 places ✓")
PY
```

### Hardcoded strings scan — anything user-facing that bypassed `settings.t(…)`?

```bash
python3 - <<'PY'
import re, glob
patterns = [
    (r'Text\("([^"]+)"\)', 'Text'),
    (r'Label\("([^"]+)"', 'Label'),
    (r'\.help\("([^"]+)"\)', 'help'),
    (r'TextField\("([^"]+)"', 'TextField'),
    (r'SecureField\("([^"]+)"', 'SecureField'),
    (r'Picker\("([^"]+)"', 'Picker'),
]
findings = []
for p in sorted(glob.glob('DevPad/Views/**/*.swift', recursive=True)):
    src = open(p).read()
    src = re.sub(r'(?s)#Preview\s*\{.*?\n\}', '', src)
    src = re.sub(r'(?s)"""(?:[^\\]|\\.)*?"""', '""', src)
    for pat, kind in patterns:
        for m in re.finditer(pat, src):
            v = m.group(1)
            if not v.strip() or len(v) <= 1: continue
            if re.match(r'^[\d\W_]+$', v): continue
            if v in ('', ' ', '/', '•', '—', '$&'): continue
            if r'\(' in v: continue   # string interpolation — dynamic value, ok
            findings.append((p, kind, v))
if findings:
    for p, k, v in findings: print(f"{p}: {k}({v!r})")
else:
    print("No hardcoded user-facing strings ✓")
PY
```

The `r'\('` skip lets through interpolations like `Text("\(count)")` — those are dynamic values, not hardcoded English.

## Per-concern checklist

### Adding a new tool

- [ ] `Tool.<slug>` case added to enum in `MainWindowView.swift`
- [ ] `titleKey` switch and `icon` switch updated
- [ ] `case .<slug>: <Slug>View().navigationTitle(…)` added to detail body switch
- [ ] `sidebar.<slug>` localization key added in **BOTH** EN and VI dictionaries
- [ ] All other `<slug>.*` keys added in BOTH dictionaries
- [ ] `DemoMode.sample<Slug>` added (if the tool has any user input)
- [ ] View file registered in `project.pbxproj` in 4 places (BuildFile, FileReference, group, Sources phase)
- [ ] Utility file (if any) registered the same way
- [ ] README — Features bullet, sidebar table row, Notes section, project tree, implementation notes
- [ ] If screenshot taken: file in `docs/screenshots/<slug><date>.png`, README screenshot grid updated
- [ ] If new privacy-sensitive API: matching `INFOPLIST_KEY_*` in pbxproj + entitlement in `DevPad.entitlements`

### Reviewing UI code

- [ ] Mode picker (if multi-mode) is centered, segmented, max-width 320, no surrounding Spacers
- [ ] Action button is `.borderedProminent`, `⌘↵` shortcut, disabled when input empty
- [ ] Empty state present (SF icon 44pt light + headline + hint)
- [ ] Error banner uses the standard red-triangle + red text + 10% red fill pattern
- [ ] Copy buttons present for any output the user might want to grab
- [ ] All strings go through `settings.t(...)`
- [ ] Drop zones use dashed border + accent on hover + file metadata when populated
- [ ] TextEditor placeholder overlay uses `.padding(.leading, 13)` (matches NSTextView lineFragmentPadding)
- [ ] Output preview is monospace + selectable + scrollable + textBackgroundColor fill
- [ ] Matches the layout / spacing of existing tabs (look at JSON / JWT / Hash for reference)

### Reviewing concurrency

- [ ] `@MainActor` classes hop to main via `DispatchQueue.main.async`, not `Task { @MainActor }` chained off background queues
- [ ] Every closure crossing actor / thread boundaries uses `[weak self]`
- [ ] Mutations crossing actor boundaries hoisted to `let` before the hop (Swift 6 strict concurrency)
- [ ] AVFoundation / ObjC delegates cleared (`setSomethingDelegate(nil, …)`) in `deinit` AND in `stop()` paths before tearing down
- [ ] No "Task pool from inside background DispatchQueue" anti-pattern (see devpad-macos-gotchas #3)

### Reviewing engine (Utilities/) code

- [ ] No SwiftUI imports
- [ ] No `@MainActor` annotations
- [ ] Error enum's `errorDescription` returns **English** strings (engines stay locale-free; view wraps with localized prefix)
- [ ] No third-party Swift package imports — stick to Foundation / CryptoKit / CommonCrypto / Vision / AVFoundation / Security
- [ ] File-streaming for potentially-large inputs (1 MB chunks, `update(data:)` then `finalize()`)
- [ ] Public API documented with `///` comments — what / when to call, return semantics, throwing conditions

### Reviewing build config / pbxproj edits

- [ ] All Release optimization flags still set (`LLVM_LTO`, `SWIFT_OPTIMIZATION_LEVEL = -Osize`, `STRIP_*`, `DEPLOYMENT_POSTPROCESSING`, `ASSETCATALOG_COMPILER_OPTIMIZATION = space`) — see devpad-release
- [ ] DMG packaging uses `-format ULFO`
- [ ] DemoMode `isOn` getter wrapped in `#if DEBUG`
- [ ] `MACOSX_DEPLOYMENT_TARGET = 13.0` unchanged
- [ ] `INFOPLIST_KEY_NSCameraUsageDescription` (and any new `INFOPLIST_KEY_NS*UsageDescription`) present in **both** Debug + Release target configs
- [ ] `DevPad.entitlements` has matching entitlement keys for every privacy API
- [ ] No accidentally-removed build settings (compare against `git diff DevPad.xcodeproj/project.pbxproj`)

### Reviewing localization edits

- [ ] Every new key in EN has a counterpart in VI
- [ ] Every removed key removed from BOTH languages
- [ ] No mojibake / smart-quote substitution — Swift source uses straight quotes
- [ ] Format placeholders (`%@`, `%d`) match between EN and VI for the same key
- [ ] Punctuation conventions match the project's voice (Vietnamese uses lowercase keys-and-spaces for sentence-case labels)

## Common regressions to spot

These are the recurring mistakes — eyeball every diff for them:

1. **Hardcoded string** sneaking past `settings.t(...)`: `Text("Loading…")`. Audit script catches most of these.
2. **VI key forgotten**: PR adds 8 new EN keys but only 7 in VI. Audit script catches.
3. **`Task { @MainActor }` accidentally introduced**: usually copy-pasted from another file that had it before we removed the pattern. Grep for `Task { @MainActor` in any file modifying `DevPad/Utilities/`.
4. **`.foregroundStyle(.accentColor)`**: macOS 13 compile error. Should be `Color.accentColor`.
5. **`pbxproj` file appears 3× instead of 4×**: usually missing from `PBXSourcesBuildPhase.files` — the linker will still compile but won't include the file in the binary. App launches without the new feature.
6. **`AVFoundation` delegate not cleared in `deinit`**: silent EXC_BAD_ACCESS waiting to happen on the next teardown.
7. **`.frame(maxHeight: .infinity)` missing on a column-mode tab**: content collapses vertically, mode picker ends up centered in the screen. Fix is `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)` at the VStack level.
8. **`Color.primary` swapped for `.primary`**: usually fine but in certain contexts (ternary with `Color.accentColor`) the type inference complains.

## When to push back on a "tiny change"

- Removing the centered mode-picker rule "because it's just one tab". → Reject. Consistency across tabs is the point.
- Removing a key from VI "because we'll add it back later". → Reject. Keep mirror invariant.
- "Just use `Task { @MainActor }` here, it'll be fine". → Reject. We've literally crashed on this pattern in production.
- Disabling `STRIP_INSTALLED_PRODUCT` "to debug". → Acceptable temporarily; not in committed code.
- Adding a third-party Swift package "just for X". → Reject. The project's strict no-deps policy is what keeps the binary tiny and the supply chain trivial.
