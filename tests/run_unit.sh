#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 1
TMPFILE=$(mktemp)
timeout 300 flatpak run org.godotengine.Godot --headless --path . -s tests/unit_runner.gd -- "$@" 2>&1 | tee "$TMPFILE"
EXITCODE=${PIPESTATUS[0]}
if grep -q 'SCRIPT ERROR\|Parse Error' "$TMPFILE"; then
    echo "UNIT FAIL script errors"
    rm -f "$TMPFILE"
    exit 1
fi
rm -f "$TMPFILE"
exit $EXITCODE
