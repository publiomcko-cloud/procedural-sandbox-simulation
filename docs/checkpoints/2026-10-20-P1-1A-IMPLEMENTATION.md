# CHK-2026-10-20-P1-1A-IMPLEMENTATION

**Checkpoint date/timezone:** 2026-10-20, America/Sao_Paulo
**Event type:** authorized implementation and test handoff
**Publication state:** recorded on the P1.1A feature branch and draft PR #96; unmerged
**Immutable once integrated:** yes; record later review, GUI, or merge events in a new checkpoint.

## Verified repository identity

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`; origin `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Verified `origin/main`: `f42f9dbdd54809df202a81b4aa59ed0d1f377a2e`; P1.1A branch base is exactly this commit.
- P1.1A source/test commit: `155a41d974754257afcb8ec78ada7fb2f454f058`, direct parent `f42f9dbdd54809df202a81b4aa59ed0d1f377a2e`.
- Draft PR #96 was opened against `main` from this branch after the two initial commits; it was unmerged and the branch head at creation was `0a343e50c944bea47d181fc8d8ba2e0c5cd0c7af`. The final head must always be read from the live PR after subsequent documentation updates.
- Branch: `feat/p1-1a-lod01-transition-fixture`. The implementation uses the existing `C:\Dev\sandbox-sim-dev` worktree. The pre-existing `stash@{0}` was preserved.
- Source commit paths: `game/scripts/experiments/lod01_transition_fixture.gd` (+ Godot UID), `game/tests/lod01_transition_tests.gd` (+ Godot UID), `scripts/validate.ps1`, and `scripts/validate.sh`.
- Documentation paths are added in the following commit on this same branch: this checkpoint, `docs/specs/P1-1A-LOD01-TRANSITION-FIXTURE.md`, `docs/status/CURRENT_STATUS.md`, `docs/status/CHANGELOG.md`, and `docs/checkpoints/INDEX.md`.
- No production scene, canonical SDF/ledger, production mesher, streamer, or F2-G1 files changed. `git diff origin/main -- game/scenes game/scripts/terrain` was empty.
- PR #87 remains closed without merge; its historical checkpoint files were preserved by the previously integrated documentation. PRs #92 and #95 remain the accepted integration history. No PR merge is authorized by this checkpoint.

## Decision and approval ledger

- Owner authorization: implement only the P1.1A experimental custom GDScript LOD0/1 transition fixture, deterministic transition tests, and benchmarks, using the approved R2 plan and original implementation prompt.
- In scope: a CPU-only bounded fixture and deterministic tests for globally anchored LOD0/LOD1 samples, selected fine/coarse interfaces, ledger replay, topology, normals, and benchmark observations.
- Out of scope and not implemented: P1.1B/C, production LOD selection or scene integration, streaming, persistence, networking, backend adoption, Voxel Tools/native execution, collision changes, or any F2-G1 protected-host operation.
- No owner GUI visual acceptance was requested or performed for this data-only fixture. No final performance or geometry thresholds were supplied; therefore measured values remain exploratory.
- Merge authorization: none. The intended PR is draft and must remain unmerged pending independent source review and separate owner decisions.

## Evidence ledger

### L0-L2 local validation

- Executor: implementation agent, in the designated Windows worktree.
- Engine: Godot `4.7.2.stable.official.ed1daf0bf`, executable `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`.
- Command: `$env:GODOT_BIN='C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'; & '.\scripts\validate.ps1'`.
- Result: exit 0, `VALIDATION_PASS: L0-L2`, 15,949 assertions and zero failures across 12 scripted suites. Suite counts: smoke 52; SDF 44; brushes 611; chunks 179; multi-region 7,634; terrain performance 11; history 842; viewport picker history 713; P1.1A transition fixture 5,583; end-to-end performance 251; concurrency 11; bootstrap structure 18.
- The log is local evidence at `%TEMP%\p1-1a-validate-final-20261020.log`; no CI run is claimed. Bootstrap validation expressly reports that rendered pixels are not assessed. The full test run is headless; it does not establish GUI appearance, GPU timing, upload completion, or owner acceptance.
- Environment recorded for exploratory timing: Windows 11 Pro build 22631; Intel Xeon E5-2690 v4 @ 2.60 GHz; 14 cores / 28 logical CPUs; approximately 64 GiB RAM.

### Deterministic geometry evidence

- LOD0 spacing is 0.5 world units and LOD1 spacing is 1.0. Shared positions are global-lattice anchored; negative coordinates use mathematical floor. LOD2 rejects explicitly because its 2-unit step does not tile the existing 3-unit chunk depth by an integer number of cells.
- The transition fixture builds one LOD1 cell using a conforming boundary triangulation and center-fan tetrahedra. It permits one to three non-opposing fine faces in any orientation; the opposite interfaces are coarse. It does not assemble a general world mosaic.
- Tests derive the production marching-tetrahedra face diagonals from the existing production tetrahedra and verify exact face triangulation for all six orientations at both resolutions. Deterministic plane tests cover a negative face, negative edge, negative corner, and positive corner; each supported interface's contour segment set equals its fine/coarse reference. Internal surface-edge incidence, winding, finite normalized normals, duplicate-position normal equality, and degenerate/duplicate triangle rejection are asserted.
- Additional tests cover signed-world lattice samples, canonical SDF v1 tunnel geometry near X=-16, synthetic cave-like geometry, a deterministic sub-grid feature that may disappear, concentrated ledger histories of 0/1/32/128/256 commands, a 256-command distributed history, snapshot validation/capacity, and stale request identity.
- A matched LOD0 (2x2x2 cells) and LOD1 (one cell) reference shares the same domain and six-tetrahedron scheme. At seed 424242, the latest run reported maximum absolute canonical-density residuals of LOD0 `0.00244372`, LOD1 `0.01061805`, and transition `0.00675345`; triangle counts were 40, 8, and 22. No owner-approved tolerance exists, so these are observations only.

### Exploratory CPU fixture benchmark

Each row is a 12-sample series (2 warmups), one CPU transition/reference cell, local headless process. `p99` with n=12 is effectively a near-maximum order statistic. Total build time includes normal computation; ArrayMesh timing is reported separately. Memory is only a packed vertex/normal plus per-sample payload estimate, not allocator/RSS peak.

| Ledger ops | Transition build p50/p95/p99 (ms) | LOD0 reference p50/p95/p99 (ms) | Transition sample / normal / ArrayMesh averages (ms) | Transition triangles / estimated payload |
|---:|---:|---:|---:|---:|
| 0 | 6.131 / 7.569 / 7.569 | 8.129 / 12.994 / 12.994 | 0.219 / 4.502 / 0.022 | 22 / 2,160 B |
| 1 | 5.726 / 11.656 / 11.656 | 10.001 / 14.703 / 14.703 | 0.184 / 5.529 / 0.023 | 32 / 2,880 B |
| 32 | 5.723 / 10.011 / 10.011 | 9.620 / 11.317 / 11.317 | 0.278 / 5.836 / 0.018 | 22 / 2,160 B |
| 128 | 11.576 / 25.952 / 25.952 | 18.678 / 28.434 / 28.434 | 0.537 / 11.794 / 0.026 | 22 / 2,160 B |
| 256 | 16.473 / 30.747 / 30.747 | 29.123 / 47.290 / 47.290 | 0.762 / 16.548 / 0.021 | 22 / 2,160 B |

These figures measure a deliberately small fixture, not region/chunk production meshing. They show history-dependent CPU cost and noisy outliers; no target-hardware, frame-time, GPU, upload-completion, peak-memory, or final budget claim is made.

## Architecture and recovery

- Current working state at checkpoint: source and documentation commits are on `feat/p1-1a-lod01-transition-fixture`, associated with [draft PR #96](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/96). The PR is unmerged. The final branch SHA should be read from the live PR after this checkpoint update is pushed.
- Reproduce: set `GODOT_BIN` to the pinned Godot 4.7.2 executable and run `scripts/validate.ps1` from the repository root. The LOD suite may also be invoked with `--headless --path game --script res://tests/lod01_transition_tests.gd`.
- Fixture implementation: `game/scripts/experiments/lod01_transition_fixture.gd`; tests and benchmark: `game/tests/lod01_transition_tests.gd`; scope/spec: `docs/specs/P1-1A-LOD01-TRANSITION-FIXTURE.md`.
- Known limits: one-cell templates only; finite fixture exterior intentionally open; no arbitrary neighboring-cell mosaic, adaptive selection, edit invalidation, worker result publication, production integration, or GPU/visual evidence. LOD2 remains unsupported. Very narrow features may disappear at the chosen samples. No approved geometry/performance budgets exist.
- No new defect was found in the implemented bounded template by the passing deterministic tests, but this is not an independent source review.
- Next action: request independent source review of PR #96. Owner GUI testing is not a substitute for the independent source review; no merge occurs without separate explicit authorization. Future P1.1B/C and native backend work require their own authorization.
- Protected environment holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
- Documentation updated: `CURRENT_STATUS.md`, `CHANGELOG.md`, and this checkpoint index entry. No decision register or ADR status changed.

## Event significance and decision

- Exact event: owner-authorized P1.1A implementation on verified post-PR-95 `main`, after the earlier Gate 0 blocker was resolved by the expressly authorized integration evidence; draft PR #96 was opened for independent review.
- Status: implementation and local L0-L2 validation passed; exact source/test commit is recorded above. Performance/geometric acceptance, visual behavior, independent review, and integration remain pending.
- This checkpoint is required because it records a newly authorized implementation slice and its test/measurement evidence, while preserving the distinction between a passing experiment and production readiness.
- Checkpoint index row: [INDEX](../checkpoints/INDEX.md).
