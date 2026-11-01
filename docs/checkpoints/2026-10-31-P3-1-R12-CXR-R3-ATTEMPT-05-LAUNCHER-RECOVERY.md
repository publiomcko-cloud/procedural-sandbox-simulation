# P3.1 R12-CXR R3 attempt 05 launcher recovery

Date: 2026-10-31 America/Sao_Paulo; event timestamps are recorded in UTC where available.

Attempt identity remains R3_TARGET_20261031_05 for frozen scenario R9.2.SEAM.XPLUS_EQUAL.v1 on code source 4734e6cb0c80cde086ea86e7d8afcda983e3a24b. The pretarget freeze and source pins remain valid.

## Prelaunch failure

The first invocation of launcher wrapper launch-target.ps1 failed at its first durable-intent file creation because the unique attempt root and host_dispatcher directory did not exist. The error was recorded before any dispatcher Process.Start call. No attempt reservation, dispatcher process, Godot process, or scenario invocation exists; the target evidence root remained absent. The complete failure record is launcher-failure-01.json. The frozen dispatcher and source were not changed, and attempt 04 was not rerun.

## Bounded recovery

The new wrapper launch-target-r2.ps1 performs a fail-if-root-exists check, then creates the attempt root and the host_dispatcher and engine_evidence subdirectories before writing any intent. It preserves the frozen dispatcher pins, exact source/fixture pins, attempt ID, timeout and resource stop-loss. PowerShell static parsing reports zero errors. Its SHA-256 is b1a5398f612b8bc7c0a2d7c1ee572ef3583122a7a9d860cf0c9827cd2946c947. The original failed wrapper remains byte-preserved as launch-target.ps1.

The pretarget evidence index v2 covers the failed setup record and corrected wrapper. At this checkpoint the target remains NOT_STARTED and no reservation exists. Only after this recovery checkpoint is committed and pushed may the corrected wrapper be invoked once. If a Godot process starts, do not rerun this attempt.

No scenario geometry, controls, later gates, full validation, production code, persistence schema, Issue #108, merge, or release work occurred. All five F2-G1 holds remain.