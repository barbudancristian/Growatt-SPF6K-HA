#!/usr/bin/env bash
# Runs the driver against a simulated inverter.
# Usage: tests/run.sh <path-to-berry-interpreter>
set -euo pipefail
BERRY="${1:?path to the berry interpreter}"
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
cp "$HERE/persist.be" "$HERE/webserver.be" "$HERE/mqtt.be" "$TMP/"
cat "$HERE/sim_before.be" "$HERE/../dongle/growatt.be" "$HERE/sim_after.be" > "$TMP/body.be"
# The device compiles growatt.be with strict mode on, so compile the test the same way.
cat > "$TMP/run.be" <<'BE'
import strict
var f = open("body.be")
var src = f.read()
f.close()
compile(src)()
BE
cd "$TMP"
"$BERRY" run.be
