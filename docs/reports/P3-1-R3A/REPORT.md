# P3.1 R3A — Comparative Ledger + Snapshot Prototype

Date: 2026-10-26<br>
Disposition: `P3_1_R3A_READY_FOR_INDEPENDENT_REVIEW`; experimental prototype only, owner architectural decision pending.<br>
Repository: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`<br>
Production baseline: `92b442d7f5b605c7bc9c48fac2aceea9d71813aa` (PR #129 source).<br>
Baseline direct parent: `073e9959fc8585322ac7efc12261e6ecc2bc953c`.<br>
Current `origin/main` at preflight: `5997a76d345f45bf86edfe83f690336391e8be27`.<br>
Worktree/branch: isolated `C:\Dev\sandbox-sim-p3-1-r3a-prototype`, `bench/p3-1-r3a-ledger-snapshots`; PR #129/#134 and user workspace not modified.

## Result summary

The final corrected experiment completed 9/9 rows with zero harness failures and 23/23 reference-artifact SHA checks. A's tested no-op pruning preserved tested SDF probes and mesh vertices, but was much slower on concentrated histories. B's content-keyed derived-mesh cache produced useful warm hits, particularly for selected concentrated cases, but lost to a normal build at distributed 8,192 operations; global invalidation undermines locality and concentrated 8,192 edit invalidation/rebuild cost was 6,840.820 ms. C's incremental lattice update matched a full rebuild at all stored grid nodes for the tested appended operation and after reload, but the interpolated field was not the canonical continuous SDF. C is rejected as an exact terrain representation. The ledger remains the sole authority in all prototypes.

**Recommendation:** do not integrate any prototype. Reject C for exact SDF use. Reject A as currently written. Continue only with a separately authorized, profiled design for exact local replay and a disposable chunk-local mesh cache with dependency-complete keys, bounded storage and full-ledger fallback. No production approval is implied.

## Identity, machine and inputs

* Candidate code commit `ffb5ccc4e59c03913b179f2b2db05cddd90ab1cd` has direct parent `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`. Physical source SHA-256 values: `p3_1_r3a_benchmark.gd` `fc4d350ccb6f07f319f3e5efb9938cba3b56119cc02f2713c176180c5870905f`; `r3a_density_snapshot.gd` `2aad631c91fcfd4ddbeb14d59fbb8c87e508dfab046055f28c899c14238292ee`; `r3a_fast_replay.gd` `419ea49515f9d7678608ab340cf37e298f265ab8c9a2e20c2ce0cc75671f93c4`; `r3a_mesh_cache.gd` `b0fa6992e1555a611deb147eb5ff9ac5f9b03e68ee2602f0d0d9435c2650a2d5`. The experiment adds only under `game/tests/prototypes/` and `game/tests/fixtures/p3_1_r3a/`, plus documentation/evidence and a path-specific `-text` attribute to retain exact frozen input bytes. No production runtime path was changed.
* Godot `4.7.2.stable.official.ed1daf0bf`; console executable `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`, SHA-256 `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643`.
* Windows 11 Pro build 22631, MACHINIST X99 PR9, Intel Xeon E5-2690 v4 (14 cores/28 logical processors), 63.8 GiB installed RAM, NVIDIA GTX 1050 Ti. No GPU timing or VRAM measurement was made. Renderer is not exercised by the headless harness.
* The source Issue #131 input manifest SHA-256 is `2dff9ccd5b98e1ea722051b25f961ff8f64c3ae698f3bc12102826e04ec3088d`; source checksum-index SHA-256 is `ac8a00cee024815dc55551c0ed5011ea2e9034d499b7846f7cf59b9b446d2be1`. The campaign expanded manifest SHA-256 is `55c1f4be70f608b5a6cd2f683c3c44d5db78358a4b79d5bc1b9b0920c527591e`.
* Seed `131102026`; generator v1; operation radius 580 mm; alternating CARVE/FILL in sequence order. Counts 256, 640, 2,048, 8,192, both distributed and concentrated. LOD mesh scenario uses region `(-31,-64)`, chunk `(2,2)`, LOD0/1; concentrated ledger uses region/chunk `(0,0)`. The separate cave control uses canonical SDF v1 in region `(0,0)`, chunk `(0,2)`, and nine centerline points.
* Full frozen workload paths, command-list hashes, exact launch JSON, stdout/stderr, CSV/JSONL, process-memory sample, summary and output digest are under [`evidence/campaign-06/`](evidence/campaign-06/). Fixture files are checked into the prototype input directory.

## Reproduction and evidence classification

The campaign used one headless Godot process, with an isolated profile and unique output root. The launcher command and arguments are in `evidence/campaign-06/command.json`. Runtime was 284,153 ms, exit code 0, `P31_R3A_PASS: scenarios=9 reference_hash_checks=23 failures=0`, stderr empty, and no Godot script/runtime errors. The output JSONL contains one row per scenario (eight edit rows plus cave control); each edit row's internal timing summaries use three mesh repetitions, while the campaign itself was not repeated in multiple processes. Therefore its percentiles are exploratory within-run timing distributions, not robust independent-run p95/p99 guarantees. The process monitor retained 303 samples each for engine PID 44588 and launcher PID 55096; engine sampled maximum working set was 249.84 MiB and private bytes 208.29 MiB. This is a sampled process peak, not a hardware-counter or exact allocation bound.

Earlier attempts are retained and explicitly classified in [`attempt-history.md`](evidence/attempt-history.md): campaign-01 had script errors in the cave control despite a misleading zero exit; campaign-02 capture deadlocked on undrained redirected pipes and was stopped; campaign-03 failed before scenario dispatch because an output variable was absent. None is accepted as performance evidence. Campaign-04 is a valid pre-incremental-snapshot full run, superseded by campaign-06 for the final source; campaign-06 is the final full result. Focused parse and smoke runs are retained separately. No historical evidence was deleted or overwritten.

`P31_R3A_PASS` means the isolated harness completed its own assertions; it is not a production SDF acceptance verdict. No gameplay, UI, renderer, real mesh publication, GPU, frame time or owner visual test occurred.

The first complete `scripts/validate.ps1` run exited 1 because two assertions in the pre-existing `procedural_object_tests.gd` failed: committed Redo reporting after injected visual-publication failure, and persisted override equality on stream revisit. No prototype or production source was changed in response. A fresh-profile focused rerun of that suite passed 638/638, and one full fresh-profile rerun passed **21 groups / 21,464 assertions / 0 failures**, exit 0, `VALIDATION_PASS: L0-L2`. Both full logs and the focused rerun are retained under `evidence/canonical-validation/`; the earlier transient failures are not erased. The successful full run still recorded the existing unavailable Windows junction fixture and three nonfatal camera look-at colinearity warnings. Startup was headless and no pixels were assessed.

Godot executable SHA-256: `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. The final campaign output JSONL SHA-256 is `39dd224c94d37924e718cfb391a2f3aa1a0d023be9ba80328d7c47fd5549279b`; every retained evidence file is listed in [`ARTIFACT_SHA256SUMS.txt`](evidence/ARTIFACT_SHA256SUMS.txt). The campaign expanded manifest SHA-256 is `55c1f4be70f608b5a6cd2f683c3c44d5db78358a4b79d5bc1b9b0920c527591e`. The source Issue #131 manifest and checksum-index digests are `2dff9ccd5b98e1ea722051b25f961ff8f64c3ae698f3bc12102826e04ec3088d` and `ac8a00cee024815dc55551c0ed5011ea2e9034d499b7846f7cf59b9b446d2be1`. The fixture path has a scoped `-text` rule so exact pinned input bytes survive future checkouts.

## Quantitative comparison

All timings are milliseconds, headless CPU/filesystem measurements. `A LOD0/1` compares canonical production builder to the test-only candidate. Cache is B's warm LOD1 read; it is not renderer publication. `C build` materializes a 0.5-unit grid; `C lattice delta` applies one appended ordered command to the stored nodes. The reported exact-grid mismatch counts were zero after update and after restart for every edit row. C's off-grid mismatches/normals remain disqualifying for exact SDF use.

| Layout | Ops | Full/indexed query p50 | A LOD0 ref→candidate p50 | A LOD1 ref→candidate p50 | B warm LOD1 | B disk bytes | C initial build | C incremental delta | C full post-edit rebuild | C probe mismatches | C LOD1 max normal Δ | C exact grid Δ after reload |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Distributed | 256 | 0.111 / 0.104 | 18.414 → 17.613 | 103.040 → 78.440 | 6.061 | 61,664 | 254.350 | 2.563 | 246.743 | 2 | 27.234° | 0 |
| Distributed | 640 | 0.275 / 0.182 | 18.965 → 17.854 | 104.530 → 79.140 | 13.466 | 61,664 | 650.068 | 5.788 | 632.895 | 2 | 27.234° | 0 |
| Distributed | 2,048 | 1.027 / 0.675 | 18.288 → 17.650 | 103.939 → 79.955 | 44.312 | 61,664 | 2,045.555 | 17.474 | 2,036.743 | 2 | 27.234° | 0 |
| Distributed | 8,192 | 6.025 / 4.338 | 18.310 → 18.555 | 103.365 → 83.386 | 174.762 | 61,664 | 9,710.430 | 85.946 | 9,660.241 | 2 | 27.234° | 0 |
| Concentrated | 256 | 0.113 / 0.697 | 75.605 → 178.177 | 303.722 → 735.732 | 7.939 | 65,112 | 253.508 | 2.808 | 252.733 | 2 | 157.308° | 0 |
| Concentrated | 640 | 0.441 / 1.829 | 163.896 → 423.337 | 645.109 → 1,870.051 | 18.071 | 68,136 | 645.893 | 6.126 | 639.628 | 2 | 68.798° | 0 |
| Concentrated | 2,048 | 0.931 / 5.743 | 458.854 → 1,272.294 | 1,685.031 → 5,334.207 | 59.191 | 63,528 | 2,102.633 | 17.601 | 2,096.301 | 2 | 152.116° | 0 |
| Concentrated | 8,192 | 7.865 / 34.141 | 1,789.632 → 5,203.181 | 6,502.572 → 21,008.214 | 235.468 | 63,096 | 9,800.553 | 85.946 | 9,660.241 | 2 | 82.795° | 0 |

Campaign data also report zero full/indexed query mismatch, zero A fast-SDF mismatch, zero selected LOD0/LOD1 vertex mismatch, and exact ordered replay metadata in all eight edit cases. A's concentrated scan still tests every operation (`indexed_max_candidates=operation_count` and fast-replay operation tests grow accordingly), making its added squared-distance branch and safe margin pure overhead there. For distributed 8,192, it measured 4.338 ms indexed p50 vs 6.025 ms full p50; that improvement does not offset the concentrated regression and does not prove all possible points/rounding edge cases.

B records three warm-cache hits in each measured row and checks restart, edit invalidation, corrupt entry rejection/rebuild and geometry parity. Cache warm LOD1 was much faster than a cold build on concentrated 256–8,192; at concentrated 8,192 it read the warm result in 235.468 ms versus a 6,502.572 ms canonical build. At 8,192 distributed it was slower (174.762 ms warm read vs 103.365 ms canonical build). The cache's edit-invalidation path ranged from 124.624 ms distributed 640 to 6,840.820 ms concentrated 8,192. B's whole-ledger digest means any new operation invalidates old entries even where geometry is unaffected. The 61–68 KiB on-disk cache in these samples and ~84–92 KiB measured live cache are only for the selected chunks, not a world-scale capacity projection.

C adds ~18.6 KiB per tested chunk snapshot and 2,277 lattice samples; it updates all lattice nodes for each appended operation, then verifies exact values against a full post-edit rebuild and after persistence reload. This is useful as a test of deterministic derived-state update/recovery, not an exact SDF shortcut. Off-grid probe mismatches and large normal differences demonstrate interpolation changes field behavior. Canonical cave control has 9/9 centerline samples open and the sampled density snapshot has 0/9; the cave oracle fails the snapshot. Although selected mesh vertices happened to match in these fixtures, that coincidence is insufficient for normals, arbitrary SDF probes, picking, cave topology or seam correctness.

## Storage and memory observations

The harness reports initial disk bytes, total disposable store bytes, segment reads/cache hits, append-delta write count, cache size, density snapshot size, and Godot static allocator delta. The JSONL is authoritative for per-row figures. At 8,192 operations, disposable total storage reached about 1.85 MB distributed and 1.89 MB concentrated; C's single-chunk lattice remained 18,584 bytes, while B's measured cache occupied about 61–68 KB and peaked around 84–92 KiB in these cases. Static allocator deltas reached 96.4 MB distributed and 106.1 MB concentrated; these are process-local static allocator readings, not total world or process peaks. The separate process sampler observed engine maximum working set/private bytes of 249.84/208.29 MiB. No RAM/VRAM budget was approved. Cache and snapshots are additional derived storage, not ledger compaction.

## Alternatives and decision gates

| Alternative | Evidence in this prototype | Main risk | Recommendation |
|---|---|---|---|
| A: exact replay pruning + LOD1 | Tested probes and selected mesh vertices matched; distributed large-history LOD1 faster in this sample; concentrated 256–8,192 replay markedly slower | Branch/check overhead remains O(N); tested cases do not establish universal floating-point equivalence | Reject current candidate; profile a mathematically proven conservative local replay design separately |
| B: derived mesh cache | Restart/corruption/edit invalidation tests worked; some small concentrated warm reads beat CPU build | Global ledger identity invalidates unrelated chunks; storage growth, writer atomicity, eviction, dependency halos and stale-version handling need production design | Possible future opt-in cache only; ledger authority and full rebuild fallback mandatory |
| C: sampled density snapshot | Exact at stored nodes; ordered incremental delta and reload reproduce the full lattice | Interpolation differs from continuous SDF, normals diverge and canonical cave topology disappears | Reject as exact field replacement; may be considered only for a separately specified approximate representation with explicit owner geometry/error gates |

Before production work, independently review source and raw data, decide whether a chunk-local cache is worth a narrowly scoped experiment, define disk/memory/error budgets, and keep the ledger canonical. No backend, cache, snapshot or ADR selection is made here.

## Full project validation

The final prototype source passed pinned Godot editor import, `--check-only`, focused cave and incremental-delta smokes, and a distributed-256 smoke. Full canonical validation outcome and exact assertion sum are recorded above; commands, environment attribution, failed first run, focused pass and successful retry are indexed in [`evidence/canonical-validation/`](evidence/canonical-validation/). Existing warnings are classified from raw logs. Main-scene startup is a headless startup probe, not visual acceptance.

## Scope and next step

Only disposable test prototypes, copied frozen fixtures, and experiment/report/checkpoint documentation are in scope. PR #129/#134 and production storage/SDF are unchanged. No Issue #108, native Voxel Tools, F2-G1 action, merge or release occurs. The next gate is independent source/evidence review of this exact candidate and a separate owner decision; these numbers do not authorize implementation or adoption.
