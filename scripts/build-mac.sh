#!/bin/bash
# Build the Mac app (Debug) and optionally run it.
#   scripts/build-mac.sh [--run] [-- <launch args>]
set -o pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Signing team: $YM_TEAM_ID, or `YM_TEAM_ID=XXXXXXXXXX` in local.env at the repo root (not committed).
[ -f "$ROOT/local.env" ] && . "$ROOT/local.env"
[ -n "$YM_TEAM_ID" ] || { echo "set YM_TEAM_ID (Apple developer team id) in local.env"; exit 1; }
cd "$ROOT/mac" && xcodegen generate >/dev/null || exit 1
xcodebuild -project YaMusicMac.xcodeproj -scheme YaMusicMac -destination 'platform=macOS' -configuration Debug \
  -derivedDataPath build/dd DEVELOPMENT_TEAM="$YM_TEAM_ID" -allowProvisioningUpdates build 2>&1 \
  | grep -v "ld: warning" | grep -E "^/.*(error|warning):|error:|BUILD" | sort -u | head -40
[ "${PIPESTATUS[0]}" = 0 ] || exit 1
if [ "$1" = "--run" ]; then
  shift; [ "$1" = "--" ] && shift
  open "$ROOT/mac/build/dd/Build/Products/Debug/Музыка.app" --args "$@"
fi
