# P3.1 Integration Gate — Issue #131

Date: 2026-10-26

Disposition: `P3_1_INTEGRATION_GATE_PERFORMANCE_BLOCKED_WITH_EVIDENCE`
Evidence PR: [#134](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/134), draft and unmerged, stacked on PR #129's branch.

## Pinned identity

- Repository: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Main at preflight: `5997a76d345f45bf86edfe83f690336391e8be27`.
- PR #129: open/draft/unmerged; exact tested production HEAD `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.
- Benchmark evidence/test commit: `e70475d7c32661568f3319658eb8347777677b34`, direct parent `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.
- Worktree branch: `bench/p3-1-issue131-integration-gate`; isolated path `C:\Dev\sandbox-sim-p3-1-issue131-benchmark`.
- The later documentation-only commit on this branch records this checkpoint and current state; the benchmark/test commit remains the exact source for measured code. Verify PR #134's live head before further action.
- PR #129 production source, saves, PRs #128/#130, the development workspace, stashes and pre-existing untracked files were not modified. No production runtime code changed.

## Work and evidence

Added an opt-in GDScript-only benchmark writing exclusively to a caller-specified empty disposable directory; added test-only in-game frame-delta reporting to the existing E2E test and published machine-readable results, raw logs, deterministic input lists, SHA-256 manifest/index, environment, recovery record and graphs. The production storage, entity, mod and terrain code remain unchanged.

On Godot `4.7.2.stable.official.ed1daf0bf` (binary SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`), the final all-phase headless run exited 0: 50 edit rows (five runs × two layouts × five operation counts), 20 population rows (five repetitions for each of 100/500/1,000/2,000 requested milestones), and one 98-command entity/restart sequence. Every result row passed; indexed-vs-full ordered-SDF mismatch count was zero. Five windowed end-to-end runs each passed 251 assertions. `scripts/validate.ps1` completed with exit 0 and 21,464 assertions / zero failures, including 3,516 terrain-v2 storage assertions.

Measurements show performance blockers: concentrated 8,192-operation histories reach 8,192 query candidates and LOD1 CPU construction p50 6.89 s (distributed p50 122 ms); windowed initial-stream frame-loop p99 is 146.6–150 ms; 256-edit accepted-to-visible latency is 119.6–140.0 ms; entity action p95 reaches 513 ms in the one small command scenario. Population threshold publication produced actual cumulative counts 103, 500, 1,001 and 2,002; at most 25 regions and 122 instances were resident. These are exploratory, UNSCORED results; no GPU completion or OS-present timestamp was available.

The final harness JSON's embedded `source_sha` was empty because `P31_SOURCE_SHA` was omitted at launch. Raw results were preserved, and independent attribution binds the run to production SHA, exact test-file hashes, process command/PIDs, manifest digest, output root and timestamps in `results/run-attribution.json`.

## Decision and limits

Recommend optimizing dense local candidate evaluation, LOD1 CPU meshing and durable command/save paths before Issue #108. Do not adopt persistent mesh caches or volumetric snapshots from these results alone. A mesh cache needs a complete ordered-revision and neighbor-dependency key; a volume snapshot risks changing continuous ordered min/max SDF semantics unless exact parity is proven. No backend, snapshot, cache, production optimization, issue #108, merge, release or GUI acceptance is authorized by this checkpoint.

Issue #133 remains `NOT_REPRODUCED / CAUSE_UNKNOWN`. The five F2-G1 holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

Full report: [P3.1 Integration Gate report](../reports/P3-1-ISSUE-131/integration-gate-report.md). PR #134 must receive independent source/evidence review; PR #129 remains separately draft and unmerged.
