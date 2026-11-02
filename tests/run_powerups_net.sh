#!/usr/bin/env bash
# Host + clients a, b: the six power-up drops. RTT on every process. PORT, RTT, LOSS env.
cd "$(dirname "$0")/.." || exit 1
PORT=${PORT:-26100}; RTT=${RTT:-150}; LOSS=${LOSS:-0}
OUT=$(mktemp -d)
G="flatpak run org.godotengine.Godot --headless --path ."
PIDS=()
cleanup() {
  for p in "${PIDS[@]}"; do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done
  pkill -f "[g]odot.*--test=powerups.*--port=$PORT" 2>/dev/null
  rm -rf "$OUT"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
run() { # role log
  timeout 170 $G -- --test=powerups --role=$1 --port=$PORT --rtt_ms=$RTT --loss=$LOSS > "$OUT/$2.log" 2>&1 &
  PIDS+=($!)
}
waitfor() { for ((i = 0; i < $3 * 5; i++)); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.2; done; return 1; }
fail() { echo "POWERUPS NET FAIL: $1"; cat "$OUT"/*.log | grep -E "POWERUPS|ERROR|SCRIPT|at:" | head -30; exit 1; }
run host host; HP=$!
waitfor "$OUT/host.log" "Godot Engine" 30 || fail "host did not start"
sleep 1
run a a
sleep 1
run b b
wait $HP; HS=$?
sleep 4
[ $HS = 0 ] || fail "host exit $HS"
for t in "$OUT/host.log:POWERUPS NET PASS" "$OUT/a.log:POWERUPS NET CLIENT OK (a)" "$OUT/b.log:POWERUPS NET CLIENT OK (b)"; do
  grep -q "${t#*:}" "${t%%:*}" || fail "missing '${t#*:}' in $(basename "${t%%:*}")"
done
grep -h "POWERUPS" "$OUT"/*.log
exit 0
