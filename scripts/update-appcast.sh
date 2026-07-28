#!/bin/zsh
# Updates appcast.xml with a new release entry.
#
# Usage:
#   zsh scripts/update-appcast.sh <version> <build_number> <ed_signature> <length> [pub_date]
#
# Example:
#   zsh scripts/update-appcast.sh 1.0.3 10 "abc123==" 9014852
#
# If pub_date is omitted, the current UTC time is used.

set -euo pipefail

if [[ $# -lt 4 ]]; then
    echo "Usage: $0 <version> <build_number> <ed_signature> <length> [pub_date]" >&2
    exit 1
fi

VERSION="$1"
BUILD_NUMBER="$2"
ED_SIGNATURE="$3"
LENGTH="$4"
# LC_TIME=C is load-bearing: %a and %b are locale-dependent, and RSS pubDate is
# RFC 822, which allows only the English abbreviations. On this French-locale
# shell the default produced "mar., 28 juil. 2026 ...", which is not a valid
# RFC 822 date. v1.0.0 escaped it only because that build ran under a C locale.
PUB_DATE="${5:-$(LC_TIME=C date -u '+%a, %d %b %Y %H:%M:%S +0000')}"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
appcast="$repo_root/appcast.xml"

if [[ ! -f "$appcast" ]]; then
    echo "Error: appcast.xml not found at $appcast" >&2
    exit 1
fi

download_url="https://github.com/vincentlauriat/dev-island/releases/download/v${VERSION}/Dev.Island.zip"

# Use Python for reliable XML-adjacent text insertion
python3 - "$appcast" "$VERSION" "$BUILD_NUMBER" "$ED_SIGNATURE" "$LENGTH" "$PUB_DATE" "$download_url" <<'PYEOF'
import sys

appcast_path = sys.argv[1]
version = sys.argv[2]
build_number = sys.argv[3]
ed_signature = sys.argv[4]
length = sys.argv[5]
pub_date = sys.argv[6]
download_url = sys.argv[7]

new_item = f"""        <item>
            <title>Version {version}</title>
            <sparkle:version>{build_number}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <pubDate>{pub_date}</pubDate>
            <enclosure
                url="{download_url}"
                type="application/octet-stream"
                sparkle:edSignature="{ed_signature}"
                length="{length}"
            />
        </item>"""

with open(appcast_path, "r") as f:
    content = f.read()

marker = "<!-- Items are added by the release workflow. See docs/releasing.md. -->"
if marker not in content:
    print("Error: marker comment not found in appcast.xml", file=sys.stderr)
    sys.exit(1)

# Insertion is unconditional, so re-running a release for a version already in
# the feed would leave two <item>s claiming the same version with different
# signatures — Sparkle would pick one of them, and which one is not something
# this script gets to decide. Refuse instead, and say how to proceed.
if f"<sparkle:shortVersionString>{version}</sparkle:shortVersionString>" in content:
    print(
        f"Error: appcast.xml already has an entry for {version}.\n"
        f"       Re-running a release for the same version would create a duplicate.\n"
        f"       Remove the existing <item> for {version} first, then re-run.",
        file=sys.stderr,
    )
    sys.exit(1)

content = content.replace(marker, marker + "\n" + new_item)

with open(appcast_path, "w") as f:
    f.write(content)
PYEOF

echo "Updated appcast.xml with version ${VERSION} (build ${BUILD_NUMBER})"
