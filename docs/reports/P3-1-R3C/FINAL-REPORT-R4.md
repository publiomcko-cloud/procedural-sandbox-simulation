# P3.1 R3C — Final Corrective Performance Experiment (R4)

**Disposition: `P3_1_R3C_BLOCKED_WITH_EVIDENCE`**

The exactness and recovery evidence is positive, and the frozen adaptive cache-admission probe meets its separately preregistered overhead-reduction gate. The evaluator and end-to-end performance gates do not pass. Do not integrate R3C into production or treat these headless CPU results as a product performance acceptance.

## Identity, scope, and environment

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`.
- R3C branch: `bench/p3-1-r3c-adaptive-cache`.
- Final measured source and campaign identity: `a760597ea0cc4be6db24cee52f0da1c972103861`.
- Direct parent: `c1470651ea1a2200e85cecfd1aa3d083254d56c8`.
- R3B comparison source: `9ec3818e47b4f42027995b12e3d7a40a72cbf7ca`; R3B evidence PR #138 remains open, draft, and unmerged at `2b9edfab41fe5ad67f767a36aae0263f1e28e683`.
- Production baseline: `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.
- R3C manifest SHA-256: `0facbab3b76bdbee78741d02f57bc8c631c3610cfb8758fd42ac868855a0ee03`.
- R3C `SHA256SUMS.txt` SHA-256: `cd0026a32e50c24a8af3bec41044bbbdb4a7aa859754aeffd3ab1b0aa141200b`.
- Evidence inventory: `docs/reports/P3-1-R3C/evidence/SHA256SUMS.txt`, 626 entries, SHA-256 `d370fa943b740249d74424f2a6ff4cecba156cb460585ab1e0b7d291db997428`.
- Physical source hashes at the measured HEAD:

| File | SHA-256 | Git blob |
|---|---|---|
| `game/tests/prototypes/r3c_exact_replay.gd` | `5b9cbf39a1b42d1438f3bc14272c9063febb84f6b80df2879b38167b8080356e` | `6b8135438e182390579454be46cf1591b22f87e1` |
| `game/tests/prototypes/r3c_profile_cache.gd` | `d95f220f42763654c9c1227d3bb887b015c62df6d9d7034aeca75ed7609a3125` | `b4e58779dca914207692036552482307007bcb37` |
| `game/tests/prototypes/r3c_cache_tests.gd` | `0dcba84cf8d8d6c578ec2bad0497a8224b31633e68f1e7c2b93b38e9c6f2eb80` | `ae26d405820eb01a701b84f41720dd5710b8e15a` |
| `game/tests/prototypes/r3c_cache_writer.gd` | `be9e137c6f5ca7d5166882440783f645a28007e1bc7132fd6e3d9ab0400d7d51` | `5c5aca9ccc390c208655c450a8b332691ccd3518` |
| `game/tests/prototypes/p3_1_r3c_benchmark.gd` | `7ee1fbc7f7610186ad4b365740b681bb51322ff70afdb2623f7cf1a1faeafc10` | `3fc7009da11133250507dc91899af0aac610f908` |
- Godot launcher: `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`, SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- Child engine image: `C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe`, SHA-256 `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`. Both report `4.7.2.stable.official.ed1daf0bf`.
- Reference host (as recorded by the R3B report): Windows 11 Pro 22631, Intel Xeon E5-2690 v4, 14 cores/28 logical CPUs, 64 GiB RAM, GeForce GTX 1050 Ti with 4 GiB reported VRAM. The host was shared; background load is a measurement limitation.
- Campaign root: `C:\Users\PUBLI\AppData\Local\Temp\p31-r3c-final-a760597ea0cc4be6`. The retained copy is `docs/reports/P3-1-R3C/evidence/final-campaign-r4/`.
- Scope remained experimental. No production source, schema, user save, PR #138, Issue #108, or F2-G1 protected state was changed.

The final campaign used the frozen eight R3B workloads and eight R3C nonperiodic workloads, five sequential process reservations each (80 total). Every process record is attributed to the pinned Godot child image through CIM parent/child and image verification. The runner's raw records remain unchanged.

## Process disposition and exactness

There are 80 unique process/run records: 76 completed with exit code 0 and a valid `PASS` result, and four retained `FAIL_RETAINED` records with null exit code, no result JSONL, and elapsed durations between 900.6 and 900.8 seconds. The runner's configured limit is 900 seconds. For derived analysis only, those four are right-censored timeout observations; the raw process status is not rewritten. All four are repeats R01/R03/R04/R05 of `NONPERIODIC-CONCENTRATED-8192`; R02 completed. No process was retried.

Across the 76 completed results:

- 0 density/query mismatches, 0 normal mismatches, 0 picker mismatches.
- Exact LOD0 and LOD1 mesh equality is recorded for every completed result.
- Every completed result has `status=PASS` and zero reported failures.
- Exactness preflight: 517 assertions, 0 failures; 4,106 density probes, 48 normals and 6 picker comparisons. It also recorded 2,424,713 pruned no-op decisions in its focused workload.
- Cache/recovery suite: 37 assertions, including corruption fallback, interrupted/temporary-file behavior, concurrent same-key writers, and exact canonical fallback.
- Frozen fixture digest checks: 8 assertions, 0 failures.

This is exactness evidence for the completed synthetic workloads and tested coordinates. It does not establish a formal proof for all possible float values, all machines, or production integration.

## Re-evaluation of the unchanged R3B gates

Ratios below are the median across valid paired processes of candidate LOD1 p50 divided by canonical LOD1 p50. A value below 1 is faster. The gate is at least 4/5 runs at ratio `<=1.10`, except concentrated N8192, which requires all 5 at `<=0.50`. Cold overhead uses the frozen formula `cache_first_lookup / (canonical LOD1 p50 + serialization) - 1`; fresh disk-hit percentage is the median disk-hit time divided by the cold lookup time.

| Frozen workload | Valid/5 | LOD1 ratio median | Runs meeting LOD1 rule | Cold overhead | Disk hit / cold | Result |
|---|---:|---:|---:|---:|---:|---|
| Concentrated 256 | 5/5 | 7.188x | 0/5 of 4 required | -4.16% | 0.79% | Fail LOD1 |
| Concentrated 640 | 5/5 | 8.778x | 0/5 of 4 required | 6.54% | 0.64% | Fail LOD1 |
| Concentrated 2,048 | 5/5 | 1.179x | 1/5 of 4 required | -3.13% | 0.74% | Fail LOD1 |
| Concentrated 8,192 | 5/5 | 0.331x | 5/5 of 5 required | 4.34% | 0.80% | Pass speed gate (~3.02x) |
| Distributed 256 | 5/5 | 0.993x | 5/5 of 4 required | 17.83% | 0.83% | Fail cold overhead |
| Distributed 640 | 5/5 | 1.043x | 5/5 of 4 required | 12.93% | 0.81% | Fail cold overhead |
| Distributed 2,048 | 5/5 | 1.094x | 3/5 of 4 required | 11.79% | 0.83% | Fail LOD1 and cold overhead |
| Distributed 8,192 | 5/5 | 1.041x | 5/5 of 4 required | 27.37% | 0.74% | Fail cold overhead |

Fresh-process disk hits remain below the 50% limit in all eight cases. Exact remote-snapshot hits, local-dependency invalidation, and corruption fallback passed. The original concentrated N8192 acceleration therefore remains useful, but the R3C evaluator does not preserve the prior matrix's broad non-regression behavior. LOD0 ratios are also retained in `scenario-summary.csv`; they show regressions in the smaller concentrated and distributed sets, although the preregistered speed gate is expressed for LOD1.

## New R3C nonperiodic gates

The frozen rule requires at least 20% LOD1 improvement (ratio `<=0.80`) in at least 4/5 concentrated N8192 runs. Each of the other seven scenarios must stay within 10% (ratio `<=1.10`) in at least 4/5 runs.

| Nonperiodic workload | Valid/5 | LOD1 ratio median | Runs meeting applicable rule | Cold overhead | Disk hit / cold | Result |
|---|---:|---:|---:|---:|---:|---|
| Concentrated 256 | 5/5 | 8.419x | 0/5 of 4 required | 2.96% | 0.42% | Fail non-regression |
| Concentrated 640 | 5/5 | 9.436x | 0/5 of 4 required | -0.32% | 0.30% | Fail non-regression |
| Concentrated 2,048 | 5/5 | 10.144x | 0/5 of 4 required | -1.26% | 0.20% | Fail non-regression |
| Concentrated 8,192 | 1/5 | 10.421x | 0/1 valid; 4 right-censored | Not available (R01 censored) | Not computable (cold R01 denominator absent; R02–R05 disk-hit median 39,457 us) | Fail; insufficient repetitions and completed run is slower |
| Distributed 256 | 5/5 | 1.276x | 0/5 of 4 required | 6.32% | 0.89% | Fail non-regression |
| Distributed 640 | 5/5 | 1.481x | 0/5 of 4 required | 18.67% | 0.79% | Fail non-regression and cold overhead |
| Distributed 2,048 | 5/5 | 2.567x | 0/5 of 4 required | 6.17% | 0.75% | Fail non-regression |
| Distributed 8,192 | 5/5 | 6.056x | 0/5 of 4 required | -0.28% | 0.55% | Fail non-regression |

The sole completed concentrated-N8192 result is R02: canonical LOD1 p50 `21,981,594 us`, candidate p50 `229,059,357 us` (10.42x slower), total scenario duration `897,041,738 us`, 8,192 ordered operations, 55,367 exact distance evaluations and 6,891,449 proven no-op operations skipped. Its query, normal, picker and LOD mesh comparisons are exact. Four other repeats were censored, so the 4/5 improvement gate is unambiguously not met.

## Adaptive cache admission and resource observations

The one frozen R=0 adaptive probe (`NONPERIODIC-DISTRIBUTED-256`) met its separate 25% overhead-reduction condition. The five paired reductions were 13.038%, 71.889%, 77.065%, 72.406%, and 70.709%. The preregistered comparison is calculated from median paired overheads: median unconditional overhead `16,896 us`, median policy overhead `4,949 us`, reduction `70.709%`. All five policy meshes were exact, each recorded one bypass and zero policy disk bytes. This isolated policy result does not counter the evaluator regression gates.

The final cache inventory contains 190 immutable cache objects and `33,804,808` bytes total (`campaign-integrity.json`, `cache-inventory.csv`). The largest scenario cache is 11,400,448 bytes; all reported per-scenario cache payloads are within the prototype quotas. Maximum sampled child working set was `250,834,944` bytes and private bytes `206,344,192` bytes. These are 100 ms process samples, not allocator/RAM ceilings. Per-run and per-scenario timing, cache, replay and memory fields remain in the JSONL/CSV evidence; no FPS, presented-frame, GPU-completion, or rendered-gameplay claim is made.

## Root cause and recommendation

The exact dominance pruning removes many Euclidean brush-distance calculations, but each sample still visits the ordered operation stream and invokes `_operator_is_proven_noop` for each operation. The per-operation branch/helper and bound calculation overhead overwhelms the saved distance calls for histories without a proven repeated period. The nonperiodic N8192 result makes this directly measurable: 6.95 million operation visits, 55 thousand distance evaluations, yet LOD1 is 10.42x slower. The same mechanism explains the 7–10x concentrated regressions at 256–2,048 and distributed nonperiodic regressions.

Do not integrate this R3C evaluator. Preserve R3B's exact-period shortcut where it passed, and design any next experiment around reducing per-operation interpreter overhead while preserving global CARVE/FILL order and canonical fallback. A candidate must be profiled before another final campaign; no post-hoc source change or rerun is represented by this report. The R=0 cache admission branch is promising as a separate measured policy, but it is not a production cache decision by itself.

## Validation and evidence

- Full `scripts/validate.ps1` on exact source `a760597...`: exit 0, `VALIDATION_PASS`, 21 assertion-bearing groups, 21,464 assertions, zero assertion failures. Godot 4.7.2 pinned version. `canonical-validation/validate.full.log` and `exit-code.txt` retain complete output.
- The validation log records the platform's unavailable junction fixture (`DirAccess.create_link returned Failed`) and non-fatal colinear camera target/up warnings; validation explicitly says rendered pixels are not assessed.
- Focused parser, fixture-digest, exactness, cache/recovery, and campaign preflight outputs are retained under `focused-preflight/`, `focused-exactness/`, and `final-campaign-r4-preflight/`.
- All 80 run folders preserve `process.json`, `command.json`, stdout, stderr, and result JSONL when completed. Four timeout/censored attempts have no result file and remain visible as attempts, not discarded.
- `campaign.json`, `results.jsonl`, `results.csv`, `run-summary.csv`, `scenario-summary.csv`, `cache-inventory.csv`, and the summary-generation script accompany the raw runs. See the evidence SHA-256 inventory in `evidence/SHA256SUMS.txt`.
- Earlier preflight/launch failures and exploratory nonperiodic profiling attempts remain preserved under `evidence/`; they are not final campaign samples.

The campaign is headless CPU measurement on a shared host. It does not establish GPU performance, frame pacing, VRAM, visual quality, or product acceptance. This blocked result preserves all five F2-G1 holds and authorizes no production integration, merge, or Issue #108 work.
