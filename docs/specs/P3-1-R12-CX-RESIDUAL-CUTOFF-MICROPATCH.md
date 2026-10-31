# P3.1 R12-CX — Residual Cutoff Micro-Patch Preregistration

Date: 2026-10-31

Status: experimental, pre-geometry; CX remains unconsumed until the frozen campaign emits one machine-readable target result.
Base: R12-C final source `619a43a795cae3e2e9926a5a29554da009fbe2c1`; parent `4535f4c965db67adab7c93e448492c54be916c92`.

## Scope and hypotheses

This is the sixth and final valid R12-C geometry hypothesis, named `R12CX_RESIDUAL_FIELD_CONSTRAINED_MICROPATCH`. It addresses only the three fixed-C6 residual faces. It preserves all 369 C6 topology roots, 870 arcs, 502 source-face obligations, original root coordinates, exact topology round-trip, Candidate D volume, fixed ROI/ray oracle, and strict `cross_squared > 1e-12` cutoff. It is test-only; production adoption and merge are not authorized.

The bounded implementation currently tests edge-flip-only local cavity replacement. The support-vertex candidate and selected-support caps are both zero. This does not claim field-derived support generation; if the bounded edge-flip profile cannot clear the residuals, CX returns a target failure or partial result and is consumed only when the frozen algorithm emits that result. No fallback or second CX attempt is planned.

## Frozen input identities

| Input | SHA-256 |
| --- | --- |
| Candidate D (`p3_1_r9_2_candidate_impl.gd`) | `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a` |
| Manifest and R9.2 E2E inputs | `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972` |
| Topology fixture | `33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d` |
| Canonical topology | `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95` |
| Graph fingerprint | `a5dd11828284aaaa9ee5204a667b1c4b39e7f584de34205b236413682e7dddb9` |
| Volume / payload | `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2` / `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0` |
| Ray fixture | `9780bea4b1609bbc89db45e21d8671170198ca01d1ad3e252b9f877a64eb62c7` |
| Godot 4.7.2 executable | `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` |

The corrected residual fixture SHA is `ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23`. Its only semantic difference from the earlier generated fixture is correction of the Candidate D digest field, which previously contained a transcription error. Three residual records, C6 mesh identity, topology, volume, payload and revision remain unchanged. The earlier artifact and attempts are retained as evidence.

## Preregistered local search bounds

- Residual defects: exactly 3; at most 3 disjoint/overlap-merged cavities.
- Cavity growth: L0 through L3 only; no automatic expansion beyond L3.
- Maximum cavity/replacement domain: 64 triangles.
- Search: at most 4,096 states per cavity, at most 12,288 total across three cavities, and 32 retained solutions per cavity.
- Aggregate search wall-time: 10,000,000 microseconds; total realization wall-time: 30,000,000 microseconds.
- New support candidates and selected support vertices: 0 in this edge-flip-only profile.
- The existing cutoff remains strict `cross_squared > 1e-12`; geometric oracle epsilon remains `1e-9` where used by the frozen implementation.
- Any state/time/cavity bound that interrupts an otherwise valid search is `PARTIAL`; exhaustion of the declared finite L0–L3 edge-flip domain without a valid patch is a target failure, not a proof of global infeasibility.

The search preserves cavity boundary signature, blocks required topology arcs and locked C6 realization triplets, validates full-mesh obligations/manifold/winding/cutoff state, and rejects changed C6 roots. No centroid or unconstrained support is introduced.

## Sequential gates

P1 exact source/commit/tree and physical hashes; P2 topology fixture; P3 exact C6 artifact reproduction; P4 residual fixture; P5 cold import; P6 campaign `check-only`; P7 realizer `check-only`; P8 the pinned-source contract suite, including physical residual-fixture digest/schema assertions and JSON-decoded root-position reconstruction. None consumes CX. The assertion total is recorded for the exact corrective source commit rather than assumed here.

Only after P1–P8 pass on one exact committed source may the reserved `R9.2.SEAM.XPLUS_EQUAL.v1` target be invoked once. `R12CX_TARGET_INVOCATION_BEGIN` records entry to target preparation; it does not prove that the geometry hypothesis ran. The realizer emits `R12CX_LOCAL_PATCH_SEARCH_BEGIN` immediately before the first bounded cavity search and carries `cx_algorithm_started=true` through its result. A failure before that marker is a pre-geometry tooling failure: it writes only a no-overwrite `P3.1.R12CX.PreGeometryFailure.v1` receipt, exits nonzero, emits no terminal geometry result, and does not consume CX. Once local patch search starts, a machine-readable terminal geometry result consumes CX even if it is `PARTIAL`, `FAILED_TARGET`, or `FAILED_WITH_REGRESSION`. No rerun is allowed after such a result.

The first target invocation (`CX_GEOMETRY_FINAL01`, source `a2a01b2…`) failed while rebuilding the frozen C6 triangles: JSON-decoded root positions were arrays, but the realizer assigned them directly to `Vector3`. The stack stopped in `_build_triangles`; no patch-search begin marker or search nodes were recorded. The harness's former generic `FAILED_WITH_REGRESSION` classification overstated the evidence. That attempt is retained and classified as pre-geometry tooling failure, not a valid CX geometry result. The corrective source explicitly accepts only a `Vector3` or a three-component JSON array, rejects malformed representations, preserves the local-search start state, and distinguishes measured structural regressions from an unmeasured preparation failure.

The second invocation (`CX_GEOMETRY_FINAL02`, source `949ceedf…`) also stopped before local search and did not consume CX. Its immutable receipt reports `cx_algorithm_started=false` and `cx_fixture_to_base_rejection_mismatch` for triangle `60,8,25|tet:1|c4-source:0`. Inspection showed a second adapter/schema defect: the pinned C6 artifact represents a cutoff rejection using `triangle_id`, `source_polygon_ids`, and `root_ids`; the CX adapter instead looked for nonexistent `polygon_id` and `triangle_root_ids` members. The correction matches all three actual C6 identity fields and retains the root-set comparison. A focused synthetic contract test uses the C6 field names, checks reconstruction of a sub-cutoff source triangle, and rejects a mismatched root set. FINAL02 is retained as pre-geometry tooling evidence; no `R12CX_LOCAL_PATCH_SEARCH_BEGIN`, search states, or terminal geometry result exists.

The third invocation (`CX_GEOMETRY_FINAL03`, source `07c93797…`) reached C6 triangle reconstruction but stopped before local search with `cx_fixture_cutoff_area_mismatch`; CX remains unconsumed. The exact C6 artifact reports `2.77538984903934e-15` for the first residual, while the pinned residual JSON annotation stores `2.77e-15`. The prior check incorrectly required a `1e-12` relative match from the rounded annotation. The correction treats the reconstructed triangle and exact C6 `cross_squared` as the geometry authority, checks those at the existing tight arithmetic tolerance, and separately bounds the pinned diagnostic annotation to 0.5% while requiring it to remain finite, positive and below the unchanged `1e-12` cutoff. The fixture bytes and digest remain unchanged. Contract regressions accept a representative 0.2% rounding difference, reject a 2% stale annotation, reject mismatched exact C6 area, and reject nonfinite annotation or C6 values. FINAL03 is retained as pre-geometry evidence; no local-search marker, search nodes, or terminal geometry result exists.

After a complete equal-LOD pass, the campaign runs the six frozen controls, the 25-ray ROI oracle, and verifies unchanged volume identity. Mixed LOD is gated after those checks. The frozen input currently lacks an explicit shared interface owner/path; the harness fails closed rather than publishing independently extracted coincident surfaces. If that blocker remains, R12-C closes exhausted and deterministic repeat, full E2E and full validation do not run, per the approved gate order.

All timing/resource values remain diagnostic and `UNSCORED`; headless timings are not presented-frame or GPU evidence. No product geometry tolerance is claimed.

## Safety and status

No production path, save/schema, user data, PR #207–#210, native dependency, or protected F2-G1 state is changed. The five protected-state holds remain active. This preregistration alone authorizes no geometry execution; the user authorization for the bounded R12-CX campaign is in the attached task.
