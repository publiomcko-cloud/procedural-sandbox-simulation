# P1.0C mesh and edit performance — Issue #93

**State:** implementation committed on the existing P1.0C branch and PR #92. Independent source rereview and owner GUI retest remain pending. This does not authorize merge, release, persistence, networking, or F2-G1 operations.

## Identity

- Repository: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Workspace: `C:\Dev\sandbox-sim-dev` (the existing functional-development worktree)
- Branch: `feat/p1-0c-global-cross-region-brushes`
- Implementation commit: `69a168eb6fe2a42f3fd6cb40024f86ed50634c2b`
- Direct parent: `163ef37a1ec0aab33dfea773a4176fae470161d8`
- Existing draft PR: [#92](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/92)
- Godot: `4.7.2.stable.official.ed1daf0bf`, executable pinned through `GODOT_BIN=C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe`

## Changes

- Replaced one-main-thread-slice-per-frame meshing with a bounded `WorkerThreadPool` queue. At most four CPU chunk jobs are in flight. Edit jobs take priority over full rebuilds, which take priority over distance-sorted region loads.
- Workers use immutable SDF/ledger snapshots and return packed vertex/normal arrays. They do not create Godot Mesh resources or touch scene nodes. The main thread creates at most two `ArrayMesh` resources per frame, validates the complete transaction/revision, then publishes the resulting region set.
- A chunk is triangulated as one CPU job. Shared lattice samples are read once per chunk job; intermediate slice meshes and their combination pass were removed. Empty cubes are skipped by comparing the eight sample signs. Repeated shared-gradient normals are cached within a chunk without changing the sampled field or normal calculation.
- Replaced per-cell temporary classification arrays with scalar classifications and scalar vertex appends. The canonical edit ledger, command ordering, ownership, reset semantics, generator v1, chunk resolution and shared-boundary rules are unchanged.
- Stale/canceled work is rejected by stage token and ledger revision. Only a bounded number of already-running stale jobs may finish; they cannot publish. Tree shutdown waits for this bounded set before cleanup.
- Frame samples use a ring buffer. Expensive formatted diagnostics refresh at 4 Hz rather than every frame.

## Benchmarks

Command for the full measured run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate.ps1`.
The performance-only kernel suite was also repeated separately with the same Godot binary. Direct kernels used seed `424242`, chunk `(1,1)`, five measured repetitions after warm-up. Times are milliseconds; p50/p95 are across those five samples. CPU stage values are independently timed and do not sum exactly to wall time.

### Comparable chunk kernel: before and after

| Ledger operations | Before p50/p95 | After full run p50/p95 | Repeated after p50/p95 | After stage p50 (SDF / triangulation / shared normals / ArrayMesh CPU build) |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 38.728 / 42.233 | 21.906 / 23.422 | 26.453 / 29.421 | 3.051 / 10.873 / 1.848 / 0.258 |
| 1 | 45.713 / 50.491 | 27.503 / 37.818 | 27.798 / 30.644 | 4.712 / 12.213 / 3.014 / 0.330 |
| 32 | 132.687 / 151.811 | 74.069 / 81.527 | 78.202 / 142.128 | 30.231 / 11.496 / 22.510 / 0.293 |

Across the principal full-run p50 values, the measured direct chunk kernel improved about 43%, 40%, and 44% for 0, 1, and 32 ledger commands. The separate repeat shows host load variability, particularly the 32-command p95; use the ranges as local measurements, not guarantees. CPU worker output was compared byte-for-byte for vertices and normals against the serial reference under 0/1/32 operations. Parallel corner jobs also matched the serial arrays and ran on multiple worker threads.

### End-to-end synthetic scenes

| Scenario | Before evidence | After measurement |
| --- | --- | --- |
| Cold initial 3×3 window (9 regions / 144 chunks) | 9,929 ms total; 4,950 ms aggregate mesh CPU work | 1,080 ms wall; 2,915 ms aggregate worker CPU work |
| Global operation, 2 regions / 4 chunks | 3,306 ms elapsed in the pre-change run; 40 slice builds | 50.5 ms accepted-to-transaction commit in the final integrated run (2 regions / 4 chunks) |
| Viewport click, one-region support | No same harness existed before optimization | 5 accepted clicks: p50 54.9 ms, p95 61.8 ms |
| Viewport click close to a seam, 2-region support | No same harness existed before optimization | 5 accepted clicks: p50 54.7 ms, p95 75.5 ms; 4 dependent regions / 6 chunks rebuilt |
| 32nd accepted global operation close to seam | Pre-change kernel benchmark only, not end-to-end | 62.0 ms to coherent scene-mesh commit; 2 regions / 4 chunks |
| Five cold camera region crossings | No matching pre-change measurement | p50 379.5 ms, p95 393.2 ms |
| Return to a 3×3 window after travel, with 32 retained edits | No matching pre-change measurement | 1,539 ms |

The initial-window improvement is about 9.2× on this machine, and the recorded end-to-end global edit fell from about 3.31 s to 50.5 ms. The older edit path and new event-driven test are close but not identical workloads; this ratio is indicative, not a controlled benchmark guarantee. There is no pre-change click or region-crossing sample set, so those have no before/after claim.

The same integrated run reported event-driven click-to-scene-commit frame p95/p99 around 6.9/7.1 ms; region-crossing frames were 6.9/8.3 ms. An unrelated integration-test measurement included a 118.9 ms p99 frame while the test performed additional synchronous reference work. Do not treat that number as a normal gameplay frame. Frame timing is headless local evidence, not a rendered GPU profile.

### Stage and queue interpretation

- Kernel stage fields measure SDF plus ledger sampling, triangulation plus face normals, shared-gradient normal work, and `ArrayMesh.add_surface_from_arrays` CPU construction separately. The ArrayMesh number is **not** GPU upload completion.
- Full 3×3 streaming stage totals are aggregated CPU time across 144 jobs. In the final full run they were SDF/ledger 651 ms, shared-gradient normals 246 ms, triangulation 1,992 ms, ArrayMesh CPU build 24 ms. Aggregate worker CPU can exceed wall time because jobs overlap.
- Queue wait is time from scheduler eligibility/enqueue to worker submission; worker-pool wait is submitted task start delay. The cold window's scheduler queue p95 was 1,052 ms across the 144-task burst, while the whole window completed in 1,081 ms. This is work waiting behind the bounded scheduler, not main-thread blocking.
- `ArrayMesh` construction and scene assignment stay on the main thread and are capped at two per frame. Godot's headless environment cannot isolate GPU upload or prove the mesh has been scanned out to the display. “Visible” in the automated latency tests means the coherent MeshInstance scene state was committed.

## Validation

`scripts/validate.ps1` passed sequentially on the pinned Godot 4.7.2 binary: import, deterministic smoke, SDF, brush/viewport, chunk equivalence, multiregion seams/streaming/failure injection, staged performance, click-to-commit/region traversal, concurrency/cancellation/transaction publication, bootstrap structure, and main-scene startup.

| Suite | Assertions | Result |
| --- | ---: | --- |
| Smoke | 52 | PASS |
| SDF and mesh | 44 | PASS |
| Brush and viewport | 156 | PASS |
| Chunk partition and localized remesh | 179 | PASS |
| Multi-region streaming and transaction cases | 7,634 | PASS |
| Staged worker/equivalence benchmark | 12 | PASS |
| Click/streaming end-to-end benchmarks | 27 | PASS |
| Worker cancellation/publication | 11 | PASS |
| Bootstrap structure | 18 | PASS |
| **Total** | **8,133** | **0 failures** |

Geometry tests confirm unchanged serial/worker vertices and normals, and equal full-mesh/chunked triangle counts. Concurrency tests cover multiple worker threads, stale focus cancellation, stale edit revision rejection, and latest-revision-only commit. `git diff --check` passed. No F2 ACL suites or protected-host operations were run.

## Limitations and owner retest

- No visual GUI, GPU upload, rendered-pixel, or input-device retest was performed. “Click-to-visible” is click event through transaction and MeshInstance commit in a headless viewport.
- The CPU kernel is faster, but returning to a fully cold 3×3 window still takes about 1.1 s, and five-region traversal crossings around 0.38 s. The 100 ms brush target is met in the measured common/seam tests; the initial-load target is exceeded substantially, though its absolute 3×3 load is still nontrivial.
- `ArrayMesh` creation/publication is bounded, but one frame in an instrumented multiregion test peaked around 68 ms of scene process work. The test includes synchronous integration/reference work, so profile a GUI build before making a frame-time claim.
- There is still no persistence or networking. Edits remain in-memory and are replayed from the canonical ledger.

Owner GUI procedure in Godot 4.7.2:

1. Open `game/project.godot`, run the main scene, and wait for the 3×3 terrain window to populate. Observe the HUD's active-region/job counters and confirm the scene remains responsive.
2. Click repeatedly on an exposed slope, then near a region seam and a corner. Confirm the carve/fill appears promptly, seams show no crack or normal discontinuity, and the HUD shows bounded job/upload activity.
3. Move across several region boundaries in positive and negative X/Z. Verify only a bounded region window stays active and newly requested regions load around the camera.
4. Return to an edited region and confirm its in-memory edits are reconstructed. Use `C`, `R`, and `X` to verify the cut, camera reset, and transaction reset behavior remain intact.
5. Watch for visible popping, missing triangles, cracks, stale edits after quick movement, or long input stalls. Record the exact OS/GPU/renderer and a screen recording if any occur.

All five F2-G1 holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.
