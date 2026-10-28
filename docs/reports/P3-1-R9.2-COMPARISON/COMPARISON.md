# P3.1 R9.2 — Four-Architecture E2E Comparison

## Provenance and campaign identity

- Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`
- Common R9.2 preregistration: `392320959316002c883e398b7db91ab6f654a44b`; frozen manifest SHA-256 `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`.
- Engine: Godot `4.7.2.stable.official.ed1daf0bf`, binary SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- Hardware capture: candidate report evidence `environment/machine.json` (Xeon E5-2690 v4, 28 logical CPUs, 64 GiB visible RAM, Windows 11 Pro; campaign was headless). GPU is inventoried but no GPU work was measured.
- Each candidate has two final-source campaign processes. Each run passed its event audit: 44 JSONL records, 21 starts, 21 completions, zero malformed records or audit identity/order/sample-count errors. Source SHA, run/process evidence, complete stdout/stderr and all prior attempts are in each candidate report PR.
### Candidate PRs and implementation footprint

| Candidate | Draft evidence PR | Measured source SHA | `candidate_impl.gd` lines |
|---|---|---|---:|
| A — root-aware Marching Tetrahedra | [#176](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/176) | `8b59f32a854a89826fbe2ecd7998ed2e6347ba0c` | 204 |
| B — adaptive Dual Contouring | [#177](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/177) | `6a42467b3378a436851257ace641eee04ebfc7c8` | 182 |
| C — Surface Nets | [#178](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/178) | `3e314f927cff5ca8a52c853bc5b504b8b3d86109` | 94 |
| D — materialized volume | [#179](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/179) | `6f0a4b41349e228a546646f758d6992c2aca6f9e` | 127 |

Line counts are a simple source-size observation for the measured `candidate_impl.gd` files; they exclude shared harness, tests, reports and dependencies and are **not** a maintainability or complexity score.

## Capability and geometry comparison

| Candidate | Execution counts (two processes) | Geometry status counts (two processes) | Zero-edit internal opens | FILL→CARVE internal opens / nonmanifold | Process-tree peak range |
|---|---|---|---:|---:|---:|
| A | {"COMPLETE": 40, "NOT_RUN": 2} | {"DIAGNOSTIC_ONLY": 2, "NOT_ASSESSED": 2, "NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE": 30, "TOPOLOGY_DEFECT_RECORDED": 8} | 0 | 0 / 0 | 104–104 MiB |
| B | {"COMPLETE": 40, "NOT_RUN": 2} | {"DIAGNOSTIC_ONLY": 2, "NOT_ASSESSED": 2, "NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE": 4, "TOPOLOGY_DEFECT_RECORDED": 34} | 28 | 32 / 2 | 99–101 MiB |
| C | {"COMPLETE": 40, "NOT_RUN": 2} | {"DIAGNOSTIC_ONLY": 2, "NOT_ASSESSED": 2, "NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE": 4, "TOPOLOGY_DEFECT_RECORDED": 34} | 28 | 32 / 2 | 99–99 MiB |
| D | {"COMPLETE": 42} | {"DIAGNOSTIC_ONLY": 2, "NO_TOPOLOGY_DEFECT_OBSERVED_NOT_ACCEPTANCE": 2, "TOPOLOGY_DEFECT_RECORDED": 38} | 214 | 272 / 86 | 99–101 MiB |

Execution COMPLETE means the diagnostic scenario completed; it does not mean geometry accepted. A/B/C each show the D-only corruption row as scoped NOT_RUN. D executes the real corrupt-byte reload check and returns `volume_disk_hash_mismatch`; see D raw `corruption_reload` diagnostics. All candidates remain `NOT_ELIGIBLE_EXPERIMENT_ONLY`.

## Headless candidate build observations

Each cell below gives the within-process median of five frozen samples for process 1 and process 2. The adjacent p95 is nearest-rank within n=5 and therefore equals that run's maximum; it is shown as an observation, not a stable tail estimate. Do not pool the two processes. These workloads do not produce comparable geometry quality, so timings are contextual and must not rank a winner.

| Candidate | Scenario | Run 1 median ms | Run 1 n=5 NR p95 ms | Run 2 median ms | Run 2 n=5 NR p95 ms |
|---|---|---:|---:|---:|---:|
| A | R9.2.GEO.ZERO.v1 | 40.62 | 44.60 | 41.62 | 56.85 |
| A | R9.2.GEO.CARVE.v1 | 42.66 | 50.74 | 43.57 | 50.43 |
| A | R9.2.GEO.FILL_CARVE.v1 | 58.70 | 66.59 | 54.20 | 61.51 |
| A | R9.2.EDIT.LOCAL_REBUILD.v1 | 163.70 | 195.88 | 158.34 | 166.85 |
| A | R9.2.MEMORY.SERIALIZED_SIZE.v1 | 163.74 | 176.27 | 161.45 | 192.59 |
| B | R9.2.GEO.ZERO.v1 | 33.07 | 47.88 | 40.34 | 45.03 |
| B | R9.2.GEO.CARVE.v1 | 33.21 | 33.65 | 33.70 | 44.56 |
| B | R9.2.GEO.FILL_CARVE.v1 | 39.82 | 40.18 | 39.32 | 53.49 |
| B | R9.2.EDIT.LOCAL_REBUILD.v1 | 124.97 | 144.30 | 136.97 | 166.00 |
| B | R9.2.MEMORY.SERIALIZED_SIZE.v1 | 142.85 | 182.58 | 126.60 | 136.61 |
| C | R9.2.GEO.ZERO.v1 | 9.08 | 13.00 | 6.88 | 7.07 |
| C | R9.2.GEO.CARVE.v1 | 10.48 | 14.62 | 7.20 | 10.12 |
| C | R9.2.GEO.FILL_CARVE.v1 | 7.68 | 7.71 | 7.62 | 7.75 |
| C | R9.2.EDIT.LOCAL_REBUILD.v1 | 21.47 | 22.24 | 20.51 | 22.61 |
| C | R9.2.MEMORY.SERIALIZED_SIZE.v1 | 20.39 | 20.65 | 21.83 | 35.30 |
| D | R9.2.GEO.ZERO.v1 | 12.43 | 13.85 | 10.97 | 11.52 |
| D | R9.2.GEO.CARVE.v1 | 11.30 | 12.08 | 11.33 | 11.49 |
| D | R9.2.GEO.FILL_CARVE.v1 | 12.60 | 14.64 | 13.38 | 15.56 |
| D | R9.2.EDIT.LOCAL_REBUILD.v1 | 29.63 | 34.78 | 31.87 | 33.90 |
| D | R9.2.MEMORY.SERIALIZED_SIZE.v1 | 29.28 | 35.12 | 36.72 | 57.41 |

The full candidate `key-performance.csv` includes the five representative scenarios (zero, CARVE, FILL→CARVE, full-snapshot local edit rebuild, serialized-size observation) per process with candidate metric JSON. `candidate-scenario-results.csv` contains all 168 final scenario result rows; candidate-specific CSVs and raw JSONL remain in the corresponding candidate PRs #176–#179.

## Candidate capability findings

- **A — root-aware Marching Tetrahedra:** zero-edit ROI and single CARVE had no observed internal open edges in the tested single-mesh proxy. The adjacent pair and X+ seam rows still report open boundaries; X+ historical diagnostics retain 12. Normal p95 grows substantially under ordered edits (e.g. 57.96° in FILL→CARVE). CPU ray proxy reports 9/25 hit/miss disagreements and up to 1.796 world-unit distance error on its finite ray grid. This is not chunk-join proof.
- **B — one-level adaptive Dual Contouring:** zero edit has 28 internal opens; CARVE 30; FILL→CARVE 32 opens and 2 nonmanifold edges; local rebuild 60 opens / 10 nonmanifold. No balanced adaptive-leaf transition implementation is demonstrated. This is an implementation defect observation, not an algorithm impossibility result.
- **C — uniform Surface Nets:** zero edit has 28 internal opens; CARVE 30; FILL→CARVE 32 opens / 2 nonmanifold; local rebuild 60 / 10. The requested three-way smoothing comparison was **NOT_IMPLEMENTED / NOT_RUN** because the frozen R9.2 manifest has no smoothing arms. It must be a separately frozen follow-up, not inferred from these rows.
- **D — materialized volume:** zero has 214 internal opens / 67 nonmanifold; CARVE 219 / 71; FILL→CARVE 272 / 86; local edit extraction 837 / 270. Materialized volume serialized in the small zero fixture is 1,365 bytes for 315 nodes (1,260-byte payload); the 729-node fixture is 3,021 bytes (2,916-byte payload). D's corruption row reopens changed bytes from disk and rejects SHA mismatch (`expected=428646…`, `corrupt=e09fa0…`). The requested second attributed reference extractor remains **NOT_IMPLEMENTED / NOT_RUN**, so volume-storage behavior and extraction quality are not fully disentangled.

Across all four, extracted empty-space cave connectivity is not implemented as a valid mesh topology oracle. `CAVE.MESH_CONNECTIVITY` carries an explicit NOT_IMPLEMENTED diagnostic; sampled-density continuity is not a proof of mesh cave connectivity. The ray and collision work is offline CPU proxy only. No production viewport, PhysicsServer, real streaming chunk publish/unload, GUI, GPU, or presented-frame data exists.

## Repeatability, validation and confidence

- Independent process determinism: within each run, all five deterministic rebuild hashes matched; the five-hash arrays matched between the two processes for A/B/C/D. Hashes: A `d5f5460ae1ae51839a9c237001b13c2a216d9446c59940634900bf54ad52b2ba`; B `9b07a2c9c1b6e3ae103113de08253cbb335cb0cfc10faa1ae7886fc268d6b83a`; C `ad2a4e2a844df1264427f33d354bdfb06307008d77bbd0e526442ed6db7c37b8`; D `5748a16544f2f41cd5a8fedc2d9232cfae3a17fca87b30c082209edf51958a01`.
- Full `scripts/validate.ps1` on each final source SHA: 21 suites, 21,464 assertions, zero failures, exit 0. Each emitted three nonfatal colinear-camera warnings from the existing procedural object tests; no parser/script errors. Individual hashes and logs appear in the candidate reports.
- The new isolated 160-assertion R9.2 contract suite passed on all four final source SHAs. The first A gate attempt failed with a typed-array script error and was corrected; failed evidence is retained, not treated as a pass.
- Confidence: **high** for source/event identities and recorded validation counts; **moderate** for repeated same-workload headless CPU observations (two processes, five samples per scenario); **low** for tail-percentile inference at n=5; **low** for geometry generalization because sampled ROIs are small and defects remain; **none** for rendered performance, actual game collision, or production streaming behavior.

## Architecture interpretation and next experiment proposal

No production winner is selected. Candidate A is the most promising extraction follow-up only in the narrow sense that its tested single-mesh ROI has fewer open-edge defects and its sampled displacement is small; its angle, seam and ray discrepancies remain material. Candidate D offers an independently observable volume lifecycle and actual corruption rejection, but its current extraction is badly nonmanifold. B/C are too topologically defective to treat speed as useful selection evidence. These are hypotheses for next experiments, not adoption recommendations.

Proposed bounded next experiment (requires separate owner approval; not executed): one test-only follow-up with **12 frozen arms**: three C smoothing variants × four fixtures (zero cave, single CARVE, ordered FILL→CARVE, and the existing X+ seam ROI); one warmup plus five samples per arm; at most two independent processes; each fixture capped to existing R9.2 ROI dimensions and the existing per-candidate resource stop-loss. Report displacement, normal angle, component/topology, cave openings, and per-process time. This proposal only closes the missing Surface Nets smoothing question and does not gate or choose a production architecture. A separate D reference-extractor comparison should follow only if independently scoped and frozen.

## Evidence links and integrity

Candidate evidence is published in the four separate R9.2 candidate report PRs. This comparison report contains raw combined CSVs, capability/determinism tables, the hardware capture, and a SHA-256 inventory. `SHA256SUMS.txt` covers every file in this report directory except itself. Candidate PRs retain per-process raw output, stderr, source preflight, contract gate, validation and previous attempts.

- Candidate A: `8b59f32a854a89826fbe2ecd7998ed2e6347ba0c`
- Candidate B: `6a42467b3378a436851257ace641eee04ebfc7c8`
- Candidate C: `3e314f927cff5ca8a52c853bc5b504b8b3d86109`
- Candidate D: `6f0a4b41349e228a546646f758d6992c2aca6f9e`

No production source, save schema, user save, Issue #108 or #154 work was performed. Original PRs #170–#174 remain separate. All five F2-G1 holds remain unchanged. This evidence authorizes no production integration, merge, release or GUI acceptance.
