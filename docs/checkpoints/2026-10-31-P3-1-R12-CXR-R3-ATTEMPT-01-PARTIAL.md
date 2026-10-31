# P3.1 R12-CXR R3 Attempt 01 — Partial Boundary-Domain Result

Date: 2026-10-31

## Classification

`R12_CXR_PARTIAL_WITH_EVIDENCE`. The target process started and completed, but no valid R3 patch boundary was constructed, so the field-support candidate generator and triangulation search did not run. This is not a finite-domain no-solution result and does not test the central support-vertex feasibility claim.

## Exact execution evidence

- Frozen code source: `64ce92c909c0b5871303a787baeba84e28477c77`; execution checkout: `45607bfd511d9fbb966388b36657941eac3a5645`; origin is the procedural-sandbox-simulation repository; PR #213 remains draft/unmerged.
- One target invocation: `R9.2.SEAM.XPLUS_EQUAL.v1`, `R12CXR_PHASE=r3`, attempt `R3_TARGET_20261031_01`.
- Godot `4.7.2.stable.official.ed1daf0bf`, executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- Process PID 44284, parent PID 42876, start `2026-10-31T20:47:16.1465154Z`, end `2026-10-31T20:47:19.9726109Z`, elapsed 3,826.0955 ms, exit 0, no timeout, stderr empty. The source marker `R12CXR_TARGET_INVOCATION_BEGIN` is present. A zero exit code does not change the geometry `PARTIAL` result.
- The campaign reproduced frozen C6 volume identity and payload; volume gate was true. The result JSON SHA-256 is `8692824368adfaffa500e1fd9af454d29c49ac40e62960da42b415fa9e7b37f8`.
- Raw process records, stdout/stderr, full result JSON, independent structured summary, and checksum inventory are retained at [`r3_target_attempt_01`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_target_attempt_01/). The profile used a new TEMP `APPDATA` root; no user save or protected state was accessed.

## Observed cavity levels

The realizer grouped all three residual faces into one joint cavity `09ff86410e9969c6`. All four declared levels had two disconnected edge-connected components and invalid remaining-mesh boundaries:

| Level | Patch triangles | Component sizes | Boundary diagnostics | Result |
| --- | ---: | --- | ---: | --- |
| L0 | 3 | 2, 1 | 8 | disconnected; invalid one-to-one incidence |
| L1 | 12 | 8, 4 | 19 | disconnected; same-direction source winding |
| L2 | 19 | 13, 6 | 31 | disconnected; open patch edge lacks remaining owner |
| L3 | 28 | 18, 10 | 47 | disconnected; open patch edge lacks remaining owner |

For every level, candidate generation and solver search were `NOT_RUN_INVALID_JOINT_BOUNDARY`. Candidate-generation attempts: 0; support candidates: 0; candidate triangles: 0; selected supports: 0; search nodes: 0. `search_complete=false`, `search_exhaustive=false`, terminal `r3_no_valid_joint_boundary_level`. Controls, ROI rays, mixed LOD, deterministic repeat, full E2E and `scripts/validate.ps1` were correctly not run after the equal-LOD gate failed.

## Corrective implementation finding

The attached R12-CXR procedure requires processing each of the two pre-existing overlapping-defect cavities separately. The R3 implementation instead replaced those groups with a single union of all three residual seeds. The measured L0-L3 component counts show that this joint patch cannot satisfy R3's one-connected-patch/one-boundary-cycle precondition. That scope mismatch prevented any field-constrained support from being tested. Therefore this result is a bounded R3 implementation/domain-construction failure, not a solver exhaustion result.

The next corrective source revision will restore the frozen two-cavity grouping, run the same field-derived support procedure independently per cavity, and retain the remaining-C6-incidence boundary, global ordered authority, R2 topology/owner constraints, fixed cutoff, and preregistered per-cavity/global limits. The old attempt is consumed and will never be rerun. Any corrected-code execution must use a new attempt ID, exact source pins, and a fresh committed pre-target freeze. No downstream gate is authorized until both equal-LOD cavity realizations pass.

No production source, persistence schema, saves, Issue #108/#154, PRs #207-#212, or protected F2-G1 state were changed. All five F2-G1 holds remain.
