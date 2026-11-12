#!/bin/bash
# Build a signed Debug build and install it on a connected iPhone.
#   scripts/deploy-ios.sh [--launch] [-- <launch args>]
# Device: $YM_DEVICE (UDID), default = the first connected physical iPhone.
# The app already on the phone must be signed by the same team, or the install is rejected
# (and the Keychain token would be lost).
set -o pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Signing team: $YM_TEAM_ID, or `YM_TEAM_ID=XXXXXXXXXX` in local.env at the repo root (not committed).
[ -f "$ROOT/local.env" ] && . "$ROOT/local.env"
[ -n "$YM_TEAM_ID" ] || { echo "set YM_TEAM_ID (Apple developer team id) in local.env"; exit 1; }
UDID="${YM_DEVICE:-$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /iPhone/ && !/unavailable/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')}"
[ -n "$UDID" ] || { echo "no connected iPhone (set YM_DEVICE)"; exit 1; }
DD="$ROOT/ios/build/dd"
cd "$ROOT/ios" && xcodegen generate >/dev/null || exit 1
xcodebuild -project YaMusic.xcodeproj -scheme YaMusic -destination "id=$UDID" -configuration Debug \
  -derivedDataPath "$DD" DEVELOPMENT_TEAM="$YM_TEAM_ID" -allowProvisioningUpdates build 2>&1 | grep -v "ld: warning" | grep -E "^/.*(error|warning):|error:|BUILD" | sort -u | head -40
[ "${PIPESTATUS[0]}" = 0 ] || exit 1
xcrun devicectl device install app --device "$UDID" "$DD/Build/Products/Debug-iphoneos/YaMusic.app" 2>&1 | grep -i -E "error|App installed" | head -3
if [ "$1" = "--launch" ]; then
  shift; [ "$1" = "--" ] && shift
  xcrun devicectl device process launch --device "$UDID" --terminate-existing az.pqh.yamusic -- "$@" 2>&1 | tail -1
fi
