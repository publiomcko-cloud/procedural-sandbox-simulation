# P3.1 R9.2 Candidate B — E2E characterization

## Identity and scope

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Candidate branch: `bench/p3-1-r9-2b-dual-contouring`
- Measured source SHA: `6a42467b3378a436851257ace641eee04ebfc7c8` (direct parent `4f272497fa2d947eae64cb8faa5e7f973b011b29`)
- Shared R9.2 preregistration parent: `392320959316002c883e398b7db91ab6f654a44b`
- Manifest SHA-256: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`
- Godot: `4.7.2.stable.official.ed1daf0bf`; executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`
- Machine profile and capture time: `evidence/environment/machine.json` (local Windows 11 Pro, Xeon E5-2690 v4, headless; no rendered/GPU metrics claimed).
- Production eligibility: **NOT_ELIGIBLE_EXPERIMENT_ONLY**.

Architecture: One-level adaptive Hermite/QEF dual contouring: coarse sign grid, refined Hermite constraints, one QEF vertex per active parent cell, dual connectivity.

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
| candidate-b-campaign-02 | R9.2.GEO.ZERO.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 33073 µs median / 47878 µs nearest-rank p95 (n=5) | 28 | 0 | 0.0429175662994384 | 43.0916136226727 |
| candidate-b-campaign-02 | R9.2.GEO.CARVE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 33206 µs median / 33646 µs nearest-rank p95 (n=5) | 30 | 0 | 0.0414297151565551 | 53.2446339811264 |
| candidate-b-campaign-02 | R9.2.GEO.FILL_CARVE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 39819 µs median / 40178 µs nearest-rank p95 (n=5) | 32 | 2 | 0.127956671714783 | 92.1539823155935 |
| candidate-b-campaign-02 | R9.2.CHUNK.NEIGHBOR_PAIR.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 123850 µs median / 123850 µs nearest-rank p95 (n=5) | 28 | 3 | 0.0763524603843689 | 112.092474592666 |
| candidate-b-campaign-02 | R9.2.SEAM.XPLUS_EQUAL.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 73532 µs median / 73532 µs nearest-rank p95 (n=5) | 34 | 0 | 0.0368850398063659 | 80.6085723033184 |
| candidate-b-campaign-02 | R9.2.HIST.XPLUS_DEFECT.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 63650 µs median / 63650 µs nearest-rank p95 (n=5) | 34 | 0 | 0.0368850398063659 | 80.6085723033184 |
| candidate-b-campaign-02 | R9.2.CAVE.MESH_CONNECTIVITY.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 41015 µs median / 41015 µs nearest-rank p95 (n=5) | 28 | 0 | 0.0429175662994384 | 43.0916136226727 |
| candidate-b-campaign-02 | R9.2.RAY.CANONICAL_PICKER.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 33493 µs median / 36929 µs nearest-rank p95 (n=5) | 28 | 0 | 0.0429175662994384 | 43.0916136226727 |
| candidate-b-campaign-02 | R9.2.EDIT.LOCAL_REBUILD.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 124969 µs median / 144296 µs nearest-rank p95 (n=5) | 60 | 10 | 0.115080552101135 | 129.190102254707 |
| candidate-b-campaign-02 | R9.2.DETERMINISM.REBUILD.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 39592 µs median / 54751 µs nearest-rank p95 (n=5) | 32 | 2 | 0.127956671714783 | 92.1539823155935 |
| candidate-b-campaign-02 | R9.2.MEMORY.SERIALIZED_SIZE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 142850 µs median / 182578 µs nearest-rank p95 (n=5) | 60 | 10 | 0.115080552101135 | 129.190102254707 |
| candidate-b-campaign-02 | R9.2.D.CORRUPTION_RELOAD.v1 (default) | NOT_RUN / NOT_ASSESSED | NOT_RUN | NOT_REPORTED | NOT_REPORTED | NOT_REPORTED | NOT_REPORTED |
| candidate-b-campaign-03 | R9.2.GEO.ZERO.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 40340 µs median / 45028 µs nearest-rank p95 (n=5) | 28 | 0 | 0.0429175662994384 | 43.0916136226727 |
| candidate-b-campaign-03 | R9.2.GEO.CARVE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 33701 µs median / 44560 µs nearest-rank p95 (n=5) | 30 | 0 | 0.0414297151565551 | 53.2446339811264 |
| candidate-b-campaign-03 | R9.2.GEO.FILL_CARVE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 39320 µs median / 53493 µs nearest-rank p95 (n=5) | 32 | 2 | 0.127956671714783 | 92.1539823155935 |
| candidate-b-campaign-03 | R9.2.CHUNK.NEIGHBOR_PAIR.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 93617 µs median / 93617 µs nearest-rank p95 (n=5) | 28 | 3 | 0.0763524603843689 | 112.092474592666 |
| candidate-b-campaign-03 | R9.2.SEAM.XPLUS_EQUAL.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 75963 µs median / 75963 µs nearest-rank p95 (n=5) | 34 | 0 | 0.0368850398063659 | 80.6085723033184 |
| candidate-b-campaign-03 | R9.2.HIST.XPLUS_DEFECT.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 78097 µs median / 78097 µs nearest-rank p95 (n=5) | 34 | 0 | 0.0368850398063659 | 80.6085723033184 |
| candidate-b-campaign-03 | R9.2.CAVE.MESH_CONNECTIVITY.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 48307 µs median / 48307 µs nearest-rank p95 (n=5) | 28 | 0 | 0.0429175662994384 | 43.0916136226727 |
| candidate-b-campaign-03 | R9.2.RAY.CANONICAL_PICKER.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 32197 µs median / 37914 µs nearest-rank p95 (n=5) | 28 | 0 | 0.0429175662994384 | 43.0916136226727 |
| candidate-b-campaign-03 | R9.2.EDIT.LOCAL_REBUILD.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 136971 µs median / 165999 µs nearest-rank p95 (n=5) | 60 | 10 | 0.115080552101135 | 129.190102254707 |
| candidate-b-campaign-03 | R9.2.DETERMINISM.REBUILD.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 40690 µs median / 53087 µs nearest-rank p95 (n=5) | 32 | 2 | 0.127956671714783 | 92.1539823155935 |
| candidate-b-campaign-03 | R9.2.MEMORY.SERIALIZED_SIZE.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 126601 µs median / 136607 µs nearest-rank p95 (n=5) | 60 | 10 | 0.115080552101135 | 129.190102254707 |
| candidate-b-campaign-03 | R9.2.D.CORRUPTION_RELOAD.v1 (default) | NOT_RUN / NOT_ASSESSED | NOT_RUN | NOT_REPORTED | NOT_REPORTED | NOT_REPORTED | NOT_REPORTED |

Times use the five frozen `build_samples_usec` values per scenario; displayed median and nearest-rank p95 are within each process only. For n=5, nearest-rank p95 and p99 equal the maximum; these estimates have low statistical confidence and are not pooled across runs. Campaign elapsed and external process-tree memory are in `evidence/.../process.json`.

## Prototype path and contract coverage

```text
One-level adaptive Hermite/QEF dual contouring: coarse sign grid, refined Hermite constraints, one QEF vertex per active parent cell, dual connectivity.
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

Final source SHA `6a42467b3378a436851257ace641eee04ebfc7c8`: `scripts/validate.ps1` exit `0`, **21 suites / 21,464 assertions / 0 failures**, one global `VALIDATION_PASS` marker and 21 per-suite assertion summaries. Runtime `551.0 s`. Captured stderr contains three known, nonfatal Godot camera `Target and up vectors are colinear` warnings in `procedural_object_tests.gd` (lines 991, 1060, 1069); no parser or script errors. Reconciled counts and complete logs/hashes are retained in `evidence/candidate-b-validation-02/`.

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

Trace open/nonmanifold edges to active-cell face ownership and introduce a separately tested balanced transition/connectivity design before any smoothing or performance work. The observed defects are implementation evidence, not a proof against Dual Contouring.

## Evidence integrity

`SHA256SUMS.txt` hashes every committed evidence/report file other than itself. Source paths and both Git blob IDs and physical SHA-256 values are listed below.

- `game/tests/prototypes/p3_1_r9_2_candidate_impl.gd` — blob `3fb2a8dcd446e055cd118fc0e17315e93d9d2644`; physical SHA-256 `f625fa94404597b582730ea214e19f03eaf03e12b20db39786dc76b611983419`
- `game/tests/prototypes/p3_1_r9_2_contract_tests.gd` — blob `1820c0836ac9f443d8ea9e07036e4d98f907d99d`; physical SHA-256 `43b59f0aef016085295e4798df198a5291ec9fd496c85a0ac27fd46d9e241300`
- `game/tests/prototypes/p3_1_r9_2_diagnostic_base.gd` — blob `a31a7484ede9b325bcdc78fd8f761d1b308f12ac`; physical SHA-256 `7615b1cd5b0c7a143cf985e53127ec5948312aaa7003fa7b9f93afdf7b1a4866`
- `game/tests/prototypes/p3_1_r9_2_e2e_harness.gd` — blob `3a4bc37a415044290780362f67486c15011dc8b3`; physical SHA-256 `8f35824d0891e2718f99bd2208ab588b6b6f9b06f6ba541bf0788da2c8647828`

No production integration, schema adoption, merge, release, or Issue #108 action is requested. The original #170–#174 PRs remain separate and unchanged.
