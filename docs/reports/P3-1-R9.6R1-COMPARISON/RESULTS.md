# P3.1 R9.6R1 — Controlled Recovery and Geometry Attempt 1 Results

**Disposition: `P3_1_R9_6R1_BLOCKED_WITH_EVIDENCE`**
**Scope:** test-only; no production, persistence schema, user-save, release, Issue #108/#154, or protected-host changes.

## Executive result

The runtime gate recovered on pinned Godot 4.7.2. The corrected shared topology suite executed 50 assertions with zero failures. Candidate A and D each completed one topology-first geometry attempt, but neither met the frozen geometry target. Both retained internal open edges and cutoff-rejected triangles; their mixed-LOD contours remain disjoint. No second geometry attempt was made because a bounded SDF-constrained refinement that preserves the existing cutoff and conforms to neighboring interfaces was not established. Full E2E and `scripts/validate.ps1` are therefore not reported as passes and were not run on a surviving candidate.

## Provenance and scope

Repository origin: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`.

| Work | Base / tested source | Published head | Notes |
|---|---|---|---|
| R1 recovery | PR #197 head `db748c8b987bf0007610daa9120697211bace46b` | `0f8cfcdc64ef43096ff9f6166d17605bb1c13aec` | Parent `ef728877b2fe3899fde0b233fe0a94bb8f88b2ec`; two topology helper/test paths only; PR #202 |
| Candidate A execution | `bf230c4916c66e2150f8725480d8ce3ca589b353` | `224f2e9ef650f103736f84451dc849f3ab3e94e6` | Parent `0f8cfcdc64ef43096ff9f6166d17605bb1c13aec`; tracked tree matches execution tree `74a865e4fc6e11fa7cba4b8a9c8a073d04207bae`; PR #203 |
| Candidate D execution | `7115166067b7f6e9c68dd9425981259ae065c5bc` | `731033f37b44414e17202e73457e9584a99364d8` | Parent `0f8cfcdc64ef43096ff9f6166d17605bb1c13aec`; tracked tree matches execution tree `7ddb998dd487bba3010717ce75646b5255c0b8b5`; PR #204 |
| Consolidated report | PR #200 head `1f7a9a575df42add40a38e65d3e1ecfb88ceba31` | See this report PR | Docs and evidence only; PR #205 |

The executed source commits and published candidate PR heads differ as commit objects, but each published commit has the same complete tracked tree as its measured source. No `UNPINNED_WORKTREE` run is claimed. Candidate C stayed frozen; Candidate B stayed out of scope.

Frozen manifest SHA-256: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`. Godot binary SHA-256: `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`; version output: `4.7.2.stable.official.ed1daf0bf`.

Physical source SHA-256 values are in [SOURCE-SHA256SUMS.txt](SOURCE-SHA256SUMS.txt); selected raw process logs and candidate topology JSON are in `evidence/`. For D, the executed LF worktree file hashes to `37CF20740511EC6ECB927850F182BC333173F2F1771449E484427EFE6D8E8A98`, while the published worktree file hashes to `A0A5001422C95EEA7D1B323C48F79FEE3A8815D3309EA19E602404F296AE748F` because `core.autocrlf=true` checked out CRLF there. Both commits resolve the candidate path to the same Git blob `9a10fbb6cf979c35e51677f4106c2f193a2f9a24`, and LF-normalized bytes compare equal. Thus Git source identity and semantics reconcile; the raw working-tree byte hashes are explicitly distinct. The complete 525-file local evidence-root inventory is in [LOCAL_EVIDENCE_ROOT_SHA256SUMS.txt](LOCAL_EVIDENCE_ROOT_SHA256SUMS.txt). The original root remains at `C:\Users\PUBLI\AppData\Local\Temp\P3_1_R96R1_20261029_1217Z_0fbfecd9baea4e8ba9bbf4cee419a3d2` and is retained unchanged apart from this report being stored elsewhere.

## Memory discrepancy and host evidence

The prior comparison report says approximately **89,908 KB** free virtual memory. No retained authoritative source for that number was found; classify it as `UNSUPPORTED_HISTORICAL_RESOURCE_VALUE` and do not repeat it as a measurement. The committed R9.6 `resource-snapshot.json` reports WMI `FreeVirtualMemory=8,702,612 KB` and `TotalVirtualMemory=74,037,908 KB`. Those WMI values are not Windows commit charge/limit measurements. The discrepancy is reconciled as a reporting error/unsupported historical value, not evidence of commit exhaustion.

A retained Windows Resource Exhaustion Detector Event 2004 at `2026-10-29 08:14:40 -03:00` reports a low-virtual-memory warning and high consumption by `vmmemWSL` and other applications. It does not identify the cause of the earlier whole-PC freeze. The owner-reported freeze remains exactly `HOST_FREEZE_OBSERVED_UNKNOWN_ATTRIBUTION`. No process, WSL instance, pagefile, service, or owner application was terminated, restarted, suspended, or reconfigured. A later bounded-event query found no System 41/6008 record in the queried 12-hour window; this does not prove that no other event exists.

Immediately before A at `2026-10-29T13:24:56Z`, the OS-native snapshot showed 24.26/63.84 GiB physical RAM available, 83.82% commit use, 11.83/73.11 GiB commit headroom, 120.58 GiB free on project and TEMP volumes, and WSL running. Immediately after at `13:25:03Z`, it showed 24.27 GiB RAM available, 83.83% commit use, 11.82 GiB commit headroom, and 120.57 GiB disk/TEMP free. Before D at `13:17:18Z`, it showed 23.85/63.84 GiB RAM available, 84.17% commit use, 11.58 GiB headroom, and 120.88 GiB disk/TEMP free; after at `13:17:24Z`, 23.82 GiB RAM available, 84.18% commit use, 11.56 GiB headroom, and 120.87 GiB disk/TEMP free. The pagefile was not automatic-managed: `C:\pagefile.sys`, configured 1,000–10,000 MB, allocated 9,487 MB; current use was 1,243 MB before A and 1,135 MB before D. These snapshots met the bounded launch gates and do not establish the earlier freeze cause or historical commit exhaustion.

The A and D runs were serial, with no concurrent candidate campaign. No new freeze occurred during these bounded runs.

## Engine and topology gate

The executable hash and `--version` output were verified. The standalone version probe's process PID was not captured in its process record; its binary identity is independently verified by SHA-256. The known-good source import at `895dbca3c6dd58bb9adacd63fb39c3ad524226ff` completed with exit 0. The corrected R9.6 source import at `0f8cfcdc64ef43096ff9f6166d17605bb1c13aec` completed with exit 0 (process 28748). The direct topology test completed with exit 0 (process 41492) and printed:

```text
R96_TOPOLOGY_TESTS {"assertions":50,"failure_reasons":[],"failures":0}
R96_TOPOLOGY_TESTS_PASS
```

The executed count is 50, not the older static site count of 38. Test corrections include explicit typed arrays, the correct ROI boundary perimeter, and a delimiter-safe root-edge key separator so root IDs containing `|` do not collide. Helper and test file hashes are pinned in the source checksum inventory. The topology gate is `TOPOLOGY_GATE_PASS`.
Process records captured source, command line, working directory, timestamps, exit code, stdout/stderr hashes, and observed Godot process creation data. Control 1 `--version`: exit 0, PID not captured (attribution gap). Known-good import: PID 25376, 11.78 s, exit 0. R1 import: PID 28748, 10.84 s, exit 0. R1 topology test: PID 41492, 0.284 s, exit 0. Candidate A: import PID 36820 (9.74 s, 0), check-only PID 7016 (0.932 s, 0), geometry PID 8808 (5.973 s, 0). Candidate D: import PID 53824 (9.263 s, 0), check-only PID 24708 (0.841 s, 0), geometry PID 32072 (5.603 s, 1). The JSON process records include observed parent PID and command line for each process; the version probe remains the stated exception.

## Candidate outcomes

| Candidate | Preflight | Geometry process | Controls / ray oracle | X+ equal LOD | X+ mixed LOD | Disposition |
|---|---|---|---|---|---|---|
| A | Import 0; `--check-only` 0 | PID 8808; exit 0; 5.97 s; stderr empty | 6/6 controls pass; root identity pass; 0/25 ROI hit/miss disagreements | Full/left ROI: 8 internal open edges, 7 triangles rejected by unchanged cutoff, 15 required adjacencies missing | 10 left / 22 right segments, no shared segments | `PARTIAL`; target fails |
| D | Import 0; `--check-only` 0 | PID 32072; exit 1; 5.60 s; stderr empty | 5/6 controls pass; negative-region X strict mesh-hash control fails; 0/25 ROI hit/miss disagreements | Full ROI: 13 internal open edges, 8 triangles rejected by unchanged cutoff, 19 required adjacencies missing | 10 left / 22 right segments, no shared segments | Target fails |

Both runs preserved `cross_squared > 1e-12`. The independent root identity probes passed. The ray result is ROI-scoped only and makes no PhysicsServer claim. A's process exit 0 and `failure_count=0` mean the harness completed without counted assertion failures; the emitted status was `ATTEMPT_1_TOPOLOGY_FIRST`, and the geometry artifacts explicitly say realization is incomplete. This is not a geometry PASS. D's exit 1 and seven failures are retained as candidate failures.

Frozen prior cave and neighbor controls passed on A. D preserved those controls except the negative-region X strict hash case. Neither result satisfies the experimental target because equal-LOD topology is incomplete and mixed-LOD boundaries mismatch.

## Attempts, validation and stop decision

- `A_ATTEMPTS_USED=1/3` — topology-first attempt 1 was actually executed. Earlier parser/diagnostic failures produced no geometry and are retained as non-geometry recovery records.
- `D_ATTEMPTS_USED=1/3` — topology-first attempt 1 was actually executed. Earlier root-identity/delimiter diagnostic failures produced no geometry and are retained as non-geometry recovery records.
- A2/D2 SDF-constrained local refinement and A3/D3 face-owned interface patches: `NOT_RUN`.
- Full frozen E2E and `scripts/validate.ps1`: `NOT_RUN`. The contract runs these only for a final surviving candidate; neither candidate survived attempt 1. No validation PASS is implied.

The next technical step is to extract the actual failing cell/face patch and design bounded SDF-constrained refinement with conforming ownership at its coarse/fine boundary. It must preserve the current degeneracy cutoff, existing passing controls, exact-zero root identity, and the 0/25 ray oracle. No such correction was source-implemented or measured in this recovery, so continuing to another geometry run would be speculative. The candidates are blocked, not accepted; remaining attempts are available for a separately reviewed correction.

## Evidence completeness and protections

- Evidence root: 525 files, 117,277,198 bytes; full local SHA-256 inventory is provided. 65 selected raw output/process/artifact files (8.03 MiB) are included here; host snapshots and the full historical package remain in the owner-local root and are hash-listed, not publicly duplicated.
- The committed Git blobs for all 65 embedded raw evidence files were independently rechecked against `SHA256SUMS.txt`: 65/65 match. The report-scoped `.gitattributes` rule prevents line-ending conversion in that raw evidence subtree. The full 525-file owner-local root inventory was also checked: 525/525 present and matching.
- Draft evidence PRs: [#202 recovery](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/202), [#203 Candidate A](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/203), [#204 Candidate D](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/204), and [#205 comparison](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/205). All remain unmerged.
- Exact stdout SHA-256: topology test `4b5f49a96064b6d1c4a445ed3871cd100901d65ac3df8d2655621b6053b36271`; A run `13b75eb994a730f2260c45b9258b99434f434cff162454117e950765ba737fa5`; D run `23705bb259e0995fa431818099750593265aabfb63f047558b7ed0f77b4dab4c`. All three stderr files are empty (SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`).
- Owner worktree `C:\Dev\sandbox-sim-dev` remains at `92b442d7f5b605c7bc9c48fac2aceea9d71813aa` on `feat/p3-1-scalable-terrain-storage`; exactly three pre-existing untracked `.gd.uid` files remain; `stash@{0}` and `stash@{1}` remain unchanged.
- PRs #197–#200 remain open, draft and unmerged. New PRs #202–#205 are separate drafts. No production, schema, save, merge, release, Issue #108/#154, or F2-G1 action occurred. The five F2-G1 holds remain: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

**Final status:** `P3_1_R9_6R1_BLOCKED_WITH_EVIDENCE`.

---

## Continuation addendum — A2, D2, A3 and D3 preflight (2026-10-29)

This section is append-only and supersedes only the campaign status and attempt counters above. The preceding report remains the historical R1/A1/D1 checkpoint. It is not edited or erased.

### Attempt matrix

| Candidate | Attempt | Tested source / process | Result | Controls |
|---|---|---|---|---|
| A | A1 | Historical source `bf230c4916c66e2150f8725480d8ce3ca589b353`; process evidence remains in the original candidate-A attempt-1 files | Partial: equal X+ retained 8 internal opens, 7 triangles were dropped by the unchanged `cross_squared > 1e-12` cutoff and 15 required adjacencies were not realized; mixed boundary was 10 vs 22 with no shared contour identities | 6/6 frozen controls; 0/25 ROI hit/miss disagreements |
| A | A2 | `4afc7ded4c083a78f3dd3d02709f34140e5f9a52`, parent `e6dd1fb63fb2d46dd8005017f544d7584cab0a7c`; PID 55556, exit 0, 6.801 s; run `0a082c315fdc4d4fac3127d9d4ebb7d8`; stdout SHA-256 `902d6db38883c19d758f207aa6323504aca9a9d4d8a55c02938187c24f2d5782`; stderr empty | The bounded centroid refinement examined 3 cells / 7 parent tetrahedra, evaluated 168 additional canonical-SDF samples, constructed 7 candidate roots/Steiner vertices, maximum recorded root residual `1.35421752933684e-06` against the experimental `1e-4` bound and maximum displacement `2.81657012237702e-05`; it emitted 0 refinement triangles. Candidate mesh hash stayed at baseline. Equal X+ remained 8 internal opens; mixed X+ combined ROI remained 32 opens, with no repaired contour pairing. | 6/6; root-identity probe pass; 0/25 ROI hit/miss disagreements |
| A | A3 | Corrected source `fc6690edb6ac0fd605de3e78814df724e9c72e47`, parent `577d22d6d7fa9c83d822a242cfaf7e002c78810f`; PID 7512, exit 0, 6.502 s; run `3acd702d2b2e4805833f97cca85eebdb`; stdout SHA-256 `b396a3ff59dec7502eae24d5bf0244952e9f9834fa9ebe0c28ebf39dda8d810e`; stderr empty | Equal X+ selected `shared_existing_contour`, with 22 edges on each side, 0 new interface triangles, 8 internal opens and no nonmanifold edges. The canonical-surface diagnostic rejected the empty patch mesh. Mixed X+ remained 10 vs 22 edges; the interface zipper rejected a triangle with `cross_squared=1.44387658703197e-14`, below the unchanged `1e-12` cutoff, so no transition patch was produced; base combined ROI retained 32 opens. The historical X+ proxy also retained 8 opens. No new interface vertices were emitted. | 6/6; root identity pass; 0/25 ROI hit/miss disagreements |
| D | D1 | Historical source `7115166067b7f6e9c68dd9425981259ae065c5bc`; process evidence remains in original candidate-D attempt-1 files | Partial with a negative-X strict mesh-hash control failure: 13 X+ equal-LOD opens, 8 cutoff drops, 19 required adjacencies missing; mixed 10 vs 22 with no shared transition | 5/6 before the isolated X_NEG diagnosis; 0/25 ROI hit/miss disagreements |
| D | D2 | `3d0e4c59c0e33e4c21e34bbd54d1771c3db83415`, parent `c3482ff55deea4869d86119e65483f8cce17b767`; PID 6400, exit 0, 6.909 s; run `091f1e1d001e4b06b22bc64de3382492`; stdout SHA-256 `61759eefdd8770a1f13f63bbc26419fb6583af4c881047634487c925144e5b2a`; stderr empty | D2 refined 4 cells / 8 parent tetrahedra, used 8 additional volume-derived samples and 0 canonical-SDF resamples; 8 roots were recorded but 0 refinement patch triangles were emitted. Equal X+ topology remained 13 opens, with 43 required adjacencies missing and 24 triangles rejected below cutoff; mixed X+ combined ROI recorded 35 opens. Nonmanifold count remained 0. Full materialized-volume hash before/after/reload stayed `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`; payload hash stayed `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`. | 6/6; X_NEG mesh hash returned to exact baseline; 0/25 ROI hit/miss disagreements |
| D | D3 | Pinned source `7d058899abc1663ff7d4175b5a508532367cd5da`, parent `3d0e4c59c0e33e4c21e34bbd54d1771c3db83415`; D2-only activation is gated to `ATTEMPT_D2` | Not started. Three distinct editor-import preflight reservations were durably blocked before process creation by the runner's required 6-GiB commit-headroom gate. No Godot PID, import, `--check-only`, or D3 geometry event exists. The D3 geometry attempt remains unused (not a geometry failure). | Not evaluated |

A2's canonical roots satisfy only the experiment's recorded numerical residual bound; they do not establish seam closure because no candidate refinement triangles were emitted. A3's empty equal-LOD patch was written as an artifact but did not change the geometry. The JSONL `R96R1_COMPLETE` events with `failure_count=0` mean the probe completed; the topology artifacts are the acceptance oracle and fail the target.

### D1 X_NEG causal reconciliation

`evidence/continuation/D_XNEG-diagnostic/D_XNEG_PROBE-D_XNEG_root_order_diagnostic.json` and the raw process output classify the drift as `NUMERIC_ORDERING_DRIFT_CORRECTED`, not a volume or SDF change. Signed string ordering had reversed endpoint order relative to baseline numeric global endpoint ordering. The diagnostic records 129 binary64 interpolation-parameter differences and 28 binary32 root-coordinate differences in the pre-fix comparison. With the numeric global endpoint order restored, baseline and corrected X_NEG positions, normals, indices (3,444 elements each) and mesh digest `9f988ba69b8143ad46ebe6c5edcfa642743c6a5de09f7fb405f86ad42516f810` are exact matches. Volume payload is byte-identical: 3,021 bytes, SHA-256 `8b27477922574a73b6b2c04a619a16bdf877e27d4d5f1e6ba7284dc7e6a510a8`. D2's six controls then pass. No SDF, materialized volume, or cutoff change was made.

### A3 preflight and D3 hard stop

The first A3 `--check-only` at source `577d22d6d7fa9c83d822a242cfaf7e002c78810f` found two parser total-return errors in the new test helper functions. No geometry ran at that SHA. The correction added explicit terminal returns and updated the probe's physical helper pin; it was committed and pinned as `fc6690edb6ac0fd605de3e78814df724e9c72e47`. On that corrected SHA, import and `--check-only` passed before the single A3 geometry run.

D3's three runner snapshots recorded free commit of 6,272,749,568; 6,315,536,384; and 6,184,431,616 bytes, each below the required 6,442,450,944 bytes. A later read-only current-status sample at `2026-10-29T17:56:24Z` measured 6,061,936,640 bytes using the runner-equivalent formatted CIM counter (380,514,304 bytes below the gate), 22,894,552 KB physical available, 126,719,180,800 bytes free on C:, and zero Godot processes. This sample is observational only, not a fourth runner reservation. No WSL or user process was terminated. The D3 resource precondition remains unmet; the campaign hard-stops here under the explicit safe-execution gate.

### Aggregate final fields

- `ENVIRONMENT_STATUS`: `HARD_STOP_RESOURCE_GATE`; physical RAM and disk requirements passed, but formatted Windows commit headroom remained below 6 GiB at all three D3 reservations and the final observational check.
- `TOPOLOGY_GATE_STATUS`: `PASS` — previously pinned 50 assertions, 0 failures. It validates the shared topology diagnostic only; it does not certify either geometry candidate.
- `A_ATTEMPTS_USED`: `3/3` geometry attempts (A1, A2, A3).
- `D_ATTEMPTS_USED`: `2/3` geometry attempts (D1, D2); D3 source is pinned but D3 geometry is not started.
- `A1_RESULT`: `PARTIAL`; controls pass, equal/mixed X+ fail as previously recorded.
- `A2_RESULT`: `FAILED_TARGET`; 7 root candidates and bounded refinement evaluation, 0 refinement triangles, mesh unchanged, 8 equal X+ opens.
- `A3_RESULT`: `FAILED_TARGET`; equal patch is a zero-triangle shared contour with 8 opens; mixed zipper rejects below cutoff and emits no bridge.
- `D1_RESULT`: `PARTIAL_WITH_CONTROL_REGRESSION`; X_NEG hash issue diagnosed before D2.
- `D2_RESULT`: `FAILED_TARGET`; exact materialized volume/reload preserved; 13 equal X+ opens, 43 missing required adjacencies, 24 cutoff drops; mixed combined ROI 35 opens.
- `D3_RESULT`: `NOT_STARTED_RESOURCE_GATE`; not a geometric result.
- `D_XNEG_DIAGNOSIS`: `NUMERIC_ORDERING_DRIFT_CORRECTED`; D2 X_NEG control hash matches baseline exactly.
- `XPLUS_EQUAL_FINAL`: A=8 internal opens, 0 nonmanifold; D=13 internal opens, 0 nonmanifold.
- `XPLUS_MIXED_FINAL`: A3 10/22 contour edges, no emitted patch, 32 combined base opens; D2 10/22 contour edges, no conforming interface, 35 combined opens.
- `NEW_VERTEX_COUNT`: A2 recorded 7 root/Steiner candidates, D2 recorded 8 roots; neither produced refinement patch triangles. A3 emitted 0 new interface vertices/triangles. No new interface vertex is part of a successful final mesh.
- `MAX_SDF_RESIDUAL`: `1.35421752933684e-06` in A2 candidate root diagnostics against a test-only bound of `1e-4`. D2 did not resample canonical SDF; A3 canonical surface checks invalidated the empty patch, so no residual is claimed for A3.
- `MAX_VERTEX_DISPLACEMENT`: `2.81657012237702e-05` in the A2 test-only root construction. It is not a product geometry tolerance.
- `NORMAL_DEVIATION`: `NOT_MEASURED_FOR_A_VALID_NEW_PATCH`; there was no conforming emitted patch to compare.
- `NONMANIFOLD_COUNT`: zero in the reported equal-LOD target meshes; the target still fails because open edges and required adjacencies remain.
- `RAY_ROI_RESULT`: A2, D2, A3 each 0/25 ROI hit/miss disagreements; no PhysicsServer result is claimed. D3 not run.
- `CONTROL_MATRIX`: A attempts 6/6 per attempt; D1 5/6, D2 6/6 after isolated X_NEG numeric-order correction; D3 not evaluated.
- `DETERMINISM_RESULT`: source, run IDs, root identity probes, artifact checksums and D2 volume-before/after/reload identity are verified within each run. No same-source repeated geometry run was performed; repeated-run determinism remains unmeasured.
- `PERFORMANCE`: headless process elapsed A2 6.801 s, D2 6.909 s, A3 6.502 s. A3 interface helper measured 2,135 microseconds for equal shared-contour handling, 1,340 microseconds before mixed-strip rejection, and 1,644 microseconds for the historical X+ proxy. These are single-run diagnostic timings, not performance acceptance.
- `FULL_VALIDATION_RESULT`: `NOT_RUN`; no candidate survived geometry acceptance. No full E2E or `scripts/validate.ps1` pass is claimed.
- `EVIDENCE_INTEGRITY`: public evidence and local continuation evidence are inventoried by the adjacent SHA-256 manifests. Original R9.6/R9.6R1 evidence remains preserved.
- `FINAL_A_STATUS`: `ATTEMPTS_EXHAUSTED_WITH_GEOMETRY_TARGET_UNMET`.
- `FINAL_D_STATUS`: `HARD_STOP_BEFORE_D3_GEOMETRY`; two geometry attempts executed, D3 not started due the explicit resource gate.
- `RECOMMENDED_ARCHITECTURAL_DECISION`: do not adopt A2, A3, or D2 in production. A2 creates no closure triangles; A3 does not bridge equal or mixed LOD; D2 preserves volume identity but leaves required topology unrealized. Resume D3 only on a later safe environment whose preflight passes; no production adoption follows from this evidence.

The existing 50-assertion shared topology gate is not equivalent to the R9.6 geometry target. Full frozen E2E and `scripts/validate.ps1` remain NOT RUN. No production files, user saves, schemas, merges, releases, native components, Issue #108/#154, or F2-G1 state were changed. All five F2-G1 holds remain unchanged.

**Continuation status:** `P3_1_R9_6R1_HARD_STOP_WITH_EVIDENCE`.

### D3 resource-gate follow-up after continuation resume (2026-10-29)

A fourth D3 import preflight reservation was made after an observational counter was initially misread as free commit. The runner itself is authoritative: it computes CommitLimit minus CommittedBytes. Reservation D3_IMPORT_RETRY3 records 6,063,943,680 bytes free commit, 378,507,264 bytes below the 6,442,450,944-byte gate. It wrote HOST_GATE_BLOCKED_NOT_STARTED before process creation (runner exit 21); no Godot PID, import, --check-only, or geometry process exists for this reservation. Physical RAM and C:/TEMP space passed their gates.

A correctly computed read-only observation at 2026-10-29T18:05:56.7706917Z measured 6,221,414,400 free-commit bytes, still 221,036,544 below the threshold, with 21,880,569,856 physical-available bytes and zero Godot processes. The earlier formatted AvailableBytes value (21,970,006,016) is not the runner free-commit metric; it must not be interpreted as clearing the gate. No WSL or user process was terminated. D3 remains unstarted and its geometry attempt is unconsumed. This resource hard stop prevents safe D3 execution; it is not a D3 geometry failure.

The local continuation inventory now covers 254 files (250 previously listed plus the four files from this blocked reservation), all hash-verified. The public evidence inventory adds the durable reservation, process record, and sanitized host-resource summary; raw host snapshots remain in the protected owner-local evidence root.

### Final bounded D3 gate (2026-10-29)

The final current-state preflight showed free commit had materially decreased since the prior observation, so one final runner reservation was justified. At 18:40:14.896753Z, CommitLimit was 78,499,172,352 bytes and CommittedBytes was 72,840,966,144, leaving 5,658,206,208 bytes: 784,244,736 below the 6-GiB gate. Physical available RAM was 22,661,373,952 bytes; C: and TEMP each had 125,926,252,544 bytes free; no Godot process was running. The pagefile was not automatically managed (allocated 9,487 MB, current use 1,423 MB, peak 1,958 MB).

The runner created reservation D3_IMPORT_FINAL and returned exit 21 with HOST_GATE_BLOCKED_NOT_STARTED. Its post-runner sample was 5,649,481,728 free-commit bytes, still below the gate. No process/PID, import, check-only or geometry process was created. The safe-action policy prohibited terminating WSL or owner applications, and no pagefile setting was changed. The free-commit metric declined materially from the earlier 6,221,414,400-byte observation, so no further identical reservation or polling is appropriate. D3 remains unconsumed; this is the final resource hard stop, not a geometry failure.

The local continuation inventory now covers 258 files (254 prior plus four D3_IMPORT_FINAL runner records/snapshots); the public inventory adds the reservation, process record and sanitized resource summary. No D3 source or production file changed.
### User-requested final D3 preflight (2026-10-29)

After the direct request to execute the attached procedure, a bounded current-state check at 18:55:28.7238452Z showed 5,904,932,864 free-commit bytes, below the 6-GiB requirement. This was materially different from the previous final record, so one runner revalidation was made. At reservation time 18:55:43.6738775Z, CommitLimit was 78,499,172,352 bytes and CommittedBytes was 73,018,421,248 bytes, leaving 5,480,751,104 bytes: 961,699,840 below the 6,442,450,944-byte gate. Physical RAM was 23,372,312,576 bytes; C:/TEMP each had 125,918,076,928 bytes free; no Godot process was running. Pagefile auto-management remained false (allocated 9,487 MB, current use 1,551 MB, peak 1,958 MB).

The runner recorded D3_IMPORT_USER_RETRY and exited 21 with HOST_GATE_BLOCKED_NOT_STARTED before Process.Start. Post-runner free commit was 5,453,905,920 bytes. No D3 process/PID, import, check-only, or geometry run exists. The resource state declined by 424,181,760 bytes from the immediately preceding observation. No process was terminated, and no pagefile setting was changed. This was the single bounded retry after a material resource change; no further identical retry is appropriate. D3 remains unconsumed and not a geometry failure.

The continuation-local inventory now covers 262 files (258 prior plus four runner records/snapshots); public evidence adds its reservation, process record, and sanitized summary. The original evidence root remains unchanged.