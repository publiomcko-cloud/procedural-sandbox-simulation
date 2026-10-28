# P3.1 R9.2 Candidate D — E2E characterization

## Identity and scope

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Candidate branch: `bench/p3-1-r9-2d-materialized-volume`
- Measured source SHA: `6f0a4b41349e228a546646f758d6992c2aca6f9e` (direct parent `121e1a11a83076b23b25c6305484336b4b5a14a6`)
- Shared R9.2 preregistration parent: `392320959316002c883e398b7db91ab6f654a44b`
- Manifest SHA-256: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`
- Godot: `4.7.2.stable.official.ed1daf0bf`; executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`
- Machine profile and capture time: `evidence/environment/machine.json` (local Windows 11 Pro, Xeon E5-2690 v4, headless; no rendered/GPU metrics claimed).
- Production eligibility: **NOT_ELIGIBLE_EXPERIMENT_ONLY**.

Architecture: Test-only float32 materialized density volume with revision/hash and isolated serialization/reload, then extraction; ledger remains experiment input authority, never production state.

This branch is test-only. It does not change production SDF, production ledger, storage schema, playable scene or saves. Candidate D's temporary volume is isolated benchmark data and is not authority for production terrain.

## Execution and geometry disposition

Two independent final-source processes ran the 21 manifest variants each. Every process produced 44 JSONL records: one campaign start, 21 scenario starts/completions, and one campaign completion. The independent audit found no malformed JSONL, source/manifest identity mismatch, monotonic-clock regression, missing completion, wrong event parent, unexpected row, incorrect warmup/repeat count, or source row mismatch. Raw stdout/stderr, process capture, launch reservation, preflight, validation and previous attempts are in `evidence/`; `scenario-results.csv` contains all final scenario completion rows from both processes.

- Execution statuses: `{"COMPLETE": 42}`.
- Geometry-quality statuses: `{"DIAGNOSTIC_ONLY": 2, "NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE": 2, "TOPOLOGY_DEFECT_RECORDED": 38}`.
- All geometry diagnostics are non-gating observations. No product-approved geometric tolerance exists; a recorded topology defect is not accepted geometry.
- Original R9 stop-loss outcomes remain separate in preserved historical campaign evidence; R9.2's smaller ROI outputs do not replace those old outcomes.

## Selected per-process observations

| Process run | Scenario | Execution / geometry status | Build timing | Internal opens | Nonmanifold | Surface residual p95 (world units) | Normal deviation p95 (degrees) |
|---|---|---|---:|---:|---:|---:|---:|
| candidate-d-campaign-02 | R9.2.GEO.ZERO.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 12425 µs median / 13849 µs nearest-rank p95 (n=5) | 214 | 67 | 0.0294381213188172 | 15.9711324633148 |
| candidate-d-campaign-02 | R9.2.GEO.CARVE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 11303 µs median / 12084 µs nearest-rank p95 (n=5) | 219 | 71 | 0.0425177049636841 | 38.3553252113314 |
| candidate-d-campaign-02 | R9.2.GEO.FILL_CARVE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 12597 µs median / 14640 µs nearest-rank p95 (n=5) | 272 | 86 | 0.128874706029892 | 91.6116180564709 |
| candidate-d-campaign-02 | R9.2.CHUNK.NEIGHBOR_PAIR.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 27589 µs median / 27589 µs nearest-rank p95 (n=5) | 567 | 183 | 0.0785522627830505 | 85.5235966283604 |
| candidate-d-campaign-02 | R9.2.SEAM.XPLUS_EQUAL.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 24650 µs median / 24650 µs nearest-rank p95 (n=5) | 446 | 136 | 0.00781087398529057 | 8.81347311397292 |
| candidate-d-campaign-02 | R9.2.HIST.XPLUS_DEFECT.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 21967 µs median / 21967 µs nearest-rank p95 (n=5) | 446 | 136 | 0.00781087398529057 | 8.81347311397292 |
| candidate-d-campaign-02 | R9.2.CAVE.MESH_CONNECTIVITY.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 11030 µs median / 11030 µs nearest-rank p95 (n=5) | 214 | 67 | 0.0294381213188172 | 15.9711324633148 |
| candidate-d-campaign-02 | R9.2.RAY.CANONICAL_PICKER.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 12780 µs median / 13850 µs nearest-rank p95 (n=5) | 214 | 67 | 0.0294381213188172 | 15.9711324633148 |
| candidate-d-campaign-02 | R9.2.EDIT.LOCAL_REBUILD.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 29629 µs median / 34783 µs nearest-rank p95 (n=5) | 837 | 270 | 0.0566595363616943 | 69.3615114878494 |
| candidate-d-campaign-02 | R9.2.DETERMINISM.REBUILD.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 12267 µs median / 12416 µs nearest-rank p95 (n=5) | 272 | 86 | 0.128874706029892 | 91.6116180564709 |
| candidate-d-campaign-02 | R9.2.MEMORY.SERIALIZED_SIZE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 29280 µs median / 35125 µs nearest-rank p95 (n=5) | 837 | 270 | 0.0566595363616943 | 69.3615114878494 |
| candidate-d-campaign-02 | R9.2.D.CORRUPTION_RELOAD.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 28811 µs median / 28811 µs nearest-rank p95 (n=5) | 837 | 270 | 0.0566595363616943 | 69.3615114878494 |
| candidate-d-campaign-03 | R9.2.GEO.ZERO.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 10970 µs median / 11515 µs nearest-rank p95 (n=5) | 214 | 67 | 0.0294381213188172 | 15.9711324633148 |
| candidate-d-campaign-03 | R9.2.GEO.CARVE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 11329 µs median / 11489 µs nearest-rank p95 (n=5) | 219 | 71 | 0.0425177049636841 | 38.3553252113314 |
| candidate-d-campaign-03 | R9.2.GEO.FILL_CARVE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 13384 µs median / 15563 µs nearest-rank p95 (n=5) | 272 | 86 | 0.128874706029892 | 91.6116180564709 |
| candidate-d-campaign-03 | R9.2.CHUNK.NEIGHBOR_PAIR.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 30492 µs median / 30492 µs nearest-rank p95 (n=5) | 567 | 183 | 0.0785522627830505 | 85.5235966283604 |
| candidate-d-campaign-03 | R9.2.SEAM.XPLUS_EQUAL.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 22475 µs median / 22475 µs nearest-rank p95 (n=5) | 446 | 136 | 0.00781087398529057 | 8.81347311397292 |
| candidate-d-campaign-03 | R9.2.HIST.XPLUS_DEFECT.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 21882 µs median / 21882 µs nearest-rank p95 (n=5) | 446 | 136 | 0.00781087398529057 | 8.81347311397292 |
| candidate-d-campaign-03 | R9.2.CAVE.MESH_CONNECTIVITY.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 11225 µs median / 11225 µs nearest-rank p95 (n=5) | 214 | 67 | 0.0294381213188172 | 15.9711324633148 |
| candidate-d-campaign-03 | R9.2.RAY.CANONICAL_PICKER.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 10898 µs median / 18477 µs nearest-rank p95 (n=5) | 214 | 67 | 0.0294381213188172 | 15.9711324633148 |
| candidate-d-campaign-03 | R9.2.EDIT.LOCAL_REBUILD.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 31867 µs median / 33903 µs nearest-rank p95 (n=5) | 837 | 270 | 0.0566595363616943 | 69.3615114878494 |
| candidate-d-campaign-03 | R9.2.DETERMINISM.REBUILD.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 12234 µs median / 17219 µs nearest-rank p95 (n=5) | 272 | 86 | 0.128874706029892 | 91.6116180564709 |
| candidate-d-campaign-03 | R9.2.MEMORY.SERIALIZED_SIZE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 36721 µs median / 57414 µs nearest-rank p95 (n=5) | 837 | 270 | 0.0566595363616943 | 69.3615114878494 |
| candidate-d-campaign-03 | R9.2.D.CORRUPTION_RELOAD.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 42727 µs median / 42727 µs nearest-rank p95 (n=5) | 837 | 270 | 0.0566595363616943 | 69.3615114878494 |

Times use the five frozen `build_samples_usec` values per scenario; displayed median and nearest-rank p95 are within each process only. For n=5, nearest-rank p95 and p99 equal the maximum; these estimates have low statistical confidence and are not pooled across runs. Campaign elapsed and external process-tree memory are in `evidence/.../process.json`.

## Prototype path and contract coverage

```text
Test-only float32 materialized density volume with revision/hash and isolated serialization/reload, then extraction; ledger remains experiment input authority, never production state.
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

Final source SHA `6f0a4b41349e228a546646f758d6992c2aca6f9e`: `scripts/validate.ps1` exit `0`, **21 suites / 21,464 assertions / 0 failures**, one global `VALIDATION_PASS` marker and 21 per-suite assertion summaries. Runtime `533.0 s`. Captured stderr contains three known, nonfatal Godot camera `Target and up vectors are colinear` warnings in `procedural_object_tests.gd` (lines 991, 1060, 1069); no parser or script errors. Reconciled counts and complete logs/hashes are retained in `evidence/candidate-d-validation-02/`.

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

Keep the materialized volume as derived and revision/hash-bound. Test one separately attributed reference extractor and preserve the actual corrupt-reload rejection, but resolve the severe extracted topology defects before drawing mesh-authority conclusions.

## Evidence integrity

`SHA256SUMS.txt` hashes every committed evidence/report file other than itself. Source paths and both Git blob IDs and physical SHA-256 values are listed below.

- `game/tests/prototypes/p3_1_r9_2_candidate_impl.gd` — blob `69eb011d18c1c971e8d1d44bdf56a5af6eeda09c`; physical SHA-256 `42281d02e76ff546b4c611c6882c7655e474bc2d3c61f289935ff1555cc6f3b7`
- `game/tests/prototypes/p3_1_r9_2_contract_tests.gd` — blob `1820c0836ac9f443d8ea9e07036e4d98f907d99d`; physical SHA-256 `43b59f0aef016085295e4798df198a5291ec9fd496c85a0ac27fd46d9e241300`
- `game/tests/prototypes/p3_1_r9_2_diagnostic_base.gd` — blob `a31a7484ede9b325bcdc78fd8f761d1b308f12ac`; physical SHA-256 `7615b1cd5b0c7a143cf985e53127ec5948312aaa7003fa7b9f93afdf7b1a4866`
- `game/tests/prototypes/p3_1_r9_2_e2e_harness.gd` — blob `2d3ee476670554b1bd57a5656bb631d3f961b425`; physical SHA-256 `27ac366ad1c4b4b350c1f99c256830155f5db96f914cfa4a2f2bfd308f5364b6`

No production integration, schema adoption, merge, release, or Issue #108 action is requested. The original #170–#174 PRs remain separate and unchanged.
