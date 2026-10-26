# P3.1 R3B — Exact Dense SDF and Localized Mesh Cache Experiment

**Checkpoint ID/date/time:** `CHK-2026-10-26-P3-1-R3B-EXPERIMENT`; 2026-10-26 13:46 America/Sao_Paulo (16:46 UTC)

**Event type:** material benchmark result and blocked performance handoff

**Publication state:** recorded on isolated experiment branch; draft evidence PR publication pending; not integrated

**Immutable once integrated:** yes; later publication/review events require new records.

## Verified repository identity

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`; origin `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Live `origin/main` at check: `5997a76d345f45bf86edfe83f690336391e8be27`.
- P3.1 production source baseline requested for the prototype: PR #129 feature SHA `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`, direct parent `073e9959fc8585322ac7efc12261e6ecc2bc953c`. This SHA remains a draft PR candidate, not main.
- Isolated worktree: `C:\Dev\sandbox-sim-p3-1-r3b-experiment`; branch `bench/p3-1-r3b-exact-dense-local-cache`.
- Final source SHA used by both the 40-run campaign and final full validation: `9ec3818e47b4f42027995b12e3d7a40a72cbf7ca`; direct parent `ca599e0ce5fe623eb2f683c4e8e975bca8c6958a`.
- Concurrent PRs #129/#134/#136/#137 were read and verified open/draft; no changes were made to those branches, their states, actual user saves, or the original development workspaces. Issue #108 was not implemented.

## Authorization and scope

The owner authorized a separate R3B experiment only. Scope was isolated GDScript prototypes, frozen inputs, tests, benchmarks, evidence and documentation. No production path, save schema, main branch, user save, native dependency or protected F2-G1 state was changed. No merge or production adoption was authorized.

## Evidence ledger

- **L0:** exact origin, source ancestry, clean source baseline and concurrent PR identities checked before execution; exact source and artifact hashes are in `docs/reports/P3-1-R3B/SOURCE_INVENTORY.csv` and `ARTIFACT_SHA256SUMS.txt`.
- **L1/L2:** pinned Godot `4.7.2.stable.official.ed1daf0bf`; full `scripts/validate.ps1` on source SHA `9ec3818e…` passed 21 assertion groups, 21,464 assertions, 0 failures, exit 0, marker `VALIDATION_PASS`. Focused replay/cache suite passed 22,471 assertions, 0 failures, exit 0. Logs are retained under `docs/reports/P3-1-R3B/evidence/`.
- **L4:** 40 independent benchmark child processes across 8 frozen scenarios × 5 repetitions. Every row has zero process failure, exit 0, exact launcher-to-engine parent/child attribution, pinned engine image, exact source SHA, exact command input hash, zero density mismatches and exact LOD0/LOD1 mesh equality. Raw process JSON, stdout, stderr, JSONL, cache files, CSV and scenario percentile summaries are retained under `evidence/campaign-02-final/`.
- Campaign 1 on `ca599e0c…` and pre-final failed/invalid harness attempts are preserved separately and explicitly excluded from final performance conclusions. See `ATTEMPT_HISTORY.md`.
- No GUI, GPU completion, presented-frame, owner visual, independent rerun, production integration, or Issue #108 evidence is claimed.

## Findings and disposition

- Exact repeated-period replay preserved ordered CARVE/FILL output and produced zero exact density or mesh mismatches. For concentrated 8,192 operations, the period of 2,002 plus tail of 184 reduces evaluation to 2,186 operations; all five LOD1 runs were 2.921×–3.005× faster. Nonrepeating histories fall back to canonical replay.
- The cache's chunk identity includes the exact ordered local dependency snapshot and meshing dependencies; remote edits that leave that snapshot unchanged hit, local dependency edits miss/rebuild, corrupt entries rebuild, and disk/in-memory hits are exact. Cache is derived, not authoritative.
- **Performance gates fail:** distributed 8,192 optimized/canonical LOD1 p50 regression met the ≤10% allowance in 3/5 runs, not 4/5; first LOD1 cache cold overhead was 12.8% for distributed 2,048 and 12.9% for distributed 8,192, above the preregistered 10% bound. No repeat or threshold adjustment was made after seeing these results.
- Disposition: `P3_1_R3B_BLOCKED_WITH_EVIDENCE`. The exact optimization/cache prototypes are suitable for independent review as experimental evidence, but not for production integration.

## Environment and limits

Windows 11 Pro 22631; Intel Xeon E5-2690 v4, 14 cores/28 logical CPUs, 64 GiB RAM, NVIDIA GTX 1050 Ti 4 GiB. Godot launcher and engine executable hashes are pinned in `environment.json` and per-process records. An unrelated long-running Godot process remained on the shared host and was not modified. Maximum sampled benchmark-child working set was 247,967,744 bytes and private bytes 203,558,912 bytes. Cache inventory was 96 files / 18,206,528 bytes across the full campaign evidence root; per-run limits are prototype counters, not product-level memory or disk budgets. No GPU/FPS/product acceptance thresholds exist.

The cache prototype assumes single-process writers, has no cross-process lock or power-loss durability guarantee, and uses Godot serialization identity not promised stable across versions/platforms. The exact-period optimization only benefits repeated complete exact operator periods. R3A's inexact density lattice remains excluded; no R3B snapshot was implemented. Full details, gates, p50/p95/p99, phase timings, recommendations and artifact map are in the [report](../reports/P3-1-R3B/REPORT.md).

## Next authorized step

Independent exact-SHA source/evidence review of the isolated draft PR, followed by owner disposition of the two failed experimental gates. No production integration, schema change, Issue #108 implementation, PR merge or F2-G1 operation is authorized by this checkpoint. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT` and `F2_G1_RELEASE_HOLD`.
