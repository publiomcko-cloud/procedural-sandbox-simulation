# P3.1 R9.2 Candidate A — E2E characterization

## Identity and scope

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Candidate branch: `bench/p3-1-r9-2a-mt`
- Measured source SHA: `8b59f32a854a89826fbe2ecd7998ed2e6347ba0c` (direct parent `30dff47634cb1d1568bc5de6ed0149170d04ce08`)
- Shared R9.2 preregistration parent: `392320959316002c883e398b7db91ab6f654a44b`
- Manifest SHA-256: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`
- Godot: `4.7.2.stable.official.ed1daf0bf`; executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`
- Machine profile and capture time: `evidence/environment/machine.json` (local Windows 11 Pro, Xeon E5-2690 v4, headless; no rendered/GPU metrics claimed).
- Production eligibility: **NOT_ELIGIBLE_EXPERIMENT_ONLY**.

Architecture: Root-aware Marching Tetrahedra: canonical density/root samples, edge-root cache, root bisection then tetrahedral facets.

This branch is test-only. It does not change production SDF, production ledger, storage schema, playable scene or saves. Candidate D's temporary volume is isolated benchmark data and is not authority for production terrain.

## Execution and geometry disposition

Two independent final-source processes ran the 21 manifest variants each. Every process produced 44 JSONL records: one campaign start, 21 scenario starts/completions, and one campaign completion. The independent audit found no malformed JSONL, source/manifest identity mismatch, monotonic-clock regression, missing completion, wrong event parent, unexpected row, incorrect warmup/repeat count, or source row mismatch. Raw stdout/stderr, process capture, launch reservation, preflight, validation and previous attempts are in `evidence/`; `scenario-results.csv` contains all final scenario completion rows from both processes.

- Execution statuses: `{"COMPLETE": 40, "NOT_RUN": 2}`.
- Geometry-quality statuses: `{"DIAGNOSTIC_ONLY": 2, "NOT_ASSESSED": 2, "NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE": 30, "TOPOLOGY_DEFECT_RECORDED": 8}`.
- All geometry diagnostics are non-gating observations. No product-approved geometric tolerance exists; a recorded topology defect is not accepted geometry.
- Original R9 stop-loss outcomes remain separate in preserved historical campaign evidence; R9.2's smaller ROI outputs do not replace those old outcomes.

## Selected per-process observations

| Process run | Scenario | Execution / geometry status | Build timing | Internal opens | Nonmanifold | Surface residual p95 (world units) | Normal deviation p95 (degrees) |
|---|---|---|---:|---:|---:|---:|---:|
| candidate-a-campaign-04 | R9.2.GEO.ZERO.v1 (default) | COMPLETE / NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE | 40619 µs median / 44597 µs nearest-rank p95 (n=5) | 0 | 0 | 0.000877125263214151 | 12.9608959974466 |
| candidate-a-campaign-04 | R9.2.GEO.CARVE.v1 (default) | COMPLETE / NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE | 42665 µs median / 50740 µs nearest-rank p95 (n=5) | 0 | 0 | 0.000904901027679483 | 34.0529827700401 |
| candidate-a-campaign-04 | R9.2.GEO.FILL_CARVE.v1 (default) | COMPLETE / NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE | 58704 µs median / 66591 µs nearest-rank p95 (n=5) | 0 | 0 | 0.00102003097534176 | 57.9578434960537 |
| candidate-a-campaign-04 | R9.2.CHUNK.NEIGHBOR_PAIR.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 113615 µs median / 113615 µs nearest-rank p95 (n=5) | 4 | 0 | 0.000981526374816855 | 69.7247380522757 |
| candidate-a-campaign-04 | R9.2.SEAM.XPLUS_EQUAL.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 104416 µs median / 104416 µs nearest-rank p95 (n=5) | 12 | 0 | 0.000510258674621622 | 9.01257961239626 |
| candidate-a-campaign-04 | R9.2.HIST.XPLUS_DEFECT.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 97790 µs median / 97790 µs nearest-rank p95 (n=5) | 12 | 0 | 0.000510258674621622 | 9.01257961239626 |
| candidate-a-campaign-04 | R9.2.CAVE.MESH_CONNECTIVITY.v1 (default) | COMPLETE / NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE | 44953 µs median / 44953 µs nearest-rank p95 (n=5) | 0 | 0 | 0.000877125263214151 | 12.9608959974466 |
| candidate-a-campaign-04 | R9.2.RAY.CANONICAL_PICKER.v1 (default) | COMPLETE / NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE | 40303 µs median / 46955 µs nearest-rank p95 (n=5) | 0 | 0 | 0.000877125263214151 | 12.9608959974466 |
| candidate-a-campaign-04 | R9.2.EDIT.LOCAL_REBUILD.v1 (default) | COMPLETE / NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE | 163703 µs median / 195882 µs nearest-rank p95 (n=5) | 0 | 0 | 0.000924544334411581 | 48.3175677881758 |
| candidate-a-campaign-04 | R9.2.DETERMINISM.REBUILD.v1 (default) | COMPLETE / NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE | 55300 µs median / 59968 µs nearest-rank p95 (n=5) | 0 | 0 | 0.00102003097534176 | 57.9578434960537 |
| candidate-a-campaign-04 | R9.2.MEMORY.SERIALIZED_SIZE.v1 (default) | COMPLETE / NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE | 163740 µs median / 176272 µs nearest-rank p95 (n=5) | 0 | 0 | 0.000924544334411581 | 48.3175677881758 |
| candidate-a-campaign-04 | R9.2.D.CORRUPTION_RELOAD.v1 (default) | NOT_RUN / NOT_ASSESSED | NOT_RUN | NOT_REPORTED | NOT_REPORTED | NOT_REPORTED | NOT_REPORTED |
| candidate-a-campaign-05 | R9.2.GEO.ZERO.v1 (default) | COMPLETE / NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE | 41622 µs median / 56851 µs nearest-rank p95 (n=5) | 0 | 0 | 0.000877125263214151 | 12.9608959974466 |
| candidate-a-campaign-05 | R9.2.GEO.CARVE.v1 (default) | COMPLETE / NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE | 43572 µs median / 50434 µs nearest-rank p95 (n=5) | 0 | 0 | 0.000904901027679483 | 34.0529827700401 |
| candidate-a-campaign-05 | R9.2.GEO.FILL_CARVE.v1 (default) | COMPLETE / NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE | 54202 µs median / 61512 µs nearest-rank p95 (n=5) | 0 | 0 | 0.00102003097534176 | 57.9578434960537 |
| candidate-a-campaign-05 | R9.2.CHUNK.NEIGHBOR_PAIR.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 119408 µs median / 119408 µs nearest-rank p95 (n=5) | 4 | 0 | 0.000981526374816855 | 69.7247380522757 |
| candidate-a-campaign-05 | R9.2.SEAM.XPLUS_EQUAL.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 99110 µs median / 99110 µs nearest-rank p95 (n=5) | 12 | 0 | 0.000510258674621622 | 9.01257961239626 |
| candidate-a-campaign-05 | R9.2.HIST.XPLUS_DEFECT.v1 (default) | COMPLETE / TOPOLOGY_DEFECT_RECORDED | 91417 µs median / 91417 µs nearest-rank p95 (n=5) | 12 | 0 | 0.000510258674621622 | 9.01257961239626 |
| candidate-a-campaign-05 | R9.2.CAVE.MESH_CONNECTIVITY.v1 (default) | COMPLETE / NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE | 42471 µs median / 42471 µs nearest-rank p95 (n=5) | 0 | 0 | 0.000877125263214151 | 12.9608959974466 |
| candidate-a-campaign-05 | R9.2.RAY.CANONICAL_PICKER.v1 (default) | COMPLETE / NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE | 40497 µs median / 41396 µs nearest-rank p95 (n=5) | 0 | 0 | 0.000877125263214151 | 12.9608959974466 |
| candidate-a-campaign-05 | R9.2.EDIT.LOCAL_REBUILD.v1 (default) | COMPLETE / NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE | 158337 µs median / 166848 µs nearest-rank p95 (n=5) | 0 | 0 | 0.000924544334411581 | 48.3175677881758 |
| candidate-a-campaign-05 | R9.2.DETERMINISM.REBUILD.v1 (default) | COMPLETE / NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE | 58087 µs median / 62015 µs nearest-rank p95 (n=5) | 0 | 0 | 0.00102003097534176 | 57.9578434960537 |
| candidate-a-campaign-05 | R9.2.MEMORY.SERIALIZED_SIZE.v1 (default) | COMPLETE / NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE | 161451 µs median / 192590 µs nearest-rank p95 (n=5) | 0 | 0 | 0.000924544334411581 | 48.3175677881758 |
| candidate-a-campaign-05 | R9.2.D.CORRUPTION_RELOAD.v1 (default) | NOT_RUN / NOT_ASSESSED | NOT_RUN | NOT_REPORTED | NOT_REPORTED | NOT_REPORTED | NOT_REPORTED |

Times use the five frozen `build_samples_usec` values per scenario; displayed median and nearest-rank p95 are within each process only. For n=5, nearest-rank p95 and p99 equal the maximum; these estimates have low statistical confidence and are not pooled across runs. Campaign elapsed and external process-tree memory are in `evidence/.../process.json`.

## Prototype path and contract coverage

```text
Root-aware Marching Tetrahedra: canonical density/root samples, edge-root cache, root bisection then tetrahedral facets.
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

Final source SHA `8b59f32a854a89826fbe2ecd7998ed2e6347ba0c`: `scripts/validate.ps1` exit `0`, **21 suites / 21,464 assertions / 0 failures**, one global `VALIDATION_PASS` marker and 21 per-suite assertion summaries. Runtime `554.6 s`. Captured stderr contains three known, nonfatal Godot camera `Target and up vectors are colinear` warnings in `procedural_object_tests.gd` (lines 991, 1060, 1069); no parser or script errors. Reconciled counts and complete logs/hashes are retained in `evidence/candidate-a-validation-02/`.

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

Prioritize conforming chunk-edge ownership and seam closure, then investigate normal-angle outliers (especially ordered fill/carve); keep root-sample stop-loss and canonical reference checks. Do not infer that clean finite-ROI topology solves production seams.

## Evidence integrity

`SHA256SUMS.txt` hashes every committed evidence/report file other than itself. Source paths and both Git blob IDs and physical SHA-256 values are listed below.

- `game/tests/prototypes/p3_1_r9_2_candidate_impl.gd` — blob `271062fd67162ceb70a293d39f17ccaa397f2377`; physical SHA-256 `24d3537bc461f576fa10ee482694f7a791c790e8442d44aab89add1c75f59ae1`
- `game/tests/prototypes/p3_1_r9_2_contract_tests.gd` — blob `1820c0836ac9f443d8ea9e07036e4d98f907d99d`; physical SHA-256 `43b59f0aef016085295e4798df198a5291ec9fd496c85a0ac27fd46d9e241300`
- `game/tests/prototypes/p3_1_r9_2_diagnostic_base.gd` — blob `a31a7484ede9b325bcdc78fd8f761d1b308f12ac`; physical SHA-256 `7615b1cd5b0c7a143cf985e53127ec5948312aaa7003fa7b9f93afdf7b1a4866`
- `game/tests/prototypes/p3_1_r9_2_e2e_harness.gd` — blob `fa6310b01eea54a09ad0e4678a5706852f8b7c3e`; physical SHA-256 `b4cc0c4c1c89889ffe89e00a16f48f7cb98d2b9e3ffede5721491ede14f138f1`

No production integration, schema adoption, merge, release, or Issue #108 action is requested. The original #170–#174 PRs remain separate and unchanged.
