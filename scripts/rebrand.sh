#!/usr/bin/env bash
# Rebrand the tree from upstream's "Open Island" identity to this fork's "Dev Island".
#
# This script is IDEMPOTENT and is the single source of truth for the rebrand. It exists
# because this fork keeps syncing from upstream: the rebrand is maintained as one isolated
# commit at the tip of `main`, re-generated after each upstream rebase rather than merged.
#
# Sync procedure:
#   git fetch upstream
#   git rebase --onto upstream/main <rebrand-commit>^ main   # drop the old rebrand commit
#   bash scripts/rebrand.sh
#   git commit -am "chore: rebrand OpenIsland -> DevIsland"
#
# Usage: bash scripts/rebrand.sh [--check]
#   --check  report what would change and exit non-zero if anything would, without writing.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

check_only=0
[ "${1:-}" = "--check" ] && check_only=1

# Files this script must never touch.
#
# - itself and docs/fork-sync.md: they *document* the substitution rules, so rewriting them
#   would collapse the rules into no-ops and silently break idempotence.
# - the READMEs: a fork's README is hand-written, not upstream's with the names swapped —
#   it has to keep pointing at upstream for attribution and sync instructions.
# - appcast.xml: reset to an empty feed rather than rebranded; its entries carry upstream's
#   DMG URLs and upstream's EdDSA signatures, which are meaningless here.
# - the local doc journals, which are gitignored working files.
is_excluded() {
    case "$1" in
        scripts/rebrand.sh|docs/fork-sync.md|README.md|README.zh-CN.md|appcast.xml) return 0 ;;
        PLAN.md) return 0 ;;
        CHANGES.md|TODOS.md|COMMANDS.md|MEMORY.md) return 0 ;;
        *) return 1 ;;
    esac
}

# Substitution rules, most-specific first. Order matters: a later rule must never be able to
# re-match text an earlier rule produced, and an earlier rule must not shadow a later one.
#
# Not matched on purpose: `OpenCode`, `com.openai.*`, and `VIBE_ISLAND_SOCKET_PATH` (a legacy
# compatibility env var inherited from upstream).
sed_script='
s|_openIslandOriginalStatusLine|@@KEEP_STATUSLINE_LITERAL@@|g
s|openIslandOriginalStatusLineKey|@@KEEP_STATUSLINE_SYMBOL@@|g
s|Octane0411/open-vibe-island|vincentlauriat/dev-island|g
s|open-vibe-island|dev-island|g
s|OPEN_ISLAND|DEV_ISLAND|g
s|OPEN ISLAND|DEV ISLAND|g
s|OpenIsland|DevIsland|g
s|openIsland|devIsland|g
s|Open Island|Dev Island|g
s|Open\\ Island|Dev\\ Island|g
s|Open\.Island|Dev.Island|g
s|open\.island|dev.island|g
s|openisland|devisland|g
s|open-island|dev-island|g
s|@@KEEP_STATUSLINE_LITERAL@@|_openIslandOriginalStatusLine|g
s|@@KEEP_STATUSLINE_SYMBOL@@|openIslandOriginalStatusLineKey|g
'

# The two sentinel round-trips are a deliberate carve-out, not an oversight.
#
# `_openIslandOriginalStatusLine` is the key this app writes into the user's
# ~/.claude/settings.json to stash their original statusLine, and reads back on uninstall to
# restore it. That is an on-disk contract with every existing install, not an internal name:
# renaming it would make uninstall() miss the key on any machine set up with v1.0.0 or v1.1.0,
# fall through to the branch that deletes "statusLine" outright, and silently destroy the
# user's own configuration.
#
# Renaming it needs a migration (read both keys), not a substitution. Until someone writes
# that, the literal and its Swift symbol are protected here so the rules can cover `openIsland`
# everywhere else. A whole-file exclusion would have been blunter — it would also hide any
# genuine branding leak that lands in that file later.

# The two escaped spellings above are easy to miss and both are load-bearing:
#   `Open\ Island`  — shell-escaped paths, e.g. ~/Applications/Open\ Island\ Dev.app
#   `Open.Island`   — GitHub release asset names (spaces become dots), and `open.island` as a
#                     grep pattern where the dot is a wildcard. scripts/update-appcast.sh builds
#                     a download URL from this, so missing it yields a feed pointing at a file
#                     that does not exist.

# There is deliberately no second list of patterns here.
#
# Pass 2 used to pre-filter files with a `branding_regex` that restated the rules above. Keeping
# two lists in step is exactly the failure this fork already shipped: `OPEN ISLAND` (uppercase,
# space) was missing from *both* at once, so `--check` reported clean while the DMG background
# carried upstream's name into a published release. `openIsland` was missing the same way.
#
# The check now asks the only question that matters — "would the substitution change this
# file?" — by running the substitution and comparing. It cannot drift from the rules, because
# it *is* the rules.
would_rewrite() {
    ! sed "$sed_script" "$1" 2>/dev/null | cmp -s - "$1"
}

rename_path() {
    printf '%s' "$1" | sed -e 's|OpenIsland|DevIsland|g' -e 's|open-island|dev-island|g'
}

# --- Pass 1: paths -----------------------------------------------------------------------
# Renamed file by file rather than directory by directory, so nested renames such as
# ios/OpenIslandMobile.xcodeproj/project.pbxproj resolve in a single sweep.

renamed=0
while IFS= read -r -d '' path; do
    is_excluded "$path" && continue
    new_path="$(rename_path "$path")"
    [ "$new_path" = "$path" ] && continue

    if [ "$check_only" -eq 1 ]; then
        echo "would rename: $path -> $new_path"
    else
        mkdir -p "$(dirname "$new_path")"
        git mv "$path" "$new_path"
    fi
    renamed=$((renamed + 1))
done < <(git ls-files -z)

# Directories left empty by the file-by-file moves are invisible to git but confuse humans.
if [ "$check_only" -eq 0 ]; then
    find Sources Tests ios Assets config -type d -empty -delete 2>/dev/null || true
fi

# --- Pass 2: contents --------------------------------------------------------------------

rewritten=0
while IFS= read -r -d '' path; do
    is_excluded "$path" && continue
    # `grep -I` reports no match for a binary file, so an empty pattern matches every text
    # file and nothing else. Binaries must never reach sed -i.
    grep -Iq '' "$path" 2>/dev/null || continue
    would_rewrite "$path" || continue

    if [ "$check_only" -eq 1 ]; then
        echo "would rewrite: $path"
    else
        sed -i '' "$sed_script" "$path"
    fi
    rewritten=$((rewritten + 1))
done < <(git ls-files -z)

if [ "$check_only" -eq 1 ]; then
    if [ $((renamed + rewritten)) -gt 0 ]; then
        echo "rebrand: $renamed path(s) and $rewritten file(s) still carry upstream branding" >&2
        exit 1
    fi
    echo "rebrand: clean"
    exit 0
fi

echo "rebrand: renamed $renamed path(s), rewrote $rewritten file(s)"
