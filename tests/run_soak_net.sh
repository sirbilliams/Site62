#!/usr/bin/env bash
# Full-match soak: the real game on a host + 3 bot clients (all four play with SoakBot). PORT, RTT (ms), LOSS (0..1),
# MAXROUND (default 8), SOAK_TIMEOUT (match seconds) env. Prints SOAK PASS rounds=N (N >= 5).
cd "$(dirname "$0")/.." || exit 1
PORT=${PORT:-26100}; RTT=${RTT:-120}; LOSS=${LOSS:-0.03}; MAXROUND=${MAXROUND:-8}; SOAK_TIMEOUT=${SOAK_TIMEOUT:-700}
OUT=$(mktemp -d)
G="flatpak run org.godotengine.Godot --headless --path ."
PIDS=()
cleanup() {
  for p in "${PIDS[@]}"; do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done
  pkill -f "[g]odot.*--test=soak.*--port=$PORT" 2>/dev/null
  [ -n "$KEEP" ] && echo "logs kept in $OUT" || rm -rf "$OUT"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
run() {
  timeout $((SOAK_TIMEOUT + 120)) $G -- --test=soak --role=$1 --port=$PORT --rtt_ms=$RTT --loss=$LOSS --maxround=$MAXROUND --timeout=$SOAK_TIMEOUT ${DEBUG:+--debug=1} > "$OUT/$1.log" 2>&1 &
  PIDS+=($!)
}
waitfor() { for ((i = 0; i < $3 * 5; i++)); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.2; done; return 1; }
fail() { echo "SOAK NET FAIL: $1"; grep -hE "SOAK|ERROR|SCRIPT|at:|Parse" "$OUT"/*.log | head -40; exit 1; }
run host; HP=$!
waitfor "$OUT/host.log" "Godot Engine" 40 || fail "host did not start"
sleep 1
for r in b1 b2 b3; do run $r; sleep 0.5; done
wait $HP; HS=$?
sleep 4
[ $HS = 0 ] || fail "host exit $HS"
grep -q "SOAK PASS" "$OUT/host.log" || fail "host did not pass"
for r in b1 b2 b3; do
  grep -q "SOAK CLIENT OK ($r)" "$OUT/$r.log" || fail "$r did not exit cleanly"
done
if grep -hE "SCRIPT ERROR|Parse Error|Lambda capture|ERROR: (Invalid|Cannot|Condition)" "$OUT"/*.log | head -5 | grep -q .; then fail "errors in logs"; fi
grep -h "SOAK" "$OUT"/*.log | grep -v "SOAK t="
exit 0
