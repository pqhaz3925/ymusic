#!/bin/bash
# Build the Mac app in Release and install it into /Applications.
#   scripts/install-mac.sh [--open]
set -o pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Signing team: $YM_TEAM_ID, or `YM_TEAM_ID=XXXXXXXXXX` in local.env at the repo root (not committed).
[ -f "$ROOT/local.env" ] && . "$ROOT/local.env"
[ -n "$YM_TEAM_ID" ] || { echo "set YM_TEAM_ID (Apple developer team id) in local.env"; exit 1; }
cd "$ROOT/mac" && xcodegen generate >/dev/null || exit 1
xcodebuild -project YaMusicMac.xcodeproj -scheme YaMusicMac -destination 'platform=macOS' -configuration Release \
  -derivedDataPath build/dd DEVELOPMENT_TEAM="$YM_TEAM_ID" -allowProvisioningUpdates build 2>&1 \
  | grep -v "ld: warning" | grep -E "^/.*(error|warning):|error:|BUILD" | sort -u | head -40
[ "${PIPESTATUS[0]}" = 0 ] || exit 1
APP="$ROOT/mac/build/dd/Build/Products/Release/Музыка.app"
DEST="/Applications/Музыка.app"
# Quit a running copy so the bundle can be replaced.
osascript -e 'tell application id "az.pqh.yamusic.mac" to quit' >/dev/null 2>&1
rm -rf "$DEST" && ditto "$APP" "$DEST" || exit 1
echo "installed: $DEST"
[ "$1" = "--open" ] && open "$DEST"
exit 0
