#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
test -f "$ROOT/game/project.godot"
"$GODOT" --headless --editor --path "$ROOT/game" --import
"$GODOT" --headless --path "$ROOT/game" --script res://tests/smoke.gd
echo 'VALIDATION_PASS (L0-L2 only)'
