#!/usr/bin/env bash
#
# release.sh
# DevPad — cut a GitHub release from the current commit.
#
# Wraps Xcode version bump + build_dmg.sh + git tag + `gh release create`
# into one command. Runs only on demand; no CI involved, no cost.
# Authentication is whatever `gh` already has on the local machine.
#
# Usage:
#   ./release.sh vX.Y.Z [--signed] [--draft] [--prerelease] [--notes "…"] [--yes]
#
# Examples:
#   ./release.sh v1.0.0
#   ./release.sh v1.1.0-beta1 --prerelease
#   ./release.sh v1.0.0 --signed --notes "First public release"
#   ./release.sh v1.2.0 --yes                    # skip the bump confirm prompt
#
# Pre-flight (any failure aborts before building):
#   - version arg is semver `vX.Y.Z[-suffix]`
#   - working tree is clean (no uncommitted / unstaged changes)
#   - on a real branch (not detached HEAD)
#   - tag does not already exist locally or on origin
#   - `gh` is installed and authenticated
#
# Xcode version sync:
#   - MARKETING_VERSION in project.pbxproj is set to the stripped tag
#     (e.g. v1.1.0 → 1.1.0).
#   - CURRENT_PROJECT_VERSION (build number) is incremented by 1.
#   - Script shows the diff and asks for confirm (unless --yes).
#   - The bump becomes its own commit, pushed before tagging, so the tag
#     points at the commit that actually carries the new version.
#
# After publishing, the DMG attached to the release is reachable at the
# stable "latest" URL:
#   https://github.com/bachbnt/dev-pad/releases/latest/download/DevPad.dmg
#
# Copyright © 2026 bachbnt. All rights reserved.
#

set -euo pipefail

cd "$(dirname "$0")"

# --- args --------------------------------------------------------------------

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 vX.Y.Z [--signed] [--draft] [--prerelease] [--notes \"…\"] [--yes]" >&2
    exit 1
fi

VERSION="$1"
shift

SIGNED_FLAG=""
RELEASE_FLAGS=()
NOTES=""
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --signed)      SIGNED_FLAG="--signed"; shift ;;
        --draft)       RELEASE_FLAGS+=("--draft"); shift ;;
        --prerelease)  RELEASE_FLAGS+=("--prerelease"); shift ;;
        --notes)       NOTES="${2:-}"; shift 2 ;;
        --yes|-y)      ASSUME_YES=1; shift ;;
        *) echo "❌  Unknown flag: $1" >&2; exit 1 ;;
    esac
done

# Strip the `v` prefix for Xcode's MARKETING_VERSION (Xcode wants 1.0.0,
# not v1.0.0).
VERSION_NUM="${VERSION#v}"
PBXPROJ="DevPad.xcodeproj/project.pbxproj"

# --- pre-flight --------------------------------------------------------------

echo "🔍  Pre-flight checks…"

# 1. semver shape (vX.Y.Z with optional -suffix like -beta1, -rc.1)
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    echo "❌  Version '$VERSION' is not semver. Expected form: v1.2.3 or v1.2.3-beta1" >&2
    exit 1
fi
echo "    ✓ version $VERSION looks like semver"

# 2. working tree clean. Untracked-but-ignored files are fine; uncommitted
# tracked changes are not. `--porcelain` lists every dirty / untracked entry
# one per line — any output means dirty.
if ! git diff --quiet HEAD -- 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    echo "❌  Working tree has uncommitted changes. Commit or stash before releasing." >&2
    git status --short
    exit 1
fi
echo "    ✓ working tree clean"

# 3. must be on a real branch — releasing from a detached HEAD means the
# bump commit would be orphaned and lost.
BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
if [[ -z "$BRANCH" ]]; then
    echo "❌  HEAD is detached. Checkout a branch before releasing." >&2
    exit 1
fi
echo "    ✓ on branch $BRANCH"

# 4. tag must not already exist (locally or on origin). If it does we'd be
# overwriting somebody's published release — refuse rather than ask.
if git rev-parse "refs/tags/$VERSION" >/dev/null 2>&1; then
    echo "❌  Tag $VERSION already exists locally. Delete it (\`git tag -d $VERSION\`) or pick a new version." >&2
    exit 1
fi
if git ls-remote --tags origin "$VERSION" 2>/dev/null | grep -q "refs/tags/$VERSION"; then
    echo "❌  Tag $VERSION already exists on origin. Pick a new version." >&2
    exit 1
fi
echo "    ✓ tag $VERSION is free"

# 5. gh CLI installed + authenticated
if ! command -v gh >/dev/null 2>&1; then
    echo "❌  \`gh\` CLI not found. Install from https://cli.github.com and re-run." >&2
    exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
    echo "❌  \`gh\` is not authenticated. Run \`gh auth login\` first." >&2
    exit 1
fi
echo "    ✓ gh CLI ready"

echo ""

# --- xcode version bump ------------------------------------------------------

# Read the *first* match for each key. The pbxproj declares them once per
# build configuration (Debug + Release) but Xcode keeps the two in lockstep
# in practice, so reading either one is fine.
CURRENT_MARKETING=$(grep -m1 -E '^[[:space:]]*MARKETING_VERSION = ' "$PBXPROJ" \
    | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/')
CURRENT_BUILD=$(grep -m1 -E '^[[:space:]]*CURRENT_PROJECT_VERSION = ' "$PBXPROJ" \
    | sed -E 's/.*CURRENT_PROJECT_VERSION = ([^;]+);.*/\1/')

if [[ -z "$CURRENT_MARKETING" || -z "$CURRENT_BUILD" ]]; then
    echo "❌  Could not read MARKETING_VERSION / CURRENT_PROJECT_VERSION from $PBXPROJ" >&2
    exit 1
fi

# Build number always advances by 1 per release. The marketing version
# becomes the stripped tag (e.g. v1.1.0 → 1.1.0).
NEW_BUILD=$((CURRENT_BUILD + 1))
NEW_MARKETING="$VERSION_NUM"

echo "📦  Xcode version bump:"
printf "    MARKETING_VERSION       : %s → %s\n" "$CURRENT_MARKETING" "$NEW_MARKETING"
printf "    CURRENT_PROJECT_VERSION : %s → %s\n" "$CURRENT_BUILD" "$NEW_BUILD"
echo ""

if [[ $ASSUME_YES -ne 1 ]]; then
    # Default to "yes" on bare Enter so the common case is one keystroke.
    read -r -p "Apply this bump and commit it to '$BRANCH'? [Y/n] " ans
    case "${ans:-Y}" in
        n|N|no|NO)
            echo "Aborted by user. No changes made."
            exit 1
            ;;
    esac
fi

# Apply. Both MARKETING_VERSION and CURRENT_PROJECT_VERSION appear twice in
# pbxproj (Debug + Release blocks); replace every occurrence so the two
# configs stay in sync.
#
# `sed -i ''` is the BSD/macOS form. Linux sed would want `-i` with no
# empty arg — but this script targets macOS only (xcodebuild already does).
sed -i '' -E "s/(MARKETING_VERSION = )[^;]+;/\\1${NEW_MARKETING};/g" "$PBXPROJ"
sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )[^;]+;/\\1${NEW_BUILD};/g" "$PBXPROJ"

# Sanity-check that sed actually changed something. If the regex missed
# (project layout changed), bail before committing the no-op.
if ! git diff --quiet -- "$PBXPROJ"; then
    git add "$PBXPROJ"
    git commit -m "chore: bump version to $NEW_MARKETING (build $NEW_BUILD)" >/dev/null
    echo "    ✓ committed bump as $(git rev-parse --short HEAD)"
    git push origin "$BRANCH"
    echo "    ✓ pushed $BRANCH to origin"
else
    echo "❌  sed didn't change $PBXPROJ — version pattern may have moved. Bump aborted." >&2
    exit 1
fi

echo ""

# --- build -------------------------------------------------------------------

echo "🏗   Building DMG via build_dmg.sh ${SIGNED_FLAG}…"
if [[ -n "$SIGNED_FLAG" ]]; then
    ./build_dmg.sh "$SIGNED_FLAG"
else
    ./build_dmg.sh
fi

DMG_PATH="$(pwd)/build/DevPad.dmg"
if [[ ! -f "$DMG_PATH" ]]; then
    echo "❌  Expected DMG at $DMG_PATH but it's missing — build_dmg.sh failed silently?" >&2
    exit 1
fi

# --- tag + push --------------------------------------------------------------

echo ""
echo "🏷   Tagging $VERSION on $(git rev-parse --short HEAD)…"
git tag -a "$VERSION" -m "Release $VERSION"

echo "📤  Pushing tag to origin…"
git push origin "$VERSION"

# --- release -----------------------------------------------------------------

echo ""
echo "🚀  Creating GitHub release…"

# If the caller didn't pass --notes, hand the work off to GitHub's
# "Generate release notes" feature, which writes notes from PRs / commits
# since the previous tag. The user can still edit the release after.
NOTES_FLAG=()
if [[ -n "$NOTES" ]]; then
    NOTES_FLAG=(--notes "$NOTES")
else
    NOTES_FLAG=(--generate-notes)
fi

gh release create "$VERSION" "$DMG_PATH" \
    --title "DevPad $VERSION" \
    "${NOTES_FLAG[@]}" \
    ${RELEASE_FLAGS[@]+"${RELEASE_FLAGS[@]}"}

echo ""
echo "🎉  Release $VERSION published."
echo "    DMG: https://github.com/bachbnt/dev-pad/releases/latest/download/DevPad.dmg"
echo "    Page: https://github.com/bachbnt/dev-pad/releases/tag/$VERSION"
