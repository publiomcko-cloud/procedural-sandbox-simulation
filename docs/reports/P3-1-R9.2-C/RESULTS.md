# P3.1 R9.2 Candidate C — E2E characterization

## Identity and scope

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Candidate branch: `bench/p3-1-r9-2c-surface-nets`
- Measured source SHA: `3e314f927cff5ca8a52c853bc5b504b8b3d86109` (direct parent `3109ae271a41131cde923f4f6bb486ccffa03d29`)
- Shared R9.2 preregistration parent: `392320959316002c883e398b7db91ab6f654a44b`
- Manifest SHA-256: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`
- Godot: `4.7.2.stable.official.ed1daf0bf`; executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`
- Machine profile and capture time: `evidence/environment/machine.json` (local Windows 11 Pro, Xeon E5-2690 v4, headless; no rendered/GPU metrics claimed).
- Production eligibility: **NOT_ELIGIBLE_EXPERIMENT_ONLY**.

Architecture: Uniform Surface Nets: canonical scalar grid, active-cell representative vertices, primal-edge/dual-face triangle extraction; reported metric labels remain qualified as in the source.

This branch is test-only. It does not change production SDF, production ledger, storage schema, playable scene or saves. Candidate D's temporary volume is isolated benchmark data and is not authority for production terrain.

## Execution and geometry disposition

Two independent final-source processes ran the 21 manifest variants each. Every process produced 44 JSONL records: one campaign start, 21 scenario starts/completions, and one campaign completion. The independent audit found no malformed JSONL, source/manifest identity mismatch, monotonic-clock regression, missing completion, wrong event parent, unexpected row, incorrect warmup/repeat count, or source row mismatch. Raw stdout/stderr, process capture, launch reservation, preflight, validation and previous attempts are in `evidence/`; `scenario-results.csv` contains all final scenario completion rows from both processes.

- Execution statuses: `{"COMPLETE": 40, "NOT_RUN": 2}`.
- Geometry-quality statuses: `{"DIAGNOSTIC_ONLY": 2, "NOT_ASSESSED": 2, "NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE": 4, "TOPOLOGY_DEFECT_RECORDED": 34}`.
- All geometry diagnostics are non-gating observations. No product-approved geometric tolerance exists; a recorded topology defect is not accepted geometry.
- Original R9 stop-loss outcomes remain separate in preserved historical campaign evidence; R9.2's smaller ROI outputs do not replace those old outcomes.

## Selected per-process observations

| Process run | Scenario | Execution / geometry status | Build timing | Internal opens | Nonmanifold | Surface residual p95 (world units) | Normal deviation p95 (degrees) |
|---|---|---|---:|---:|---:|---:|---:|
| candidate-c-campaign-02 | R9.2.GEO.ZERO.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 9077 µs median / 13002 µs nearest-rank p95 (n=5) | 28 | 0 | 0.0590015482902527 | 21.1811214179325 |
| candidate-c-campaign-02 | R9.2.GEO.CARVE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 10483 µs median / 14619 µs nearest-rank p95 (n=5) | 30 | 0 | 0.130445258617401 | 46.0770098734194 |
| candidate-c-campaign-02 | R9.2.GEO.FILL_CARVE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 7678 µs median / 7706 µs nearest-rank p95 (n=5) | 32 | 2 | 0.213180584907532 | 90.8042781995835 |
| candidate-c-campaign-02 | R9.2.CHUNK.NEIGHBOR_PAIR.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 24135 µs median / 24135 µs nearest-rank p95 (n=5) | 30 | 3 | 0.153246330022812 | 124.489795113628 |
| candidate-c-campaign-02 | R9.2.SEAM.XPLUS_EQUAL.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 17139 µs median / 17139 µs nearest-rank p95 (n=5) | 34 | 0 | 0.013860924243927 | 11.0428421034121 |
| candidate-c-campaign-02 | R9.2.HIST.XPLUS_DEFECT.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 27880 µs median / 27880 µs nearest-rank p95 (n=5) | 34 | 0 | 0.013860924243927 | 11.0428421034121 |
| candidate-c-campaign-02 | R9.2.CAVE.MESH_CONNECTIVITY.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 9878 µs median / 9878 µs nearest-rank p95 (n=5) | 28 | 0 | 0.0590015482902527 | 21.1811214179325 |
| candidate-c-campaign-02 | R9.2.RAY.CANONICAL_PICKER.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 8855 µs median / 9771 µs nearest-rank p95 (n=5) | 28 | 0 | 0.0590015482902527 | 21.1811214179325 |
| candidate-c-campaign-02 | R9.2.EDIT.LOCAL_REBUILD.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 21467 µs median / 22242 µs nearest-rank p95 (n=5) | 60 | 10 | 0.108349161148071 | 111.049854917942 |
| candidate-c-campaign-02 | R9.2.DETERMINISM.REBUILD.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 7920 µs median / 9686 µs nearest-rank p95 (n=5) | 32 | 2 | 0.213180584907532 | 90.8042781995835 |
| candidate-c-campaign-02 | R9.2.MEMORY.SERIALIZED_SIZE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 20386 µs median / 20652 µs nearest-rank p95 (n=5) | 60 | 10 | 0.108349161148071 | 111.049854917942 |
| candidate-c-campaign-02 | R9.2.D.CORRUPTION_RELOAD.v1 (default) | NOT_RUN / NOT_ASSESSED | NOT_RUN | NOT_REPORTED | NOT_REPORTED | NOT_REPORTED | NOT_REPORTED |
| candidate-c-campaign-03 | R9.2.GEO.ZERO.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 6884 µs median / 7069 µs nearest-rank p95 (n=5) | 28 | 0 | 0.0590015482902527 | 21.1811214179325 |
| candidate-c-campaign-03 | R9.2.GEO.CARVE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 7201 µs median / 10121 µs nearest-rank p95 (n=5) | 30 | 0 | 0.130445258617401 | 46.0770098734194 |
| candidate-c-campaign-03 | R9.2.GEO.FILL_CARVE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 7616 µs median / 7748 µs nearest-rank p95 (n=5) | 32 | 2 | 0.213180584907532 | 90.8042781995835 |
| candidate-c-campaign-03 | R9.2.CHUNK.NEIGHBOR_PAIR.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 19167 µs median / 19167 µs nearest-rank p95 (n=5) | 30 | 3 | 0.153246330022812 | 124.489795113628 |
| candidate-c-campaign-03 | R9.2.SEAM.XPLUS_EQUAL.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 18114 µs median / 18114 µs nearest-rank p95 (n=5) | 34 | 0 | 0.013860924243927 | 11.0428421034121 |
| candidate-c-campaign-03 | R9.2.HIST.XPLUS_DEFECT.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 17620 µs median / 17620 µs nearest-rank p95 (n=5) | 34 | 0 | 0.013860924243927 | 11.0428421034121 |
| candidate-c-campaign-03 | R9.2.CAVE.MESH_CONNECTIVITY.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 6943 µs median / 6943 µs nearest-rank p95 (n=5) | 28 | 0 | 0.0590015482902527 | 21.1811214179325 |
| candidate-c-campaign-03 | R9.2.RAY.CANONICAL_PICKER.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 9710 µs median / 15276 µs nearest-rank p95 (n=5) | 28 | 0 | 0.0590015482902527 | 21.1811214179325 |
| candidate-c-campaign-03 | R9.2.EDIT.LOCAL_REBUILD.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 20511 µs median / 22615 µs nearest-rank p95 (n=5) | 60 | 10 | 0.108349161148071 | 111.049854917942 |
| candidate-c-campaign-03 | R9.2.DETERMINISM.REBUILD.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 7769 µs median / 7874 µs nearest-rank p95 (n=5) | 32 | 2 | 0.213180584907532 | 90.8042781995835 |
| candidate-c-campaign-03 | R9.2.MEMORY.SERIALIZED_SIZE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 21829 µs median / 35302 µs nearest-rank p95 (n=5) | 60 | 10 | 0.108349161148071 | 111.049854917942 |
| candidate-c-campaign-03 | R9.2.D.CORRUPTION_RELOAD.v1 (default) | NOT_RUN / NOT_ASSESSED | NOT_RUN | NOT_REPORTED | NOT_REPORTED | NOT_REPORTED | NOT_REPORTED |

Times use the five frozen `build_samples_usec` values per scenario; displayed median and nearest-rank p95 are within each process only. For n=5, nearest-rank p95 and p99 equal the maximum; these estimates have low statistical confidence and are not pooled across runs. Campaign elapsed and external process-tree memory are in `evidence/.../process.json`.

## Prototype path and contract coverage

```text
Uniform Surface Nets: canonical scalar grid, active-cell representative vertices, primal-edge/dual-face triangle extraction; reported metric labels remain qualified as in the source.
canonical frozen density + ordered commands -> candidate-specific sampler/extractor -> diagnostic mesh and query oracles
```

| R9.2 investigation | Result |
|---|---|
| Frozen common geometry/edit/seam/ray/collision/local-rebuild/determinism/memory variants | Executed as listed in the CSV; candidate-specific statuses and limitations are preserved per row. |
| C smoothing comparison (none vs normal-only vs bounded SDF-constrained) | **NOT_IMPLEMENTED / NOT_RUN.** Frozen manifest has no separate smoothing variants; no smoothing comparison is claimed. |
| D second attributed reference extractor | **NOT_IMPLEMENTED / NOT_RUN.** Only the candidate's pinned extraction path was exercised, so storage and extractor effects are not disentangled. |
| D corrupt-file rejection after fresh disk reload | Executed only in D; diagnostics identify the read-back corrupted bytes and rejected hash. A/B/C explicitly report D-only row NOT_RUN by candidate scope. |
| Extracted empty-space cave connectivity / production collider or picker | Not established. Mesh component, sampled-density, and CPU query proxies are not equivalent to cave topology, gameplay picking, or PhysicsServer results. |

## Full validation

Final source SHA `3e314f927cff5ca8a52c853bc5b504b8b3d86109`: `scripts/validate.ps1` exit `0`, **21 suites / 21,464 assertions / 0 failures**, one global `VALIDATION_PASS` marker and 21 per-suite assertion summaries. Runtime `545.5 s`. Captured stderr contains three known, nonfatal Godot camera `Target and up vectors are colinear` warnings in `procedural_object_tests.gd` (lines 991, 1060, 1069); no parser or script errors. Reconciled counts and complete logs/hashes are retained in `evidence/candidate-c-validation-02/`.

Preflight/import, harness check-only, and the 160-assertion R9.2 contract suite passed on the measured source. Candidate A also preserves a failed earlier source gate attempt with a GDScript Array type error; it is not passing evidence and is included in its evidence history. Earlier campaign/validation attempts are retained separately and are not substituted for the final runs.

## Measurement boundaries and residual limitations

- Harness build times, query/proxy timings, and edit timings are headless CPU observations. They are **not** rendered FPS, presented-frame latency, GPU completion, VRAM, PhysicsServer collider behavior, or visual owner acceptance.
- Peak RAM is sampled at the external process-tree level, not isolated per scenario. No per-scenario high-water mark is claimed.
- The seam diagnostics use finite ROI/boundary-contour proxies, not publication of two production chunks; the neighbor-pair diagnostic does not validate a true chunk join.
- The local edit path rebuilds the scenario snapshot; it is not proof of incremental production remeshing.
- Cave connectivity reports sampled/candidate mesh diagnostics only where the harness explicitly implements them; it does not establish production cave topology.
- The CPU ray/picker and collision paths are diagnostic proxies, not the gameplay picker or Godot PhysicsServer. Headless measurements say nothing about actual display presentation.
- Candidate-specific topology, normal and residual measurements are influenced by the implemented extraction and ROI; candidate implementations are not quality-equivalent. Do not rank by a single timing or use this run to select a production winner.
- No owner-approved geometry, frame-time, memory or latency budgets were supplied. All measurements remain exploratory and unscored.

## Recommended engineering follow-up

Fix dual-face boundary/connectivity topology first. Then freeze three explicit smoothing arms (none, normal-only, bounded SDF-constrained) and measure displacement/cave preservation; those arms were not part of this R9.2 manifest.

## Evidence integrity

`SHA256SUMS.txt` hashes every committed evidence/report file other than itself. Source paths and both Git blob IDs and physical SHA-256 values are listed below.

- `game/tests/prototypes/p3_1_r9_2_candidate_impl.gd` — blob `175c0231fe298d7addbf2f139e9765343cb41e60`; physical SHA-256 `a0e178c84cf32f2c976986937da6235e6500b3325ae9760b5e43dbf7195a776a`
- `game/tests/prototypes/p3_1_r9_2_contract_tests.gd` — blob `1820c0836ac9f443d8ea9e07036e4d98f907d99d`; physical SHA-256 `43b59f0aef016085295e4798df198a5291ec9fd496c85a0ac27fd46d9e241300`
- `game/tests/prototypes/p3_1_r9_2_diagnostic_base.gd` — blob `a31a7484ede9b325bcdc78fd8f761d1b308f12ac`; physical SHA-256 `7615b1cd5b0c7a143cf985e53127ec5948312aaa7003fa7b9f93afdf7b1a4866`
- `game/tests/prototypes/p3_1_r9_2_e2e_harness.gd` — blob `b39a2709f824591e6b2a600e6cadfae31f2bf970`; physical SHA-256 `07affea27edd3312126c4f8a400edf1c8a916773837ecbc431374fdb7c3c6a8b`

No production integration, schema adoption, merge, release, or Issue #108 action is requested. The original #170–#174 PRs remain separate and unchanged.
