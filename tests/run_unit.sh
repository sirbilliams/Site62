#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 1
timeout 300 flatpak run org.godotengine.Godot --headless --path . -s tests/unit_runner.gd -- "$@"
