# Releasing

Dev Island releases are built **locally**, not in CI. There are no GitHub secrets:
the Developer ID certificate, the notarization credentials and the Sparkle signing
key all live in the login keychain. See [release-signing.md](release-signing.md)
for the one-time setup.

## Versioning

[Semantic Versioning](https://semver.org/). Dev Island's numbering is independent
of upstream's and starts at `v1.0.0` — see the Versioning section of
[fork-sync.md](fork-sync.md) for why, and for the `--no-tags` rule that keeps
upstream's tags from creeping back.

## Cutting a release

```bash
git checkout main && git pull
zsh scripts/release.sh 1.0.0
```

That single command builds a universal Release binary, signs it with Hardened
Runtime, notarizes it, staples the ticket, produces the styled DMG, signs the
update for Sparkle, and adds the entry to `appcast.xml`. It **pushes nothing** —
it prints the `gh release create` invocation to run once the notes are written.

Before doing any of that it refuses to start unless:

- the version is `MAJOR.MINOR.PATCH` and its tag does not already exist;
- the working tree is clean;
- the Developer ID identity is in the keychain;
- the notary profile answers (`notarytool history`);
- **the Sparkle public key in the keychain matches the one pinned in the script.**

That last check is the important one. A mismatch means the key was regenerated,
and shipping an update signed with a new key would make every installed copy
reject all future auto-updates. The script stops rather than build it.

After packaging it re-verifies independently, because a packaging script that
prints success is not evidence:

```bash
spctl -a -t exec -vv "output/package/Dev Island.app"   # source=Notarized Developer ID
xcrun stapler validate release/Dev-Island-<version>.dmg
```

## Publishing

```bash
git add appcast.xml && git commit -m "chore: appcast for v1.0.0"
git tag v1.0.0 && git push origin main v1.0.0
gh release create v1.0.0 \
  release/Dev-Island-1.0.0.dmg release/Dev.Island.zip \
  --title "Dev Island v1.0.0 — <short English title>" \
  --notes-file release/release-notes-1.0.0.md
```

The zip asset **must** keep the name `Dev.Island.zip`: `appcast.xml`'s enclosure
URL points at it, and Sparkle downloads exactly that path. GitHub turns spaces
into dots in asset names, which is where the odd-looking name comes from.

## Release notes

Bilingual, English + 简体中文. Template in `.github/RELEASE_TEMPLATE.md`.

```markdown
## Dev Island v<version> — <Title>

### Changes since v<prev> | 自 v<prev> 以来的变更

- <emoji> **Category**: English description (#PR)
  中文描述 (#PR)
```

| Emoji | Category | When to use |
|-------|----------|-------------|
| ✨ | Feature | New user-facing functionality |
| 🐛 | Fix | Bug fix |
| 📸/📋 | Docs | Documentation changes |
| ♻️ | Refactor | Code restructuring |
| 🏗️ | Infra | Build, packaging changes |

External contributors get `— Thanks @user` on the English line.

### Installation section

Releases are signed and notarized, so **do not** carry the old
`xattr -dr com.apple.quarantine` workaround: it is for unsigned builds and
telling users to strip quarantine from a notarized app is worse than useless.

```markdown
## Installation | 安装说明

1. Download **Dev-Island-<version>.dmg**, open it, drag **Dev Island** to **Applications**.
   下载 **Dev-Island-<version>.dmg**，打开后将 **Dev Island** 拖入 **Applications**。

2. Requirements: **macOS 14+**.
   系统要求：**macOS 14+**。
```

## Assets

| File | Purpose |
|------|---------|
| `Dev-Island-<version>.dmg` | Styled disk image, drag-to-Applications |
| `Dev.Island.zip` | Sparkle update payload — name is load-bearing |

## Sparkle appcast

`appcast.xml` at the repo root is the update feed, served from:

```
https://raw.githubusercontent.com/vincentlauriat/dev-island/main/appcast.xml
```

`scripts/release.sh` adds each entry through `scripts/update-appcast.sh`; hand
editing is only for fixing a mistake. Entry shape:

```xml
<item>
    <title>Version X.Y.Z</title>
    <sparkle:version>BUILD_NUMBER</sparkle:version>
    <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    <pubDate>Thu, 06 Apr 2026 00:00:00 +0000</pubDate>
    <enclosure
        url="https://github.com/vincentlauriat/dev-island/releases/download/vX.Y.Z/Dev.Island.zip"
        type="application/octet-stream"
        sparkle:edSignature="…"
        length="…"
    />
</item>
```

The feed starts empty: upstream's 48 entries pointed at upstream DMGs signed
with upstream's key, and keeping them would have auto-updated Dev Island users
onto the upstream app. See [fork-sync.md](fork-sync.md).
