#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/game"
GODOT="${GODOT_BIN:-godot}"
failures=0

for file in project.godot scenes/main.tscn scenes/terrain_demo.tscn scripts/bootstrap.gd scripts/region_generator.gd scripts/terrain/sdf_world.gd scripts/terrain/marching_tetrahedra.gd scripts/terrain/terrain_demo.gd scripts/simulation/fixed_tick_scheduler.gd scripts/simulation/simulation_tier_state.gd scripts/simulation/simulation_tier_router.gd scripts/simulation/material_environment_domain.gd scripts/simulation/material_environment_work_queue.gd scripts/simulation/material_environment_runtime_bridge.gd scripts/simulation/simulation_runtime.gd scripts/experiments/lod01_transition_fixture.gd tests/smoke.gd tests/terrain_sdf_tests.gd tests/p4_0a_fixed_tick_scheduler_tests.gd tests/p4_0b_simulation_tier_tests.gd tests/p4_0c_simulation_tier_router_tests.gd tests/p4_0d_material_environment_tests.gd tests/p4_0e_material_runtime_tests.gd tests/lod01_transition_tests.gd tests/bootstrap_visual_regression.gd; do
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
echo "COMMAND: $GODOT --headless --path $PROJECT --script res://tests/terrain_sdf_tests.gd"
if "$GODOT" --headless --path "$PROJECT" --script res://tests/terrain_sdf_tests.gd; then echo 'L2 PASS: deterministic SDF and mesh tests'; else code=$?; printf 'L2 FAIL: terrain SDF tests exit code %s\n' "$code" >&2; failures=$((failures + 1)); fi
echo "COMMAND: $GODOT --headless --path $PROJECT --script res://tests/p4_0a_fixed_tick_scheduler_tests.gd"
if "$GODOT" --headless --path "$PROJECT" --script res://tests/p4_0a_fixed_tick_scheduler_tests.gd; then echo 'L2 PASS: deterministic bounded fixed-tick scheduler foundation'; else code=$?; printf 'L2 FAIL: P4.0A fixed-tick scheduler tests exit code %s\n' "$code" >&2; failures=$((failures + 1)); fi
echo "COMMAND: $GODOT --headless --path $PROJECT --script res://tests/p4_0b_simulation_tier_tests.gd"
if "$GODOT" --headless --path "$PROJECT" --script res://tests/p4_0b_simulation_tier_tests.gd; then echo 'L2 PASS: bounded active/aggregate/dormant simulation tier framework'; else code=$?; printf 'L2 FAIL: P4.0B simulation tier tests exit code %s\n' "$code" >&2; failures=$((failures + 1)); fi
echo "COMMAND: $GODOT --headless --path $PROJECT --script res://tests/p4_0c_simulation_tier_router_tests.gd"
if "$GODOT" --headless --path "$PROJECT" --script res://tests/p4_0c_simulation_tier_router_tests.gd; then echo 'L2 PASS: bounded deterministic automatic simulation tier routing'; else code=$?; printf 'L2 FAIL: P4.0C tier router tests exit code %s\n' "$code" >&2; failures=$((failures + 1)); fi
echo "COMMAND: $GODOT --headless --path $PROJECT --script res://tests/p4_0d_material_environment_tests.gd"
if "$GODOT" --headless --path "$PROJECT" --script res://tests/p4_0d_material_environment_tests.gd; then echo 'L2 PASS: mod-first material/environment state domain'; else code=$?; printf 'L2 FAIL: P4.0D material/environment tests exit code %s\n' "$code" >&2; failures=$((failures + 1)); fi
echo "COMMAND: $GODOT --headless --path $PROJECT --script res://tests/p4_0e_material_runtime_tests.gd"
if "$GODOT" --headless --path "$PROJECT" --script res://tests/p4_0e_material_runtime_tests.gd; then echo 'L2 PASS: bounded material runtime orchestration'; else code=$?; printf 'L2 FAIL: P4.0E material runtime tests exit code %s\n' "$code" >&2; failures=$((failures + 1)); fi
echo "COMMAND: $GODOT --headless --path $PROJECT --script res://tests/lod01_transition_tests.gd"
if "$GODOT" --headless --path "$PROJECT" --script res://tests/lod01_transition_tests.gd; then echo 'L2 PASS: experimental deterministic LOD 0/1 transition fixture'; else code=$?; printf 'L2 FAIL: LOD 0/1 transition fixture exit code %s\n' "$code" >&2; failures=$((failures + 1)); fi
echo "COMMAND: $GODOT --headless --path $PROJECT --script res://tests/bootstrap_visual_regression.gd"
if "$GODOT" --headless --path "$PROJECT" --script res://tests/bootstrap_visual_regression.gd; then echo 'L2 PASS: instantiated bootstrap structure (pixels are not assessed)'; else code=$?; printf 'L2 FAIL: bootstrap structure exit code %s\n' "$code" >&2; failures=$((failures + 1)); fi
echo "COMMAND: $GODOT --headless --path $PROJECT --quit-after 2"
if "$GODOT" --headless --path "$PROJECT" --quit-after 2; then echo 'L2 PASS: configured main scene startup'; else code=$?; printf 'L2 FAIL: main scene startup exit code %s\n' "$code" >&2; failures=$((failures + 1)); fi

if (( failures > 0 )); then
  printf 'VALIDATION_FAIL: failures=%s; GUI visual test is not performed by this script\n' "$failures" >&2
  exit 1
fi
echo 'VALIDATION_PASS: L0-L2; GUI visual test remains an owner task'
