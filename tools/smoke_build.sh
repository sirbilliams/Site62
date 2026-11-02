#!/bin/bash
# Launch the exported Linux build in a private virtual KWin (like tools/vrun.sh), host a match with the scripted bot playing
# and wait for round 2; saves a screenshot. usage: tools/smoke_build.sh [shot.png]   (build it first with tools/export_pc.sh;
# it runs build/Site62_smoke.x86_64, the only export that carries the scripted bot)
cd "$(dirname "$0")/.." || exit 1
SHOT=${1:-$HOME/Projects/arena-assets/shots/site62/build_round2.png}
mkdir -p "$(dirname "$SHOT")"
LOG=${SMOKE_LOG:-/tmp/site62_smoke.log}
inner=$(mktemp /tmp/smokeXXXX.sh)
cat > "$inner" <<EOF
#!/bin/bash
exec "$PWD/build/Site62_smoke.x86_64" --display-driver wayland --rendering-method forward_plus -- --smoke=$SHOT --smoke_round=2 --smoke_bot > "$LOG" 2>&1
EOF
chmod +x "$inner"
timeout ${VRUN_TIMEOUT:-300} kwin_wayland --virtual --no-lockscreen --width 1280 --height 720 --socket wl-site62-smoke-$$ "$inner"
rm -f "$inner"
grep -E "SMOKE|ERROR|SCRIPT|Parse" "$LOG" | head -20
grep -q "SMOKE round=2" "$LOG"
