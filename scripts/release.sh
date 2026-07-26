#!/usr/bin/env bash
# Build, Developer ID sign, notarize, staple and package Dev Island as a
# distributable DMG — entirely on this machine, with no GitHub secrets.
#
# ┌────────────────────────────────────────────────────────────────────────────┐
# │ SPARKLE SIGNING KEY — DO NOT REGENERATE                                    │
# │                                                                            │
# │ Updates are EdDSA-signed with the private key stored in the login keychain │
# │ under account "DevIsland". Its public half is pinned below as              │
# │ EXPECTED_ED_PUBLIC_KEY and embedded in the app as SUPublicEDKey.           │
# │                                                                            │
# │ Regenerating the key, or changing SUPublicEDKey, makes every installed     │
# │ copy reject all future auto-updates — recovery means every user manually   │
# │ re-downloading. This script refuses to run when the keychain and the       │
# │ pinned value disagree, which is the whole point of pinning it.             │
# │                                                                            │
# │ Back the key up once and keep it somewhere safe:                           │
# │     generate_keys -x dev-island-sparkle-key.txt --account DevIsland        │
# │                                                                            │
# │ The account name matters: other apps on this machine keep their keys under │
# │ their own account ("MarkdownViewer", …). Never omit --account, or you hit  │
# │ the shared default and risk clobbering another app's key.                  │
# └────────────────────────────────────────────────────────────────────────────┘
#
# Usage: zsh scripts/release.sh <version>      e.g. zsh scripts/release.sh 1.0.0
#
# One-time prerequisites:
#   - "Developer ID Application: Vincent LAURIAT (KFLACS69T9)" in the login
#     keychain (Xcode → Settings → Accounts → Manage Certificates).
#   - notarytool credentials under the shared keychain profile:
#       xcrun notarytool store-credentials "AppliMacVincentGithub" \
#         --apple-id "<apple-id>" --team-id "KFLACS69T9"
#     One profile serves every macOS project here — the credentials are tied to
#     the Apple ID + team, not to the app.
#   - A Sparkle key:  generate_keys --account DevIsland
#     then paste its public half into EXPECTED_ED_PUBLIC_KEY below.
#
# Overrides:  SIGNING_IDENTITY=… NOTARY_PROFILE=… zsh scripts/release.sh 1.0.0
#
# Outputs release/Dev-Island-<version>.dmg, notarized and stapled. Does NOT
# push anything: it prints the suggested `gh release create` at the end.

set -euo pipefail

VERSION="${1:?Usage: zsh scripts/release.sh <version>   (e.g. zsh scripts/release.sh 1.0.0)}"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-DevIsland}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Vincent LAURIAT (KFLACS69T9)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AppliMacVincentGithub}"

# Public half of the Sparkle key, pinned. Generated 2026-07-26 with
# `generate_keys --account DevIsland`. Never change it: every installed copy
# validates updates against this exact value.
EXPECTED_ED_PUBLIC_KEY="cQjrKru74Ib0Q/tCX7ZXfWApKf5/d7TLbaUTr5kRIoI="

release_dir="$repo_root/release"
sparkle_bin="$repo_root/.build/artifacts/sparkle/Sparkle/bin"

die() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
step() { printf '\033[1m→ %s\033[0m\n' "$*"; }

# --- 1. Preflight -----------------------------------------------------------

[[ "$(uname -s)" == "Darwin" ]] || die "macOS only."

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "Version must be MAJOR.MINOR.PATCH, got '$VERSION'."

if [[ -n "$(git status --porcelain)" ]]; then
    die "Working tree is dirty. Commit or stash before releasing."
fi

if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    die "Tag v$VERSION already exists."
fi

# package-app.sh shells out to python3 (icon + DMG background generation, early) and to
# create-dmg (right at the end, AFTER notarization). A missing create-dmg therefore burns an
# Apple submission before failing, so both are checked here rather than discovered mid-run.
step "Checking the packaging tools"
command -v create-dmg >/dev/null \
    || die "create-dmg is not installed.  brew install create-dmg"

if ! python3 -c "import PIL" >/dev/null 2>&1; then
    if [[ -x "$repo_root/.venv/bin/python" ]] && "$repo_root/.venv/bin/python" -c "import PIL" >/dev/null 2>&1; then
        # package-app.sh calls `python3` by name, so put the venv ahead of it on PATH
        # rather than patching the script and adding another divergence from upstream.
        PATH="$repo_root/.venv/bin:$PATH"
        export PATH
    else
        die "python3 has no Pillow, and .venv does not provide it either.
   python3 -m venv .venv && .venv/bin/pip install Pillow"
    fi
fi

# update-appcast.sh inserts after this exact comment and fails if it is missing — which it does
# at the very end of the run, once the build is already notarized. Check it up front.
step "Checking the appcast insertion marker"
grep -qF '<!-- Items are added by the release workflow. See docs/releasing.md. -->' "$repo_root/appcast.xml" \
    || die "appcast.xml has lost the marker comment scripts/update-appcast.sh inserts after.
   Restore this line inside <channel>:
     <!-- Items are added by the release workflow. See docs/releasing.md. -->"

step "Checking the signing identity"
security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGNING_IDENTITY" \
    || die "Signing identity not found in the keychain: $SIGNING_IDENTITY"

step "Checking the notarization profile"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "Notary profile '$NOTARY_PROFILE' is missing or its credentials are stale.
   Recreate it with:
     xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <apple-id> --team-id KFLACS69T9"

# --- 2. Sparkle key: keychain must match what the app will advertise ---------

step "Checking the Sparkle signing key"
[[ -x "$sparkle_bin/generate_keys" && -x "$sparkle_bin/sign_update" ]] \
    || die "Sparkle tools missing. Run 'swift build' once to fetch them."

if [[ -z "$EXPECTED_ED_PUBLIC_KEY" ]]; then
    die "EXPECTED_ED_PUBLIC_KEY is empty in $0.
   Dev Island has no Sparkle key yet. Create one — it will not touch the keys
   other apps keep under their own account:
     $sparkle_bin/generate_keys --account $SPARKLE_ACCOUNT
   Then paste the printed public key into EXPECTED_ED_PUBLIC_KEY and back the
   private half up:
     $sparkle_bin/generate_keys -x dev-island-sparkle-key.txt --account $SPARKLE_ACCOUNT"
fi

keychain_key="$("$sparkle_bin/generate_keys" -p --account "$SPARKLE_ACCOUNT" 2>/dev/null || true)"
[[ -n "$keychain_key" ]] \
    || die "No Sparkle key under account '$SPARKLE_ACCOUNT' in the login keychain."

if [[ "$keychain_key" != "$EXPECTED_ED_PUBLIC_KEY" ]]; then
    die "Sparkle key mismatch — refusing to build an update nobody can install.
   keychain: $keychain_key
   pinned:   $EXPECTED_ED_PUBLIC_KEY
   Either the key was regenerated (restore the backup) or the pin is stale."
fi

# --- 3. Build, sign, notarize, package --------------------------------------

build_number="$(git rev-list --count HEAD)"

step "Building and packaging $VERSION (build $build_number)"
DEV_ISLAND_VERSION="$VERSION" \
DEV_ISLAND_BUILD_NUMBER="$build_number" \
DEV_ISLAND_SIGN_IDENTITY="$SIGNING_IDENTITY" \
DEV_ISLAND_NOTARY_PROFILE="$NOTARY_PROFILE" \
DEV_ISLAND_EDDSA_PUBLIC_KEY="$EXPECTED_ED_PUBLIC_KEY" \
DEV_ISLAND_UNIVERSAL="true" \
    zsh "$repo_root/scripts/package-app.sh"

zip_path="$repo_root/output/package/Dev Island.zip"
dmg_src="$repo_root/output/package/Dev Island.dmg"
[[ -f "$zip_path" && -f "$dmg_src" ]] || die "Packaging did not produce the expected artifacts."

# --- 4. Independent verification (never trust the packaging log alone) ------

step "Verifying signature and notarization"
spctl -a -t exec -vv "$repo_root/output/package/Dev Island.app" 2>&1 | grep -q "source=Notarized Developer ID" \
    || die "Gatekeeper does not see a notarized Developer ID build."
xcrun stapler validate "$dmg_src" >/dev/null 2>&1 \
    || die "The DMG has no stapled notarization ticket."

# --- 5. Sign the update for Sparkle and record it in the appcast ------------

step "Signing the update with the Sparkle key"
sign_output="$("$sparkle_bin/sign_update" --account "$SPARKLE_ACCOUNT" "$zip_path")"
ed_signature="$(printf '%s' "$sign_output" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
length="$(printf '%s' "$sign_output" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
[[ -n "$ed_signature" && -n "$length" ]] || die "Could not parse sign_update output: $sign_output"

step "Recording the release in appcast.xml"
zsh "$repo_root/scripts/update-appcast.sh" "$VERSION" "$build_number" "$ed_signature" "$length"

# --- 6. Stage the artifacts -------------------------------------------------

mkdir -p "$release_dir"
dmg_path="$release_dir/Dev-Island-$VERSION.dmg"

# Clear the previous run's artifacts first. Dev.Island.zip has a fixed name shared by every
# version, so if a copy failed here the stale zip from an earlier release would sit next to a
# freshly written appcast entry describing different bytes — and get published.
rm -f "$dmg_path" "$release_dir/Dev.Island.zip"

cp "$dmg_src" "$dmg_path"
cp "$zip_path" "$release_dir/Dev.Island.zip"   # name must match the appcast enclosure URL

notes="$release_dir/release-notes-$VERSION.md"
[[ -f "$notes" ]] || cat > "$notes" <<EOF
# Dev Island v$VERSION

<!-- Bilingual release notes: English + 简体中文. See .github/RELEASE_TEMPLATE.md -->
EOF

# --- 7. Hand over ------------------------------------------------------------

cat <<EOF

$(printf '\033[32m✓ Release %s built, notarized and stapled\033[0m' "$VERSION")

  $dmg_path
  $release_dir/Dev.Island.zip
  $notes  ← write the notes before publishing

Nothing has been pushed. To publish:

  git add appcast.xml && git commit -m "chore: appcast for v$VERSION"
  git tag v$VERSION && git push origin main v$VERSION
  gh release create v$VERSION \\
    "$dmg_path" "$release_dir/Dev.Island.zip" \\
    --title "Dev Island v$VERSION — <short English title>" \\
    --notes-file "$notes"

The zip asset must keep the name Dev.Island.zip — appcast.xml points at it.
EOF
