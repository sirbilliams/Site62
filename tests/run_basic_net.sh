#!/usr/bin/env bash
# Host + 3 clients + a 5th client (must be refused "full"). PORT/BP env, defaults 26100/7800.
cd "$(dirname "$0")/.." || exit 1
PORT=${PORT:-26100}; BP=${BP:-7800}
OUT=$(mktemp -d)
G="flatpak run org.godotengine.Godot --headless --path ."
PIDS=()
cleanup() {
  for p in "${PIDS[@]}"; do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done
  pkill -f "[g]odot.*--test=basic.*--port=$PORT" 2>/dev/null
  rm -rf "$OUT"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
run() { # role idx log
  timeout 90 $G -- --test=basic --role=$1 --idx=$2 --port=$PORT --bp=$BP > "$OUT/$3.log" 2>&1 &
  PIDS+=($!)
}
waitfor() { # file pattern seconds
  for ((i = 0; i < $3 * 5; i++)); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.2; done
  return 1
}
fail() { echo "BASIC NET FAIL: $1"; cat "$OUT"/*.log | grep -E "BASIC NET|ROSTER|BEACON|CLIENT|ERROR" | head -30; exit 1; }
run host 0 host; HP=$!
waitfor "$OUT/host.log" "Godot Engine" 30 || fail "host did not start"
sleep 1
run client 1 c1; run client 2 c2; run client 3 c3
waitfor "$OUT/host.log" "ROSTER 4" 40 || fail "roster never reached 4"
run client 5 c5
wait $HP; HS=$?
sleep 3
TOKENS=("$OUT/host.log:BASIC NET PASS" "$OUT/host.log:ROSTER 4" "$OUT/c1.log:CLIENT ROSTER OK" "$OUT/c2.log:CLIENT ROSTER OK" "$OUT/c3.log:CLIENT ROSTER OK" \
  "$OUT/c3.log:CLIENT LEAVE STATE OK" "$OUT/c1.log:CLIENT LEFT OK" "$OUT/c2.log:CLIENT LEFT OK" "$OUT/c1.log:BEACON OK" "$OUT/c5.log:refused full")
[ $HS = 0 ] || fail "host exit $HS"
for t in "${TOKENS[@]}"; do
  grep -q "${t#*:}" "${t%%:*}" || fail "missing '${t#*:}' in $(basename "${t%%:*}")"
done
grep -h -E "BASIC NET|ROSTER|BEACON" "$OUT"/*.log
exit 0
