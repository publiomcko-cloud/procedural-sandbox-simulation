# Local qualification test

Use this to reproduce the successful E2E without changing your normal R6 checkout.

## Checkout

```powershell
cd C:\Dev\procedural-sandbox-simulation
git fetch origin
git switch -c test/shared-surface-e2e --track origin/exp/p3-1-shared-surface-e2e-success
```

If that local branch already exists:

```powershell
git switch test/shared-surface-e2e
git reset --hard origin/exp/p3-1-shared-surface-e2e-success
```

## Godot 4.7.2

Set the executable path if Godot is not already on PATH:

```powershell
$godot = "C:\path\to\Godot_v4.7.2-stable_win64.exe"
```

Import project script classes first:

```powershell
& $godot --headless --editor --path game --quit
```

Run the E2E qualification:

```powershell
& $godot --headless --path game --script res://tests/experiments/shared_surface_e2e_integration.gd
```

Expected terminal marker:

```text
SHARED_SURFACE_E2E_PASS: assertions=48 failures=0
```

The script creates temporary schema-v2 persistence under Godot's user-data location and removes it at the end.

## Important

This command validates the same data/meshing/persistence path that passed GitHub Actions. It is not yet the visual gameplay test because the normal `terrain_demo.gd` scheduler has not been switched to pair-owned boundary jobs.

Do not merge this branch into R6. Keep your R6 checkout/worktree separate.
