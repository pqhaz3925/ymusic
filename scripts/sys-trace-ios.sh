#!/bin/bash
# System-wide Activity Monitor trace of the iPhone; prints average %CPU of the top processes
# (watch `backboardd` = the compositor, and the app itself).
#   scripts/sys-trace-ios.sh <output-name> <seconds>
# xctrace sometimes answers "Waiting for device to boot": just run it again.
UDID="${YM_DEVICE:-$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /iPhone/ && !/unavailable/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')}"
OUT="${TMPDIR:-/tmp}/$1.trace"; rm -rf "$OUT"
perl -e 'alarm 150; exec @ARGV' xcrun xctrace record --template 'Activity Monitor' --device "$UDID" \
  --all-processes --time-limit "${2:-12}s" --output "$OUT" 2>&1 | grep -v "^Starting\|^Ctrl" | tail -2
[ -d "$OUT" ] && python3 "$(dirname "$0")/trace-cpu.py" "$OUT"
