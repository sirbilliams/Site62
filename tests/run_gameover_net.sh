#!/usr/bin/env bash
# Host + e (joins in the lobby, builds its game late) + f (connects after game over). Game over must stop the match on the
# host, refuse f ("over") and still show e the summary. PORT env (BP accepted but unused: the tests set Net.beacon_port = 0).
cd "$(dirname "$0")/.." || exit 1
PORT=${PORT:-26100}
OUT=$(mktemp -d)
G="flatpak run org.godotengine.Godot --headless --path ."
PIDS=()
cleanup() {
  for p in "${PIDS[@]}"; do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done
  pkill -f "[g]odot.*--test=gameover.*--port=$PORT" 2>/dev/null
  rm -rf "$OUT"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
run() {
  timeout 150 $G -- --test=gameover --role=$1 --port=$PORT > "$OUT/$1.log" 2>&1 &
  PIDS+=($!)
}
waitfor() { for ((i = 0; i < $3 * 5; i++)); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.2; done; return 1; }
fail() { echo "GAMEOVER NET FAIL: $1"; cat "$OUT"/*.log | grep -E "GAMEOVER|ERROR|SCRIPT|at:|Parse" | head -30; exit 1; }
run host; HP=$!
waitfor "$OUT/host.log" "Godot Engine" 30 || fail "host did not start"
sleep 1
run e
waitfor "$OUT/host.log" "GAMEOVER NET OVER" 80 || fail "host never reached game over"
run f
wait $HP; HS=$?
sleep 3
[ $HS = 0 ] || fail "host exit $HS"
for t in "host:GAMEOVER NET PASS" "e:GAMEOVER NET CLIENT OK (e)" "f:GAMEOVER NET CLIENT OK (f)"; do
  grep -q "${t#*:}" "$OUT/${t%%:*}.log" || fail "missing '${t#*:}' in ${t%%:*}"
done
grep -h "GAMEOVER" "$OUT"/*.log
exit 0
