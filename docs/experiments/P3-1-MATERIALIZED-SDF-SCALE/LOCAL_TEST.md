# Local load + fidelity stress test

Repository: C:\Dev\sandbox-sim-dev

After fetching the remote experimental branch, fast-forward the existing local test branch. Do not clean untracked evidence files.

~~~powershell
cd C:\Dev\sandbox-sim-dev
git fetch origin
git status
git merge --ff-only origin/exp/p3-1-shared-surface-e2e-success
git rev-parse HEAD
~~~

The implementation qualified by the hosted run is commit 638e69e0948bb61952cac5ea358446d241b7c03d; documentation commits may place the branch HEAD later.

Godot:

C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe

Import and frozen geometry regression:

~~~powershell
$godot = "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --editor --path C:\Dev\sandbox-sim-dev\game --quit
& $godot --headless --path C:\Dev\sandbox-sim-dev\game --script res://tests/experiments/shared_surface_e2e_integration.gd
~~~

Expected:

SHARED_SURFACE_E2E_PASS: assertions=48 failures=0

Then run the scalable-world qualification:

~~~powershell
$env:SCALABLE_EDIT_COUNT = "4096"
& $godot --headless --path C:\Dev\sandbox-sim-dev\game --script res://tests/experiments/materialized_sdf_scalability_qualification.gd
~~~

Expected:

MATERIALIZED_SDF_SCALE_PASS: assertions=45 failures=0

For stronger local load tests, rerun with increasing values, for example 8192 and 20000. The current harness caps the configured count at 20000.

Do not infer infinite capacity from one finite load count. The relevant architectural gate is that normal hot load performs zero journal replay and chunk recovery remains spatial/local while the archived lifetime edit count grows.
