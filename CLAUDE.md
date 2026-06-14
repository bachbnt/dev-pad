# DevPad Claude instructions

Project-specific skills live in `.ai/skills/` and are the canonical source of guidance for Claude when working in this repository.

## Required routing

1. Read `.ai/skills/devpad-overview/SKILL.md` before making any DevPad change.
2. Read `.ai/skills/devpad-conventions/SKILL.md` when writing or modifying Swift code or user-visible behavior.
3. Read `.ai/skills/devpad-add-tool/SKILL.md` when adding a sidebar tool or tab.
4. Read `.ai/skills/devpad-macos-gotchas/SKILL.md` when touching AVFoundation, AppKit layer hosting, SwiftUI compatibility, concurrency, pasteboards, drag and drop, CommonCrypto, or CryptoKit.
5. Read `.ai/skills/devpad-release/SKILL.md` when changing build settings, entitlements, signing, packaging, versioning, or release behavior.
6. Read `.ai/skills/devpad-review/SKILL.md` before completing a code change, then run the relevant audits documented there.

Load only the task-specific skills needed after the overview. Follow the skills as repository instructions, keep `README.md` synchronized with user-visible changes, and preserve unrelated worktree changes.

Do not duplicate skills under `.claude/`, `.codex/`, or another agent-specific directory. Update `.ai/skills/` as the single shared source.
