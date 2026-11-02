#!/usr/bin/env bash
# Host + client a in the real game; the host leaves mid-round. a must reach the menu ("host left") within 3 s. PORT env (BP is
# accepted but unused: the tests set Net.beacon_port = 0).
cd "$(dirname "$0")/.." || exit 1
PORT=${PORT:-26100}
OUT=$(mktemp -d)
G="flatpak run org.godotengine.Godot --headless --path ."
PIDS=()
cleanup() {
  for p in "${PIDS[@]}"; do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done
  pkill -f "[g]odot.*--test=hostquit.*--port=$PORT" 2>/dev/null
  rm -rf "$OUT"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
run() {
  timeout 150 $G -- --test=hostquit --role=$1 --port=$PORT > "$OUT/$1.log" 2>&1 &
  PIDS+=($!)
}
waitfor() { for ((i = 0; i < $3 * 5; i++)); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.2; done; return 1; }
fail() { echo "HOSTQUIT NET FAIL: $1"; cat "$OUT"/*.log | grep -E "HOSTQUIT|ERROR|SCRIPT|at:|Parse" | head -30; exit 1; }
run host; HP=$!
waitfor "$OUT/host.log" "Godot Engine" 30 || fail "host did not start"
sleep 1
run a
waitfor "$OUT/host.log" "HOSTQUIT NET HOST QUITTING" 80 || fail "host never reached the round"
START=$(date +%s.%N)
wait $HP; HS=$?
[ $HS = 0 ] || fail "host exit $HS"
waitfor "$OUT/a.log" "HOSTQUIT NET CLIENT OK (a)" 3 || fail "client did not reach the menu within 3 s of the host leaving"
echo "client left $(echo "$(date +%s.%N) - $START" | bc) s after the host process exited"
grep -h "HOSTQUIT" "$OUT"/*.log
exit 0
