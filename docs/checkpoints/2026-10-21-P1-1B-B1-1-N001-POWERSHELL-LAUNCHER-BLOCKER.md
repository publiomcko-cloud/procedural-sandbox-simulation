# CHK-2026-10-21-P1-1B-B1-1-N001-POWERSHELL-LAUNCHER-BLOCKER

**Event date:** 2026-10-21, America/Sao_Paulo.
**Type:** significant execution blocker, *outside the application under test*; evidence and recovery handoff.
**State at observation:** `N001_STAGE_A_NOT_EXECUTED / POWERSHELL_ARGUMENT_FORWARDING_BLOCKED / R7_SOURCE_UNCHANGED / N001_NOT_RUN`.
**Publication:** prepared on existing separate docs-only PR #101 (draft/unmerged), NOT yet integrated.
**Historical checkpoint rule:** preserve [prior N000 successful checkpoint](2026-10-21-P1-1B-B1-1-R7-N000-FIRST-UNSCORED-PASS.md) unchanged. The R7 N000 PASS remains a prior developer-reported result; it does not imply N001 ran.

## Verified GitHub identity and scope

- Repo `publiomcko-cloud/procedural-sandbox-simulation`. Verified remote `main`: `ea4422d90726d3f2fe6d5cef097126268f93685a`.
- [Feature PR #99](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99) open/draft/unmerged at `2b4355363a43b73476715cf4002e31575bf9828d`; direct parent `5b3a8f735038ba4ba8d98ae3c24d44d53262d4dd`. No source change in the N001 attempt.
- [Docs PR #100](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/100) independent roadmap draft, unmodified. This new checkpoint is on documentation-only PR #101.
- Frozen B0 manifest `game/tests/fixtures/p1_1b_b0_manifest.json`, source Git blob `fde2ff84e2754cfef48052b32998903f45276aa1`, expected physical SHA-256 `bcf49351436f46bae0512573a77d99e662430bfe65917ebadebcf96264a1aecd`; sidecar matches, per reported preflight.
- Attempted target: `B0A.INTERIOR.N001.v1`, type `ledger_replay`, status `FROZEN`, exactly **one** ordered canonical ledger command. Manifest values confirmed from reviewed GitHub source in prior checkpoint.
- Godot executable pinned externally: `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`, SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`; this preflight reportedly matched.

## Stage ledger: what actually ran versus what was blocked

The owner/Codex reports that a Windows PowerShell helper declared a parameter named `Args`, conflicting with the automatic variable `$Args`. Its invocation path forwarded **an empty argument vector** to the Godot binary.

- Intended Stage A: Godot `--headless --path ./game --editor --import`.
- Actual observed Stage A: launched Godot with **zero arguments**, rather than the authorized import command. The process chain was documented and terminated. **Authorized import: NOT_EXECUTED**; exit code **NOT_CAPTURED / UNKNOWN**. Do NOT label this as import exit 0 or import exit 1, and do not infer an engine failure.
- Stage B `--check-only`: **NOT_RUN**.
- Stage C R7 contract suite (previous N000 validation reportedly had **2,586 assertions / 0 failures**, 11 groups): **NOT_RUN** in this N001 attempt.
- Stage D `B0A.INTERIOR.N001.v1`: **NOT_RUN**; zero validated N001 JSONL, zero accepted edits, no N001 performance results.
- **No retry** performed and no scenario run launched, per owner/Codex report. Disposable checkout lacks class cache and has no tracked changes.
- This is a **launcher/preflight failure** in the host-side execution method, not a new demonstrated defect of Godot source, R7 harness, frozen manifest or N001 ledger operation.

**Evidence custody:** host-local directory `C:\Users\PUBLI\AppData\Local\Temp\p1_1b_n001_d50be783e8e44f60bfb4eb3ab6fe843d_evidence` reportedly contains `preflight.json`, `import.stdout.log`, `import.stderr.log`, `import.result.json`, `unexpected_process_chain.json`, `integrity.json`, `validation_summary.md` and `evidence_artifact_hashes.json`.

**Evidence grading:** GitHub source/PR/manifest identity were reviewed independently. No access to local Windows PowerShell helper implementation, its original argument transcript, or host logs is available to this remote reviewer. The collision cause and process evidence are **Codex-reported**, not independently replayed. The prior N000 host-PID relationship remains unproved; avoid claiming any Windows process PID mapping without observation.

## Recovery / next bounded gate

1. **Do not modify tracked project sources, PR #99, the manifest or CI to fix a host-side PowerShell helper.**
2. In a new evidence directory, inspect/correct the local invocation helper: use `GodotArguments` or `ArgumentList`, never the automatic `$Args` identifier; alternatively bypass the helper and invoke the pinned executable with explicit positional arguments. **Before spawning any Godot process**, verify the exact non-empty ordered argument vector for each stage; fail closed on empty/mismatched tokens or paths. Exercise local argument-building with a no-Godot dry-run. Prevent accidental GUI Godot launch.
3. Use fresh disposable exact-R7-SHA checkout and isolated Godot user-data profile. Under standing Godot permission, perform A import, B harness check-only, C R7 contracts, then only on all PASS **one** frozen N001 `UNSCORED`. Capture complete stdout/stderr, actual exit codes, class cache, version and hash, process IDs/parents and serialized argv where available; no automatic retry after failure.
4. Acceptance of N001 requires one accepted canonical command, revision and last sequence 1, matching command-list hash, signed support/rebuild/dependency sets, full versus filtered SDF parity, one scenario start and one terminal scenario_complete PASS, zero failures, exit 0. **N000 was already run; do not rerun it as a substitute.**
5. Keep PowerShell launcher PID versus Godot event PID provenance `UNKNOWN` until evidence establishes the relation; do not attribute OS CPU/RSS/VRAM metrics to the wrong PID.
6. Preserve all old evidence, the ordinary Windows development worktree, its three pre-existing untracked `.gd.uid` hashes and `stash@{0}`. No native Voxel Tools or protected-host operations, no other scenario, no scored benchmarks and **no PR merge**. Preserve all five holds `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

[PR #99 independent reviewer disposition](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/99#issuecomment-6324286249) records this execution boundary.

This checkpoint amends neither approved B0 scenario definitions nor any execution authorization. It is new evidence; no decision-register change or merge changelog entry is required. Future results require their own later checkpoint if material.
