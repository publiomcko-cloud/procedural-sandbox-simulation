# P3.1 R12-CXR R3 attempt 04 partial runtime failure

Date: 2026-10-31 America/Sao_Paulo; process times are UTC.

## Identity and preservation

- Repository origin: https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git
- Last verified main: 5997a76d345f45bf86edfe83f690336391e8be27
- Branch: exp/p3-1-r12-cxr-per-cavity-continuation
- Code source: 2964bd55b5691081bfe4db9c421f3b982fee167b; direct parent 27c88a78aff8aef0af8a69c041f90ddcf2ac502e.
- The source code was executed from detached checkout C:\r12cxr-attempt04-2964bd5, with origin and tracked source pins verified.
- PR #214 remains OPEN/DRAFT/UNMERGED. PRs #212 and #213 also remain OPEN/DRAFT/UNMERGED. The docs-only pretarget freeze commit is c2aa71318e92f593ba96d792ac976624d6b1adef.
- Both stashes, unrelated work, and generated/untracked .gd.uid files remain preserved.

## Exact attempt result

The frozen scenario R9.2.SEAM.XPLUS_EQUAL.v1 was invoked exactly once as attempt R3_TARGET_20261031_04. The dispatcher PID was 44380 and Godot PID 31504; Godot's recorded parent PID was 44380. Source and fixture hashes were revalidated before launch. Godot exited 0 after approximately four seconds, did not time out, and the resource stop-loss did not trigger; seven commit-memory samples were captured. Exit 0 is not a pass: Godot emitted a SCRIPT ERROR, and the result is R12_CXR_PARTIAL_WITH_EVIDENCE.

The first causal error is at p3_1_r12_cxr_field_support_realizer.gd:911: a value returned by adjacency.get(...) is a Dictionary, but the R3 subset expansion assigns it to a typed Array. The base _adjacency() implementation creates dictionary-of-dictionary neighbor sets, so the value type is source-confirmed. The new branch that expands a subset beyond the initial seed was not covered by the existing one-triangle success test.

The raw result's verified counters show: target algorithm started; both cavity patch-selection searches started; two patch-selection nodes; zero field-support candidate attempts; zero generated candidate triangles; candidate and support stages in both cavities are NOT_RUN. Therefore this run does not establish geometric feasibility or infeasibility of the constrained field-support realization. It is a bounded R3 runtime implementation failure before support-candidate generation. Attempt 04 is consumed and must not be rerun.

## Evidence and next step

Raw process records, full stdout/stderr, resource samples, the result JSON, wrapper-preflight issue, and checksum inventories are preserved under the attempt 04 evidence directory. The authoritative correction to an initially incomplete derived summary is attempt-analysis-correction.json; evidence-sha256-index-v2.txt verifies the directory contents. The earlier four-byte preflight.json and its explanation are preserved; the wrapper preflight failure occurred before dispatcher or Godot launch.

The bounded next source correction is to read adjacency row keys, sort them deterministically, and add a contract regression that forces a multi-node connected-subset expansion. It must be a new source SHA. After import, CXR contract tests and check-only pass, a new attempt ID may be used for the frozen target; attempt 04 remains untouched. No controls, ROI rays, volume-following gates, mixed LOD, deterministic repeat, E2E, or scripts/validate.ps1 ran because the equal-LOD gate did not pass.

All work remains test-only. No production code, schema, save, Issue #108, PR merge or release work occurred. Preserve CURRENT_PROTECTED_STATE_UNKNOWN, V3_NOT_ATTESTED, ACL_REVIEW_REQUIRED, G1_BLOCKED_ENVIRONMENT, and F2_G1_RELEASE_HOLD.