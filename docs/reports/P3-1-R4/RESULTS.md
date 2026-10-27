# P3.1 R4 — Subledger and Incremental Voxel Materialization Results

**Disposition:** `P3_1_R4_READY_FOR_INDEPENDENT_REVIEW` — experiment complete; this is not production acceptance.

## Identity and scope

- Repository: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Reused worktree: `C:\Dev\sandbox-sim-p3-1-r4-subledger-snapshots`
- Branch: `bench/p3-1-r4-subledger-snapshots`
- Production baseline: `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`
- Campaign source SHA: `83c7c091bcec0d10534d8638225d3d24d94b6334`
- Live `main` observed during finalization: `5997a76d345f45bf86edfe83f690336391e8be27`
- Engine: Godot `4.7.2.stable.official.ed1daf0bf`, SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`
- Frozen 90-row scenario manifest SHA-256: `c6fd895685304795101968ed1104385d31c3f4b1cf303fb26582b16a22666c31`

Only test/benchmark prototypes and their reporting/documentation changed. No production terrain, ledger, save schema, PR #129, other PR, or Issue #108 source was changed. The global schema-v2 ledger remained the only authority; A/B/C outputs were disposable derived projections.

## Campaign evidence and correction

The final campaign launched 90 fresh Godot processes: 18 frozen scenario IDs × five independent process repeats. All 90 result records have `PASS`, exit 0, matching source/input identity and verified result-file hashes. There were no timeouts or unrun campaign rows. The campaign produced 1,230 arm/resolution metric rows and 246 scenario/arm/resolution groups. A total of 560 subledger, voxel-snapshot and mesh-cache files were independently rehashed against their recorded digests.

The original raw files remain byte-for-byte archived. The original campaign CSV summarizer is retained as historical output but is superseded: it incorrectly dereferenced nested JSON objects as dictionaries, yielding empty B/C and picker measurements; the Godot picker summary also appended to a temporary packed-array copy. Its top-level storage count omitted nested files, and the launcher process working set was mislabeled as process memory. `Export-P31R4DerivedMetrics.ps1` now revalidates the 90 result hashes, recomputes recursive storage bytes, reads nested object properties explicitly, derives picker percentiles from raw ray durations, verifies 560 artifact files, and labels launcher working set separately from Godot allocator delta. Engine OS RSS is `NOT_MEASURED`.

The corrected evidence is in [the R5 derived report](evidence/final-r4/derived-report-r5/). The raw campaign, including both original and corrected exports, is retained in [final-campaign-raw.zip](evidence/final-r4/final-campaign-raw.zip). The outer evidence index is [evidence-index.csv](evidence/final-r4/evidence-index.csv). The archive SHA-256 is `06398da449df934a286312cd05ba90e0303327fb3ab475c20f2820e785d83d83`. R5's integrity manifest records these hashes: `metrics-per-run.corrected.csv` `b9dd771dc3aececf406fd81b8f4f5681ab2b5e8f552022baee342588122e706c`; `scenario-summary.corrected.csv` `aaeafc530b949d52955c68a83c79b5a521604af01b0edd29db5b4af574fd2ad2`; `artifact-integrity.csv` `bdfe4f3bf5bee5263454a02703f990e17f6f1f53ca4a266d4baf52d04e2f06fc`; and `integrity.json` `049d0c9109072dfe66937ade6d6846733fea386d8417abc0f1965a189c4037ae`. The R5 file sizes and source/manifest identities are recorded in `derived-report-r5/integrity.json`; the outer index covers the copied report, logs, profile marker, and raw archive.

## Architecture outcomes

### A — exact chunk subledger

The projection preserves global operation sequence and the canonical min/max query semantics, including conservative dependencies outside an operation's immediate geometric support. Across all 90 rows, the harness reported exact in-domain density probes and bitwise-identical LOD0/LOD1 mesh arrays for A versus the canonical path. Each run includes 64 density probes, for 5,760 exact probe comparisons in the campaign. Corruption, append-prefix, restart and reconstruction checks are part of the passing harness.

For the frozen 8,192 concentrated R3B row, the median across five process measurements was: projection build 99.374 ms; local append 1.650 ms; persist 21.484 ms; reload 6.142 ms; projected-query p95 0.940 ms versus canonical-query p95 0.969 ms; projected LOD0 1.909 s versus canonical LOD0 1.854 s; projected LOD1 6.629 s versus canonical LOD1 6.702 s. The projection kept exact geometry, but the preregistered no-more-than-10% p95 meshing-regression screen is not met consistently: the measured LOD0 p95 across five process runs exceeded that limit on several rows, including concentrated 256/640 workloads. A therefore remains promising exact local-work infrastructure but does **not** pass the complete exploratory adoption screen.

### B/C — float32 voxel snapshot and combined cache

B/C are approximate, resolution-matched experiments at voxel spacing 0.5/0.25/0.125 according to the frozen schedule. They are not equivalent to the continuous canonical SDF, and no owner geometry tolerance exists. On concentrated R3B N8192 at spacing 0.5, median-of-five materialization was 1.712 s (B) and 1.693 s (C); LOD0 CPU mesh generation was about 22 ms and LOD1 about 92 ms. The corresponding median per-process surface-distance p95 was 0.0674 and 0.0540 world units, with normal-angle p95 about 16.2° and 47.8° for LOD0/LOD1. These faster meshes are lower fidelity, not a like-for-like production speedup.

The nonperiodic concentrated N8192 case exposes the risk more clearly: spacing-0.5 surface-distance p95 was about 0.517/0.638 world units and normal-angle p95 about 119°/135° for LOD0/LOD1. B/C cannot be adopted as production terrain, cave, tunnel, picker or collision representations under the current exactness contract.

C's dependency-keyed cache produced warm in-memory retrieval around 43–51 µs and fresh-instance disk retrieval around 1.06–2.21 ms in the selected 8,192 rows. Those are one lookup per process, summarized across five processes; they are not input-to-frame measurements. The cache stores derived data only. The on-disk cache and snapshot bytes are reported separately from subledger storage.

The synthetic entity-view arm remains a sequential logical-sharing model. It does not establish thread safety, production entity persistence, multiplayer safety or durable multi-writer behavior.

## Validation

- Godot R4 architecture tests: 201 assertions, zero failures.
- Full `scripts/validate.ps1`: exit 0, 21 groups, 21,464 assertions, zero failures under the pinned Godot build and an isolated profile.
- Benchmark and reporting PowerShell scripts: Windows PowerShell 5.1 parsing passed; the offline metric exporter completed under both PowerShell 7 and Windows PowerShell 5.1 with 90 rows, 1,230 metrics, 246 groups and 560 checked artifacts.
- R4 benchmark script: Godot `--check-only` passed after the collection fixes.

An initial full validation against the normal user profile failed two declarative-package assertions with `duplicate_mod_id`; it was stopped and preserved without deleting or changing mods/saves. The definitive run used isolated `APPDATA`, `LOCALAPPDATA`, `TEMP` and `TMP` roots and passed. The isolated full suite emitted `ISSUE118_REPARSE_FIXTURE_UNAVAILABLE` because `DirAccess.create_link` could not create the junction fixture; that low-level Windows reparse subtest is unavailable in this run. The profile marker and both logs are preserved in the evidence directory. No GUI or rendered-pixel acceptance is claimed.

## Recommendation and limits

Keep the global ordered ledger authoritative. Continue evaluating A only as an exact projection/cache layer, with a focused LOD0 regression investigation before any production proposal. Do not adopt B or C geometry without a separately approved geometric error contract and proof that required caves/tunnels/picking behavior are preserved. This campaign measured headless CPU/filesystem paths, not rendered FPS, GPU completion, VRAM or Godot engine OS RSS. The host had an unrelated long-running Godot process during campaign execution; host contention may affect timing, so all performance values are exploratory and should be independently reviewed. Owner GUI review, independent exact-SHA review and a separate architecture decision remain outstanding.

All five F2-G1 holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
