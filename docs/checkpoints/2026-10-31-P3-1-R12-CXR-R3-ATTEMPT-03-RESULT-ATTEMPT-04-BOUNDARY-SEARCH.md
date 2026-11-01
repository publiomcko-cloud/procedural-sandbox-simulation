# P3.1 R12-CXR R3 attempt 03 result and attempt 04 boundary-search correction

## Attempt 03 disposition

The frozen target `R3_TARGET_20261031_03` was invoked exactly once for `R9.2.SEAM.XPLUS_EQUAL.v1` using Godot `4.7.2.stable.official.ed1daf0bf` and execution checkout `aa9a6dc5c562cd707cacde3e95364941ded076d9`. The measured R12-CXR code remains `c1dce7e2a410e439dbf82e5252a8e333d0621642`. The process started (Godot PID 38020, parent PID 30192), emitted `R12CXR_TARGET_INVOCATION_BEGIN`, and exited 2 after 3.94 seconds. This is not a geometry result: the failure receipt reports stage `BEFORE_LOCAL_PATCH_SEARCH`, `cx_bounded_patch_search_failed`, `cx_algorithm_started=false`, and `consumes_cx_hypothesis=false`. No support candidates, triangulation search, or geometry qualification ran. Attempt 03 is preserved and will not be rerun.

The receipt records two original cavities and four boundary levels each. Neither cavity had a valid boundary at L0–L3. Frozen edge diagnostics show that the current boundary builder rejects edges with one removed face and two surviving C6 owners even when those two owners have opposite directions and therefore form an intact closed edge in the surviving mesh. Other expanded levels contain branch/open-boundary diagnostics. Therefore simply changing the 1:1 incidence check is insufficient; boundary selection must search bounded connected patch subsets and retain the existing whole-mesh topology gates.

An offline exploratory read of the captured incidence diagnostics found a candidate four-triangle subset for the first cavity at L2, but no matching simple-cycle subset for the second cavity within its captured L3 patch. These observations are diagnostic only: they did not execute the candidate algorithm, generate geometry, or qualify a support realization. They are not evidence that the field-support hypothesis passes or is exhausted.

The inner dispatcher captured Godot exit 2, complete output, process identity, durable launch records, and seven memory samples. Minimum free commit was 9,830,916,096 bytes; the 2 GiB stop-loss did not trigger. Pre-existing `.gd.uid` files (57) remained byte-identical. Godot produced 67 additional untracked `.gd.uid` files during the run; they are preserved and are not staged. The outer nested PowerShell wrapper reported exit 0 despite the inner dispatcher/Godot completion record showing exit 2. Raw evidence remains intact; the next invocation will launch the dispatcher directly as a PowerShell process, removing this wrapper layer.

## Attempt 04 bounded correction plan

Keep the frozen source field, topology roots/arcs, Candidate D, volume, cutoff, ROI oracle, cavity seed identities and L0–L3 limit unchanged. Replace only the R3 full-radius-union patch choice with deterministic enumeration of connected patch subsets drawn from each frozen L0–L3 neighborhood. Rank by level, then patch cardinality, then sorted triangle IDs. Derive the interface from the remaining C6 owners: one surviving owner defines an oriented interface edge; two surviving owners are accepted as closed only when oppositely directed and are not interface edges; same-direction pairs and incidence above two remain invalid. Zero surviving owners are not invented as interface constraints; the final full-mesh incidence, winding, manifold, topology-round-trip, cutoff and field-volume gates remain authoritative.

Count boundary-subset states against the already preregistered 32,768 per-cavity search-state cap; retain the existing 64-triangle patch, L0–L3 radius, support-candidate, support-selection, triangle, wall-time and solution-retention caps. If any cap is reached, report PARTIAL with exact counters, never exhaustion. Add synthetic positive/negative boundary tests and a fixture reproducing the captured incidence pattern. The correction must pass editor import, the complete CXR contract suite, campaign check-only, and the pre-target source/input gates before attempt 04 is frozen. If the second cavity still has no valid simple boundary after exhaustive bounded selection, preserve that as a concrete per-cavity topology-domain blocker; do not weaken the final mesh gates or silently merge the cavities.

## Evidence

Raw attempt and dispatcher evidence: [`r3_target_attempt_03`](../reports/P3-1-R12-CXR-R2-R3/evidence/r3_target_attempt_03/). Its `evidence-sha256-index.txt` inventories all copied raw files and host-launcher records. The attempt remains classified `PRE_GEOMETRY_TOOLING_FAILURE_HYPOTHESIS_NOT_TESTED`.

## Scope and holds

This is bounded experimental research only. No production source, save/schema, user save, merge, release, Issue #108/#154, or F2-G1 protected operation is authorized. PRs #213/#214 remain draft and unmerged. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.
