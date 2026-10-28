# P3.1 R9.2 — Four-Architecture E2E Diagnostic Contract

**Contract:** `P3.1.R9.2.contract.v1`
**Issue:** [#175](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/175)
**Parent:** R9 common experiment commit `a60d38df4f96b9007162e8fd917b3d14f29dcb0f`
**Historical comparison:** PR #174, source HEAD `60dd52585e711820d57d99481a3dac3b8030f146`
**Frozen source workload:** `game/tests/prototypes/p3_1_r9_frozen_inputs.jsonl`, SHA-256 `2b44cb52ef091c2527fa2f8b06859752cc7cfaa14bcafe94d4a4c55b0cdd908f`
**R9.2 workload:** [`p3_1_r9_2_e2e_inputs.jsonl`](../../game/tests/prototypes/p3_1_r9_2_e2e_inputs.jsonl); exact bytes are pinned by the adjacent `.sha256` file.

This version preregisters expanded, non-gating diagnostics for test-only architectures A/B/C/D. Geometry defects are evidence and do not stop other safe independent scenarios. No result is production approval, a geometry contract, a save-schema decision, GUI/PhysicsServer evidence, Issue #108/#154 implementation, merge authorization, or a change to any F2-G1 hold.

## 1. Identity and preservation

The only canonical terrain function is `SdfWorld.sample_density`, generator version 1, seed `131102026`; positive density is solid, negative density is empty, and world coordinates are world units. Commands are applied in increasing `sequence` order using the existing CARVE/FILL min/max semantics. Candidate-specific accelerations may not replace the canonical oracle. Original R9 manifests, logs, metrics, stop-losses, branches and PRs #170–#174 are historical and immutable; R9.2 is a new experiment rooted in the R9 common parent. Current remote `main` may contain later unrelated integrations; that does not change this explicitly pinned experimental lineage.

The previous full ROI remains `[8,-2,3]`, dimensions `[8,20,12]`, step `0.5`; it is not resized retroactively. R9.2 uses named bounded ROIs in the new manifest. Every candidate consumes identical manifest bytes and scenario records. The local four-command history is copied exactly from `R9.LOCAL.EXCAVATE_FILL.v1`; canonical CARVE and ordered FILL→CARVE inputs are copied from their named R9 records. New neighbor-boundary commands are explicit in the manifest. No scenario may transform, reorder, infer, or silently omit commands.

Manifest checks: UTF-8, no BOM, LF, terminal LF, exactly 20 compact JSON objects, unique `scenario_id`, schema version fixed, finite coordinates/radii, known command modes, contiguous zero-based command sequences, and canonical SHA-256 sidecar match before execution. The raw line digest is SHA-256 over exact UTF-8 line bytes excluding LF. The command identity is derived from the exact `commands` array byte slice in that line; if byte-range extraction cannot be verified, report it unavailable and do not reserialize to invent a digest. Binary mesh hashes include algorithm/version, ROI, LOD, source revision, float32 little-endian positions/normals and integer indices.

## 2. Non-gating result model

Every candidate/scenario/repetition records these independent fields:

| Field | Allowed values |
|---|---|
| `EXECUTION_STATUS` | `COMPLETED`, `FAILED`, `TIMED_OUT`, `CENSORED`, `NOT_RUN` |
| `CAPABILITY_STATUS` | `IMPLEMENTED`, `PARTIAL`, `NOT_IMPLEMENTED`, `BLOCKED` |
| `GEOMETRY_QUALITY_STATUS` | `OBSERVED_NO_RECORDED_DEFECT`, `DEFECT_RECORDED`, `UNSCORED`, `NOT_APPLICABLE`, `NOT_MEASURED` |
| `EVIDENCE_COMPLETENESS` | `COMPLETE`, `PARTIAL`, `INCOMPLETE` |
| `PRODUCTION_ELIGIBILITY` | always `INELIGIBLE` for R9.2 |

Each record also contains candidate/source SHA, source file hashes, manifest and case digests, run and parent-event IDs, scenario/repetition IDs, process-local monotonic start/end, exact reason, resource counters and raw artifact paths/hashes. Missing telemetry is `null` plus an explanation, never zero. A geometry failure is retained as `DEFECT_RECORDED`; if safe, later cave/edit/seam/ray diagnostics still run and state whether their mesh inputs contain known defects. An unsupported path is `NOT_IMPLEMENTED`; a valid but unattempted case is `NOT_RUN`. Only source/protected-state identity failures, evidence-integrity failures, unsafe/unbounded resource growth, or unrecoverable harness corruption stop a candidate campaign. Isolated functional or geometry failures do not.

No invalid candidate mesh is promoted to game geometry, physics, collision, or GUI use. CPU triangle tests use an offline two-sided mathematical ray/triangle oracle only. Headless build times are not FPS, GPU time, frame time, or presented-frame evidence.

## 3. Fixed 20-scenario matrix

The JSONL is authoritative for the exact values. `source_case`/`source_cases` point to the corresponding immutable R9 record. The 20 IDs cover: zero edit; CARVE; ordered FILL then CARVE; four repeated CARVEs; four repeated FILLs; neighboring chunks across X=16; equal-resolution X+; mixed-LOD X+; X− and Z− signed-region boundary variants; historical X+ 33/35 contour observation; historical X− ray displacement; cell 712/triangle 3103; sampled cave connectivity; extracted-mesh cave connectivity; 25 deterministic vertical SDF/picker rays; 12 fixed two-sided CPU proxy rays; four-command local edit/rebuild; deterministic reconstruction; memory/serialized-byte observation; and D-only real corrupt-byte reload rejection/rebuild. Thus the negative-boundary row contains two separately reported variants without collapsing their result records.

ROIs are bounded and stated per row. In particular, the two local-history cases use a domain containing the full command centers; the X=16 neighbor case spans both sides of the region boundary; and X+/X−/Z− seam domains straddle their stated plane. The original known X+ and X− source observations remain metadata, not acceptance thresholds. The known seam uses the canonical ordered R9 FILL→CARVE history; the R9.2 neighboring-chunk case separately uses four explicit edits centered around X=16. The triangle 3103 case uses the canonical cell coordinates and its frozen ordered history. Every variant has a stable case identity derived from its parent row and variant ID.

Scenario diagnostics include, where implemented: unique/repeated density queries, exact root brackets/iterations, sample/replay/extract/topology/serialization phase durations, emitted triangles and bytes, internal/boundary/open/nonmanifold edges, strict T-junctions, degeneracies, winding, canonical surface residual and normal-angle distributions, sampled-empty components, centerline slices, mesh components, shared-face scalar/gradient observations, actual extracted contours and edge traces, continuous SDF roots, picker and mesh hit/miss plus position deltas, D volume dirty cells/revision/corrupt reload, and local edit-to-coherent-mesh revision. Each metric includes definition, units, and availability. No single summary status masks missing data.

## 4. Geometry methods

The canonical surface reference is `SdfWorld.sample_density` with zero isovalue. For bounded mesh comparisons, sample deterministic points on each emitted triangle and along canonical edge/root brackets; report signed-distance residual and symmetric sampled surface distance with the sample construction and spacing. Report normal-angle differences using canonical finite-difference gradients at identical world coordinates, explicitly retaining singular/near-zero gradients as unavailable. Do not call this a certified Hausdorff bound.

Topology counters operate on actual emitted triangle index/position data, not only interpolated scalar values. Separate ROI crop-boundary edges from internal opens. Trace each internal open/nonmanifold edge to source cell(s), algorithmic edge/face, and orientation. A strict T-junction is a vertex lying inside a nonincident segment under the already-frozen R9 tolerance. Seam comparisons use exact shared-sample equality, independently extracted contour segment sets from both sides, edge incidence, winding, and an independently sampled piecewise-linear/root oracle. Report defects without stopping other safe cases.

Sampled cave connectivity uses a deterministic 0.125-unit 3D sample lattice in the `CAVE_SMALL` ROI. The component seeded at the canonical tunnel centerline is tested at each frozen X slice and at both X openings; exterior empty components are separate diagnostics. Mesh cave connectivity is computed from actual triangle connectivity/intersections and cross-sections; scalar connectivity cannot substitute. Preserve the historical 1.75-unit opening as a measured observation, not a tolerance.

The ray/picker scenario constructs exactly 25 downward rays from the Cartesian product of manifest X and Z coordinates, ordered X-major then Z-minor. The independent field root oracle uses the frozen bounded scan and bisection method; report scan resolution and root completeness limits, since tangent/narrow roots may be missed. Compare actual mesh triangle ray hits and the canonical picker separately. The 12 CPU proxy rays are explicit in JSONL and use two-sided Möller–Trumbore tests; they do not query Godot PhysicsServer.

## 5. Architecture-specific observations

- **A, root-aware Marching Tetrahedra:** retain canonical production fallback. Count unique/repeated query calls, root brackets/iterations, bisection and sampling/extraction costs. Run the original full ROI exactly as historical evidence only; its previous sample stop-loss remains recorded. R9.2 uses the frozen smaller ROI for completed mesh diagnosis. Do not hide stop-loss data by presenting small ROI numbers as full ROI.
- **B, adaptive Dual Contouring:** separately measure uniform and bounded balanced leaves when present; count primal crossings, Hermite constraints, QEF outcomes, connectivity and transition leaves. Trace open edges to source cells. Continue independent diagnostics after holes/cracks.
- **C, Surface Nets:** compare unsmoothed, normal-only, and bounded SDF-constrained vertex smoothing as separate configuration identities. Record displacement and cave changes; smoothing never converts a topology defect into a pass.
- **D, revisioned materialized volume:** ledger remains historical authority; the disposable materialized revision is only the experimental query/extraction source. Measure initialization, dirty cells, ordered incremental updates, revision replay, serialization/reload, actual byte corruption through a fresh reader, fallback rebuild, picker/proxy parity, and extraction cost. Run D's original extractor and one clearly attributed shared reference extractor when each is available. Separate volume construction from extraction comparisons; do not touch production or user saves.

## 6. Resource and timing limits

Before any candidate run, enforce the pre-existing per-build caps: 4 propagation rings, 10,000 unique sampled nodes, 20,000 emitted triangles, and 600 seconds wall-clock for a focused build. Add R9.2 run control: 60 seconds per scenario repetition, 600 seconds aggregate diagnostic wall time per candidate, and 512 MiB process peak working-set stop-loss. The controller checks before starting each independent case and stops/kills only on a resource limit or unsafe hang; it records the interrupted attempt as `CENSORED`, preserves partial raw artifacts, and may continue remaining independent cases in a fresh process after confirming custody and cleanup. These are experimental safety bounds, not product requirements or performance acceptance. R9's original full-ROI sample-cap outcome remains a separate historical record; no increase or reinterpretation.

Use `Time.get_ticks_usec()` as the process-local monotonic source; retain the run start origin, parent/child event IDs, process ID and command line. Distinguish cold process, warmup, repetitions, candidate/scenario/repetition distributions. Include raw samples and p50/p95/p99/max only for like-for-like inputs and same machine/source. A scenario is invalid if input/source/hash validation fails, commands or ROI differ from the manifest, output is truncated, timeout occurs before terminal record, or the candidate produces nonfinite accepted geometry. Invalid execution does not imply zero defects or a quality pass.

## 7. Repetition, evidence and final reporting

For completed bounded geometry/build/edit cases, run one warmup then five measured repetitions where safe; deterministic reconstruction runs at least two independent process builds. Small topology/root-specific cases use the manifest repeat count. Keep every repetition separate and report per-process distributions; do not pool different ROI, candidate, machine, LOD, history or execution mode. Timeouts are right-censored, not dropped. A failed or missing repetition is reported with its status and excluded from percentiles only with the denominator stated. Results with fewer than five valid repetitions remain descriptive and low confidence.

Each candidate package contains its implementation and source identity, architecture diagram, all 20 scenario results and variant expansion, metrics methodology, raw JSONL/CSV and stdout/stderr/process exits, artifacts, per-file SHA-256 index, validation logs and exact command lines. Run focused diagnostics, Godot `4.7.2.stable.official.ed1daf0bf` import/check-only as applicable, then `scripts/validate.ps1` against final test-only source; retain complete marker logs and reconcile suites/assertions directly. Candidate worktrees execute serially. Preserve all historical failures and evidence. Final comparison discusses experimental completeness, geometry, performance, edit behavior, memory and complexity with confidence levels; no single CPU timing ranks candidates and no architecture winner/production recommendation is asserted.

All five F2-G1 holds remain exactly: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
