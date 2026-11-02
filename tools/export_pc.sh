#!/usr/bin/env bash
# Export the Linux and Windows desktop builds to build/Site62.x86_64 and build/Site62.exe (release templates).
# Needs the Godot 4.7.2 linux/windows export templates (see README). usage: tools/export_pc.sh
cd "$(dirname "$0")/.." || exit 1
mkdir -p build
G="flatpak run org.godotengine.Godot --headless --path ."
timeout 300 $G --import >/dev/null 2>&1
rc=0
timeout 900 $G --export-release "Linux" build/Site62.x86_64 || rc=1
timeout 900 $G --export-release "Windows Desktop" build/Site62.exe || rc=1
ls -la build/Site62.x86_64 build/Site62.exe
exit $rc
