# P3.1 R3B — Exact Dense SDF and Localized Mesh Cache

**Disposition: `P3_1_R3B_BLOCKED_WITH_EVIDENCE`**

This isolated experiment preserves exact canonical geometry and demonstrates a useful concentrated-history replay reduction and fast derived-cache hits. Two preregistered performance gates did not pass. It is not ready to recommend production integration.

## Identity and scope

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`, origin verified as `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.
- Production baseline: `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.
- Experiment branch: `bench/p3-1-r3b-exact-dense-local-cache` in an isolated worktree.
- Source used for final measurements: `9ec3818e47b4f42027995b12e3d7a40a72cbf7ca`.
- Implementation commit chain from the pinned baseline: `7548e680` → `ce30c02e` → `ca599e0c` → `9ec3818e`.
- No production file, save schema, user save, PR #129/#134/#136/#137, Issue #108, or F2-G1 state was modified.
- The exact Issue #131 frozen inputs were reused. Manifest SHA-256: `2dff9ccd5b98e1ea722051b25f961ff8f64c3ae698f3bc12102826e04ec3088d`; `SHA256SUMS.txt` SHA-256: `ac8a00cee024815dc55551c0ed5011ea2e9034d499b7846f7cf59b9b446d2be1`.

## Method and environment

The final campaign ran five independent Godot processes per each of eight frozen scenarios: 256, 640, 2,048 and 8,192 commands, each concentrated and distributed (40 processes total). It paired the production canonical SDF/LOD builders with the R3B evaluator and derived cache. Query order was alternated and mesh timing order counterbalanced. Results report per-process p50/p95/p99 and summarize the five processes separately; no cross-scenario pooled percentile is used.

Hardware: Windows 11 Pro 22631, Intel Xeon E5-2690 v4 (14 cores / 28 logical CPUs), 64 GiB RAM, NVIDIA GeForce GTX 1050 Ti (4 GiB reported VRAM). Godot launcher `Godot_v4.7.2-stable_win64_console.exe`, SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`; actual child engine image `Godot_v4.7.2-stable_win64.exe`, SHA-256 `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`. Both report `4.7.2.stable.official.ed1daf0bf`. All 40 launcher records confirm wrapper→engine parent/child, command line, engine version and image hash. An unrelated Godot process was already active on the shared host during earlier R3A measurement and remained outside this work; it was not touched. This is a shared-host-load limitation.

## Exactness and function

The canonical oracle is production SDF v1 plus `SdfBrushEditState.sample_density_snapshot()` over the original packed snapshot and ordered CARVE/FILL stream. The R3B evaluator uses exact binary equality for brush geometry, KMP to find a complete exact operation period, and reduces only duplicate complete periods; order and tail remain intact. If a history has no safe repeated period, it selects the canonical evaluator rather than approximating or reordering.

- Final campaign: 40/40 results `PASS`, 40/40 child-process identities verified, zero process exits other than 0, zero timeouts, zero reported failures, zero bitwise density mismatches, and exact LOD0/LOD1 mesh-array comparisons for every run.
- Exact concentrated 8,192 case: a 2,002-operation repeated period plus 184-operation tail evaluates 2,186 replay operations; it retains the original 8,192-command authority. All five LOD1 paired speedups exceeded 2× (2.921×–3.005×, median 2.984×). LOD1 median p50 was 6.566 s canonical vs 2.206 s optimized; query median p50 was 915 µs vs 302 µs.
- Other histories used the canonical fallback when no exact repeated-period reduction was proven. Geometry remains exact; the fallback does not claim a speedup.
- Focused exact replay/cache suite: **22,471 assertions, zero failures** on the implementation at source SHA `9ec3818e…`.
- Full `scripts/validate.ps1`: **21 groups, 21,464 assertions, zero failures**, exit 0 and `VALIDATION_PASS`, on source SHA `9ec3818e…`, with a fresh isolated Godot profile. It logged the existing unavailable Windows junction fixture (`DirAccess.create_link returned Failed`) and three non-fatal colinear camera target/up warnings. No rendered pixels were validated.

## Performance summary

Times below are microseconds. The table reports the median of five per-process p50/p95/p99 values. Full eight-scenario distributions, process ranges, all per-run values and raw records are in `evidence/campaign-02-final/scenario-percentiles.csv`, `campaign.json`, `results.csv`, `results.jsonl` and `runs/`.

| Scenario | Canonical query p50/p95/p99 | Canonical LOD1 p50/p95/p99 | R3B LOD1 p50/p95/p99 | Per-run LOD1 gate |
|---|---:|---:|---:|---|
| Concentrated 256 | 34 / 39 / 85 | 321,093 / 337,949 / 337,949 | 335,805 / 354,391 / 354,391 | Pass: 4/5 within 10% |
| Concentrated 640 | 76 / 165 / 263 | 661,273 / 709,770 / 709,770 | 664,800 / 705,335 / 705,335 | Pass: 5/5 |
| Concentrated 2,048 | 232 / 536 / 773 | 1,750,547 / 1,830,486 / 1,830,486 | 1,769,162 / 1,824,281 / 1,824,281 | Pass: 5/5 |
| Concentrated 8,192 | 915 / 974 / 2,098 | 6,565,796 / 6,647,435 / 6,647,435 | 2,205,595 / 2,258,509 / 2,258,509 | Pass: 5/5, each ≥2× faster |
| Distributed 256 | 34 / 44 / 68 | 107,391 / 110,594 / 110,594 | 103,386 / 107,815 / 107,815 | Pass: 5/5 |
| Distributed 640 | 76 / 87 / 162 | 102,686 / 106,130 / 106,130 | 103,593 / 108,903 / 108,903 | Pass: 5/5 |
| Distributed 2,048 | 231 / 247 / 302 | 102,933 / 104,250 / 104,250 | 103,084 / 103,698 / 103,698 | Pass: 5/5 |
| Distributed 8,192 | 913 / 1,015 / 2,058 | 103,198 / 109,425 / 109,425 | 105,949 / 113,865 / 113,865 | **Fail: 3/5 within 10%; two runs regressed 10.2% and 14.7%** |

One-run LOD builder phase breakdown is recorded for all scenarios in `phase-summary.csv`. For concentrated 8,192, canonical LOD1 median phases were SDF/ledger 943 ms, shared-gradient normals 5,496 ms, transition assembly 11 ms, triangulation/face normals 87 ms. Canonical LOD0 phases were SDF/ledger 1,289 ms, normals 540 ms, triangulation 8.9 ms. `ArrayMesh` build is separately measured; it is not included in CPU mesh generation. Serialization is also separately recorded. These are headless CPU timings, not GPU upload or presented-frame results.

### Cache results and failed experimental gates

R01 is the cold creation process per scenario; R02–R05 use the shared scenario cache and start from verified disk entries. The cache reports the first LOD1 lookup time, paired canonical LOD1 p50, and serialization time. Cold-overhead calculation is `(cold_lookup / (canonical_Lod1_p50 + measured_serialization)) - 1`.

| Scenario | Cold overhead | Fresh-process disk-hit median as % of cold | Result |
|---|---:|---:|---|
| Concentrated 256 | -3.6% | 0.7% | Pass |
| Concentrated 640 | 0.0% | 0.6% | Pass |
| Concentrated 2,048 | -2.5% | 0.7% | Pass |
| Concentrated 8,192 | 3.1% | 0.8% | Pass |
| Distributed 256 | 6.7% | 0.8% | Pass |
| Distributed 640 | 5.7% | 0.8% | Pass |
| Distributed 2,048 | **12.8%** | 0.8% | **Fail: >10% cold-overhead limit** |
| Distributed 8,192 | **12.9%** | 0.9% | **Fail: >10% cold-overhead limit** |

Every scenario recorded the expected first layer (`rebuilt` for R01, `disk` for R02–R05). The median disk hit was below 1% of the cold LOD1 lookup in all scenarios. Remote unchanged-snapshot lookups were cache hits; local dependency edits changed identity, missed and rebuilt the exact mesh; corruption and oversized-entry fallback passed the focused suite. Campaign cache inventory: 96 `.bin` entries, 18,206,528 bytes total across all eight scenario roots; maximum per scenario 11,400,448 bytes, below the prototype’s 64 MiB/128-file caps. Maximum measured in-memory serialized payload accounting was 68,768 bytes, below 16 MiB. Maximum child peak working set sampled at 100 ms was 247,967,744 bytes; private bytes peaked at 203,558,912 bytes. These process samples are not an allocator census or product budget.

The preregistered cache cold-overhead gate is **not met** for distributed 2,048 and 8,192. The preregistered LOD1 non-regression gate is **not met** for distributed 8,192 (3/5 repetitions meet the 10% limit; required 4/5). These are the reasons the result is blocked despite exactness and other cache gates passing. Thresholds were not changed, and no replacement runs were launched after observing them.

## Attempt history

- The first full campaign on `ca599e0ce5fe623eb2f683c4e8e975bca8c6958a` completed 40/40 functional runs, but `last_builder_usec` was always reported incorrectly because the benchmark closure did not preserve the cache-owned timing. It is retained under `evidence/campaign-01-invalid-builder-timing/` and excluded from final performance conclusions.
- The final campaign on `9ec3818e…` corrected the builder-timing ownership, verified in focused tests and smoke, then completed all 40 runs. This is the sole final performance dataset.
- Prior compile/focused smoke failures and their subsequent corrections are preserved in git history and earlier disposable logs; they were pre-scenario harness defects, not accepted campaign samples.

## Architecture conclusion and limits

R3A A had reported a 6.502 s → 21.008 s concentrated-8,192 LOD1 regression; R3B's paired baseline was 6.566 s and its exact period reduction was 2.206 s (2.984× median speedup), addressing that specific case. This does not generalize to nonperiodic histories. R3A B's global-ledger invalidation problem is addressed experimentally by including only the exact dependency-complete local snapshot in the cache identity; remote edits hit and local edits miss in the tested fixtures. R3A C remains excluded because its continuous-field equivalence, normals and cave connectivity were not established.

The exact-period evaluator is a narrow optimization opportunity for histories containing repeated complete operation sequences. It does not change the ledger and falls back to the canonical evaluator otherwise. Its useful result is demonstrated only for the frozen concentrated 8,192 workload.

The localized derived cache demonstrably avoids recomputation for exact-key revisits and retains a cache hit after a remote operation that cannot affect the exact filtered chunk snapshot. Local dependency changes invalidate and rebuild. The prototype is not authoritative and cannot replace the schema-v2 operation ledger. Its cold-write path needs work before the frozen cache performance gate can be satisfied. The prototype assumes single-process writers; it has no cross-process lock and no power-loss durability claim. Cache-key serialization is pinned to this Godot version/platform and is not asserted as a cross-version/cross-platform canonical format. Caps count serialized cache payload and `.bin` entries, not total runtime allocator, filesystem metadata or OS cache usage. Cache I/O and CPU timings are host-specific.

R3A volumetric snapshots are not reconsidered: they remain outside this experiment because the earlier exactness issue is unresolved. No visual, GPU, frame-time, save/load world persistence, production integration, or Issue #108 result is claimed. Production recommendation: do not integrate R3B yet; retain the exact-period path as an independently reviewable experiment, optimize and retest the two failed performance gates, and separately review cache concurrency/crash-recovery requirements before any production proposal. All five F2-G1 holds remain unchanged.

## Evidence map

- `PREREGISTRATION.md`: frozen scenarios, exactness and experimental gates.
- `evidence/campaign-02-final/`: final 40 process records, raw stdout/stderr/JSONL, input command hashes, engine attribution, cache directory, summary CSVs and inventory.
- `evidence/campaign-01-invalid-builder-timing/`: preserved superseded campaign attempt.
- `evidence/focused-tests/`: import, check-only and 22,471-assertion exact/cache suite logs.
- `evidence/canonical-validation/final-head-9ec3818/`: final 21-group canonical validation log and exit code.
- `ARTIFACT_SHA256SUMS.txt`: checksum inventory of retained report inputs and evidence.
