#!/usr/bin/env bash
# Runs the driver against a simulated inverter.
# Usage: tests/run.sh <path-to-berry-interpreter>
set -euo pipefail
BERRY="${1:?path to the berry interpreter}"
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
cp "$HERE/persist.be" "$HERE/webserver.be" "$TMP/"
cat "$HERE/sim_before.be" "$HERE/../dongle/growatt.be" "$HERE/sim_after.be" > "$TMP/run.be"
cd "$TMP"
"$BERRY" run.be
