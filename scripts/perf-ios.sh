#!/bin/bash
# Launch the app on the iPhone with the DEBUG CPU probe and print its lines for N seconds.
#   scripts/perf-ios.sh <seconds> [extra launch args, e.g. -autoplay]
# Output: "PERF cpu=2.1% thermal=nominal" every 2 s (100% = one core). The app exits with the console.
UDID="${YM_DEVICE:-$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /iPhone/ && !/unavailable/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')}"
SECS="${1:-20}"; shift
perl -e 'alarm shift; exec @ARGV' "$SECS" xcrun devicectl device process launch --device "$UDID" \
  --terminate-existing --console az.pqh.yamusic -- -perfProbe YES "$@" 2>&1 | grep -E "^PERF|^YM "
