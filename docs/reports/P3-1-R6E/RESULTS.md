# P3.1 R6-E — Exact-density causal investigation

## Disposition

`P3_1_R6E_READY_FOR_INDEPENDENT_REVIEW` — test-only correction on an isolated experiment branch. This result does not adopt R5-E into production and does not authorize any merge.

| Identity | Value |
|---|---|
| Repository | `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git` |
| Branch | `bench/p3-1-r6e-causal` |
| Parent/base | R5-E `7646dfdeb2e6cdfe51407f8f25957a61a75abe1b` |
| R4 ancestor | `051249642611a7fa9cd2006be450bad0e184e4ee` |
| Production reference | `92b442d7f5b605c7bc9c48fac2aceea9d71813aa` |
| Godot | `4.7.2.stable.official.ed1daf0bf` |
| Godot binary SHA-256 | `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643` |

## Cause

Canonical `Brush.sample_density_snapshot` first evaluates the base field through the mapped `(region_key, local_position)` pair, then reconstructs world position from that pair before evaluating ordered brush distances. The old R5-E candidate evaluated the same base density but measured each brush distance from the original raw world query. At negative/nonzero region coordinates, `world_to_region_local` followed by `region_local_to_world` can change a `Vector3` component by one or more float32 ULPs. The raw and reconstructed positions therefore produce different Euclidean distances and bitwise density results.

All 16 frozen R5-E final-density failures were reproduced exactly. The detailed per-probe CSV and JSONL-style raw diagnostics include world/local/reconstructed coordinates, region, binary32 coordinate bits, binary64 densities/distances, operation sequence and mode, radius/center, prune cutoff/guard, skip decision, and replay with pruning disabled.

The first replay divergence for all 16 was operation sequence 0, `CARVE`; none of those operations was skipped. The unpruned old replay retained the mismatch, while the corrected pruned and unpruned replays both matched the canonical result. The correction uses the canonical reconstructed world point for both the displacement vector and exact distance in the R6 prototype's instance and static evaluation paths.

## Hypothesis disposition

| Hypothesis | Finding |
|---|---|
| A. Base-field coordinate transformation differs | Rejected for these failures. Canonical and candidate base-density values match before brush replay; canonical coordinate remapping matches the candidate's mapped path. |
| B. Float rounding invalidates the conservative cutoff | Not the cause of the 16 failures. The ULP difference is in the raw-versus-reconstructed distance input; no failing operation was skipped, and disabling pruning preserves the mismatch. |
| C. Oracle/snapshot inputs differ | Rejected for this fixture. The canonical and projected center/radius/mode arrays are equal, order is preserved, and the first differing state is the distance result at sequence 0. |

The minimal one-command fixture reproduces the same contract defect without an 8,192-command ledger. It uses the first frozen operation at sequence 0 and a query equal to its center. The raw query `(-0.119999997317791, 2.09999990463257, -0.159999996423721)` reconstructs to `(-0.119999885559082, 2.09999990463257, -0.159999847412109)` through the canonical region/local mapping. The corrected density is bitwise identical to the canonical evaluator; the old raw-coordinate distance differs.

## Validation evidence

- Focused diagnostic: exit 0, `R6E_RESULT status=PASS`, 8,192 operations, 796 probes, 16/16 old mismatches reproduced, corrected candidate mismatch count 0, corrected full-replay/no-prune mismatch count 0, corrected prune-vs-no-prune mismatch count 0, snapshot arrays equal. The diagnostic also emitted an explicit record for each of the 16 failing probes.
- Existing R5-E exact regression after the correction: exit 0, 8,998 assertions, zero failures. LOD0 and LOD1 positions, normals, topology and density agree with the canonical reference; `lod1_density_mismatches=0`.
- Full `scripts/validate.ps1`: exit 0, 21,464 assertions, zero failures across L0-L2; elapsed 523,027 ms. Three existing colinear-camera `look_at` warnings were recorded. No parser, script, or runtime errors were found; the output itself says rendered pixels are not assessed.
- The R5-E single-process timing remains exploratory and is not a performance improvement: for the 796 probe set, canonical query p95 was 2,059 µs and optimized candidate p95 7,328 µs; LOD0 aggregate build was 4,116 ms candidate vs 1,884 ms reference, LOD1 23,211 ms vs 6,826 ms. The R6 change is a correctness fix, not a speed claim.

The complete focused, regression, and full-validation output, exit codes and durations are under [`evidence`](evidence/). The 16-row table is [`reproduced-16-probes.csv`](evidence/reproduced-16-probes.csv). Earlier parser/collector/diagnostic attempts are retained under `evidence/failed-attempts/` and are not counted as passing runs.

## Scope and limits

Only the R5-E experimental prototype under `game/tests/prototypes/` and an R6 diagnostic test were changed. No production SDF, ledger, storage schema, terrain scene, production mesher, native dependency or gameplay path changed. R5-E remains an experiment and its slower query/build measurements remain unresolved. This review does not establish GUI appearance, presented FPS, GPU completion, collision behavior, cache/production adoption, or geometry approval. No R5-V approximation or tolerance is accepted here.

All five F2-G1 operational holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.
