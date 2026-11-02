#!/usr/bin/env bash
# Host + clients a, b; client d joins mid-match (staged) and must get the full world. RTT on every process. PORT, RTT, LOSS, NOWS env.
cd "$(dirname "$0")/.." || exit 1
PORT=${PORT:-26100}; RTT=${RTT:-150}; LOSS=${LOSS:-0}
EXTRA=""; [ -n "$NOWS" ] && EXTRA="--nows=1"
OUT=$(mktemp -d)
G="flatpak run org.godotengine.Godot --headless --path ."
PIDS=()
cleanup() {
  for p in "${PIDS[@]}"; do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done
  pkill -f "[g]odot.*--test=latejoin.*--port=$PORT" 2>/dev/null
  rm -rf "$OUT"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
run() { # role log
  timeout 170 $G -- --test=latejoin --role=$1 --port=$PORT --rtt_ms=$RTT --loss=$LOSS $EXTRA > "$OUT/$2.log" 2>&1 &
  PIDS+=($!)
}
waitfor() { for ((i = 0; i < $3 * 5; i++)); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.2; done; return 1; }
fail() { echo "LATEJOIN NET FAIL: $1"; cat "$OUT"/*.log | grep -E "LATEJOIN|ERROR|SCRIPT|at:|Parse" | head -30; exit 1; }
run host host; HP=$!
waitfor "$OUT/host.log" "Godot Engine" 30 || fail "host did not start"
sleep 1
run a a
sleep 1
run b b
waitfor "$OUT/host.log" "LATEJOIN STAGED" 40 || fail "host never staged the match"
sleep 1
run d d
wait $HP; HS=$?
sleep 4
[ $HS = 0 ] || fail "host exit $HS"
for t in "$OUT/host.log:LATEJOIN NET PASS" "$OUT/a.log:LATEJOIN NET CLIENT OK (a)" "$OUT/b.log:LATEJOIN NET CLIENT OK (b)" "$OUT/d.log:LATEJOIN NET CLIENT OK (d)"; do
  grep -q "${t#*:}" "${t%%:*}" || fail "missing '${t#*:}' in $(basename "${t%%:*}")"
done
grep -h "LATEJOIN" "$OUT"/*.log
exit 0
