#!/usr/bin/env bash
# Host + a client x that joins a running match and never sends `ready`. PORT env.
cd "$(dirname "$0")/.." || exit 1
PORT=${PORT:-26100}
OUT=$(mktemp -d)
G="flatpak run org.godotengine.Godot --headless --path ."
PIDS=()
cleanup() {
  for p in "${PIDS[@]}"; do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done
  pkill -f "[g]odot.*--test=noready.*--port=$PORT" 2>/dev/null
  rm -rf "$OUT"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
run() {
  timeout 120 $G -- --test=noready --role=$1 --port=$PORT > "$OUT/$1.log" 2>&1 &
  PIDS+=($!)
}
waitfor() { for ((i = 0; i < $3 * 5; i++)); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.2; done; return 1; }
fail() { echo "NOREADY NET FAIL: $1"; cat "$OUT"/*.log | grep -E "NOREADY|ERROR|SCRIPT|at:|Parse" | head -30; exit 1; }
run host; HP=$!
waitfor "$OUT/host.log" "Godot Engine" 30 || fail "host did not start"
sleep 1
run x
wait $HP; HS=$?
sleep 3
[ $HS = 0 ] || fail "host exit $HS"
grep -q "NOREADY NET PASS" "$OUT/host.log" || fail "host did not pass"
grep -q "NOREADY NET CLIENT OK (x)" "$OUT/x.log" || fail "x did not exit cleanly"
if grep -q "Node not found" "$OUT/x.log"; then fail "x log has node-not-found noise"; fi
grep -h "NOREADY" "$OUT"/*.log
exit 0
