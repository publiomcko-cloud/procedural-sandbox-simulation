#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/game"
GODOT="${GODOT_BIN:-godot}"
failures=0

for file in project.godot scenes/main.tscn scripts/bootstrap.gd scripts/region_generator.gd tests/smoke.gd tests/bootstrap_visual_regression.gd; do
  if [[ -f "$PROJECT/$file" ]]; then
    :
  else
    printf 'L0 FAIL: missing source %s\n' "$file" >&2
    failures=$((failures + 1))
  fi
done
if (( failures == 0 )); then echo 'L0 PASS: all project source files exist'; fi

if ! command -v "$GODOT" >/dev/null 2>&1; then
  printf 'FAIL: Godot command not found: %s\n' "$GODOT" >&2
  exit 1
fi
version="$("$GODOT" --version 2>&1)"
version_exit=$?
echo "Godot found: $version"
if (( version_exit != 0 )) || [[ ! "$version" =~ ^4\.7\.2\.stable(\.|$) ]]; then
  printf 'ENV FAIL: Godot 4.7.2 stable required (version command exit=%s)\n' "$version_exit" >&2
  failures=$((failures + 1))
else
  echo 'ENV PASS: pinned Godot 4.7.2 stable'
fi

echo "COMMAND: $GODOT --headless --editor --path $PROJECT --import"
if "$GODOT" --headless --editor --path "$PROJECT" --import; then echo 'L1 PASS: Godot project import'; else code=$?; printf 'L1 FAIL: exit code %s\n' "$code" >&2; failures=$((failures + 1)); fi
echo "COMMAND: $GODOT --headless --path $PROJECT --script res://tests/smoke.gd"
if "$GODOT" --headless --path "$PROJECT" --script res://tests/smoke.gd; then echo 'L2 PASS: deterministic generation and failure-path checks'; else code=$?; printf 'L2 FAIL: exit code %s\n' "$code" >&2; failures=$((failures + 1)); fi
echo "COMMAND: $GODOT --headless --path $PROJECT --script res://tests/bootstrap_visual_regression.gd"
if "$GODOT" --headless --path "$PROJECT" --script res://tests/bootstrap_visual_regression.gd; then echo 'L2 PASS: instantiated bootstrap structure (pixels are not assessed)'; else code=$?; printf 'L2 FAIL: bootstrap structure exit code %s\n' "$code" >&2; failures=$((failures + 1)); fi
echo "COMMAND: $GODOT --headless --path $PROJECT --quit-after 2"
if "$GODOT" --headless --path "$PROJECT" --quit-after 2; then echo 'L2 PASS: configured main scene startup'; else code=$?; printf 'L2 FAIL: main scene startup exit code %s\n' "$code" >&2; failures=$((failures + 1)); fi

if (( failures > 0 )); then
  printf 'VALIDATION_FAIL: failures=%s; GUI visual test is not performed by this script\n' "$failures" >&2
  exit 1
fi
echo 'VALIDATION_PASS: L0-L2; GUI visual test remains an owner task'
