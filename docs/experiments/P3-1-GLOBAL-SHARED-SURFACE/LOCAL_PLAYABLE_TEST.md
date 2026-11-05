# Local playtest — Global Shared-Surface Authority

Repository: C:\\Dev\\sandbox-sim-dev

## Update

PowerShell:
cd C:\\Dev\\sandbox-sim-dev
git fetch origin
git status
git merge --ff-only origin/exp/p3-1-shared-surface-e2e-success
git rev-parse HEAD

Do not delete existing untracked evidence files.

## Launch

$godot = "C:\\Tools\\Godot\\Godot_v4.7.2-stable_win64_console.exe"
& $godot --path C:\\Dev\\sandbox-sim-dev\\game -- --preedit-count=512

Wait for initial staging, then press F5. The fixture now includes general edits, X seams, Z seams and X/Z four-region corners. Wait for archived≈512, hot tail 0, and a committed generation.

## Geometry test

Move through X seams, Z seams and diagonally through four-region corners. Toggle LOD with L. There should be no visible cracks, holes, stale chunks or discontinuities.

## Diagonal unload/reload

Move in +X and +Z until focus is near region (4,4), then return to (0,0). Observe time-to-focus-visible, edit fidelity, X/Z/corner seam fidelity and frame p95/p99 while the rest of the 3x3 window loads.

Hosted reference for 256 edits: focus visible ~1.77 s; full 3x3 settle ~13.4 s; frame p95 ~7.04 ms; p99 ~7.14 ms; checkpoint worker ~1.17 s; journal reads during reload 0.

## Automated gates

$godot = "C:\\Tools\\Godot\\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --editor --path C:\\Dev\\sandbox-sim-dev\\game --quit
& $godot --headless --path C:\\Dev\\sandbox-sim-dev\\game --script res://tests/experiments/shared_surface_e2e_integration.gd
& $godot --headless --path C:\\Dev\\sandbox-sim-dev\\game --script res://tests/experiments/global_shared_surface_qualification.gd
& $godot --headless --path C:\\Dev\\sandbox-sim-dev\\game --script res://tests/experiments/runtime_scalable_playable_qualification.gd

Expected markers:
SHARED_SURFACE_E2E_PASS: assertions=48 failures=0
GLOBAL_SHARED_SURFACE_PASS: assertions=159 failures=0
RUNTIME_SCALABLE_PLAYABLE_PASS: assertions=33 failures=0