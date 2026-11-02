#!/usr/bin/env bash
# Host + 3 clients + a 5th client (must be refused "full"). PORT/BP env, defaults 26100/7800.
cd "$(dirname "$0")/.." || exit 1
PORT=${PORT:-26100}; BP=${BP:-7800}
OUT=$(mktemp -d)
G="flatpak run org.godotengine.Godot --headless --path ."
run() { # role idx log
  timeout 90 $G -- --test=basic --role=$1 --idx=$2 --port=$PORT --bp=$BP > "$OUT/$3.log" 2>&1 &
}
run host 0 host; HP=$!
sleep 4
run client 1 c1; run client 2 c2; run client 3 c3
sleep 8
run client 5 c5
wait $HP; HS=$?
sleep 3
pkill -f "[g]odot.*--test=basic.*--port=$PORT" 2>/dev/null
grep -h "BASIC NET" "$OUT"/*.log
if [ $HS = 0 ] && grep -q "BASIC NET PASS" "$OUT/host.log" && grep -q "refused full" "$OUT/c5.log"; then
  exit 0
fi
echo "BASIC NET FAIL (logs in $OUT)"; exit 1
