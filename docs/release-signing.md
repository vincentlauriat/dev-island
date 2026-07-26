# Release Signing & Notarization

Dev Island is signed and notarized **on the maintainer's machine**, by
`scripts/release.sh`. There are no GitHub Actions secrets and no CI release
workflow — CI only builds and tests.

Everything a release needs lives in the login keychain. This is a deliberate
choice over the CI model inherited from upstream, where a runner needed the
Developer ID certificate, its password, an app-specific password and the Sparkle
private key uploaded as repository secrets — each one a second copy of something
that already exists in exactly one place.

## One-time setup

### 1. Developer ID certificate

Xcode → Settings → Accounts → Manage Certificates → **Developer ID Application**.
Verify:

```bash
security find-identity -v -p codesigning
# 1) … "Developer ID Application: Vincent LAURIAT (KFLACS69T9)"
```

### 2. Notarization credentials

One profile is shared by every macOS project on this machine — notarytool
credentials are tied to the Apple ID and team, not to the app, so a per-project
profile buys nothing.

```bash
xcrun notarytool store-credentials "AppliMacVincentGithub" \
  --apple-id "<apple-id>" --team-id "KFLACS69T9"
```

It prompts for an **app-specific password** (generated at appleid.apple.com),
not the account password. Verify:

```bash
xcrun notarytool history --keychain-profile "AppliMacVincentGithub"
```

### 3. Sparkle signing key

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account DevIsland
```

**`--account DevIsland` is not optional.** Without it Sparkle falls back to a
single global account shared by every app on the machine, so generating a key
for Dev Island could overwrite another project's key and break auto-update for
everyone already running it. Each app keeps its own account.

`-p` reads an existing key without writing anything:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -p --account DevIsland
```

Then:

1. Paste the printed public key into `EXPECTED_ED_PUBLIC_KEY` in
   `scripts/release.sh`. It is embedded in the app as `SUPublicEDKey`, and the
   script refuses to build when the keychain and the pin disagree.
2. Back the private half up somewhere safe:
   ```bash
   .build/artifacts/sparkle/Sparkle/bin/generate_keys -x dev-island-sparkle-key.txt --account DevIsland
   ```
   Losing it means no further auto-updates for anyone already installed, and
   recovery is every user re-downloading by hand. The exported file is as
   sensitive as the key; never commit it.

## Never regenerate

Once a release has shipped, the Sparkle key is fixed forever. Regenerating it,
or editing `SUPublicEDKey`, makes every installed copy reject all future updates.
The pin in `scripts/release.sh` turns that silent disaster into a refusal to
build.

## Verifying a build

Never trust the packaging log alone:

```bash
spctl -a -t exec -vv "output/package/Dev Island.app"    # accepted, source=Notarized Developer ID
xcrun stapler validate release/Dev-Island-<version>.dmg  # The validate action worked!
codesign --verify --deep --strict "output/package/Dev Island.app"
```

`scripts/release.sh` runs the first two itself and aborts if either fails.
