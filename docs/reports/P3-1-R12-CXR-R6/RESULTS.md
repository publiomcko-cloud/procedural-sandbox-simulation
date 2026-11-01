# P3.1 R12 CXR R6 realization-map cavity — results

**Disposition:** `BLOCKED_WITH_EVIDENCE` at R6-D. The bounded causal cavity search exhausted its finite candidate set for the pinned fixture without finding a boundary-feasible cavity. This is not a claim of global infeasibility.

**Issue:** [#218 — R6 realization-map cavity](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/218)  
**Source branch:** `exp/p3-1-r12-cxr-r6-realization-map-cavity`  
**Draft code PR:** [#219](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/219)  
**Draft docs/evidence PR:** [#220](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/220)  
**Source SHA:** `836a2cd8e681dfb35f0bbaa5f1f55b1bfcc59b0f`  
**Parent:** `69648002dc961301cbf789107453a718a206ca64`  
**R5 baseline:** `64a14d7bc8ddf024933129767b6889146d4645c4` (PR #217 head at observation)

## What completed

- Implemented the R6-A representability audit and R6-B/C owner selection and canonical boundary-arc rules, then integrated the bounded R6-D cavity search and R6-E/F support realization path. R6-E/F are gated on a boundary-feasible D result and did not start in the final target run.
- R6-D starts from the pinned R4 six-face cavity. Expansion adds only causally adjacent surviving faces across currently unrealizable boundary edges. Every candidate is checked for patch connectivity, boundary cycles, continuous zero-facet upper bounds, and a strict in-domain witness. Candidate ordering is deterministic and uses removed-face count, blocked-edge count, descending minimum margin, boundary-component count, then stable IDs.
- The R6 campaign reproduces the frozen R5 cavity fixture byte-for-byte (fixture SHA-256 `a54a407ac84b3fd7d64108f41457d5ecc7ff335abaee6899819de579ebeae6a6`), with six faces and six boundary edges. It leaves R5 geometry unchanged.
- R6-A audit at the final source SHA reports `R6_A_REPRESENTABILITY_PARTIAL`: 1,666 occurrences; 1,564 corrected/accepted; 849 changed positions; 97 corrected residual-over-epsilon rows; 8 corrected barycentric failures; 8 occurrences unresolved within the permitted ±2 ULP search. `target_attempt_consumed=false`; no global infeasibility claim is made. Full audit: [R6-A final audit](evidence/attempts/r6-a-audit-836a2cd.json).
- Final R6-05 D search returned `EXHAUSTED/FINITE_CAUSAL_SEARCH_EXHAUSTED`: 844 states examined, 1,254 generated, queue empty, 28,811 ms. The best-ranked state remained the initial six-face patch; four of its six boundary edges had no strict interior witness. No state, queue, or wall-time cap was hit. Full accounting and corrections: [attempt accounting](ATTEMPT-ACCOUNTING.md); raw result: [R6-05](evidence/attempts/r6-target-attempt-05.json).

## Target-attempt accounting

Four of five valid target attempts were consumed (R6-02 through R6-05). R6-01 stopped before geometry due to a tooling inventory mismatch and is not consumed under the procedure's pre-geometry correction rule. R6-02's raw `target_attempt_consumed=false` field is corrected by the accounting addendum because its bounded D search did start and reached the wall cap. One valid target attempt remains unused. No new attempt is justified after the finite search exhaustion without an owner-approved change to the scientific search envelope or target.

The five R6-A audit artifacts and all target outputs/logs are preserved under [evidence/attempts](evidence/attempts/). SHA-256 values and byte lengths are in [SHA256SUMS.txt](evidence/attempts/SHA256SUMS.txt), whose own digest is [SHA256SUMS.txt.sha256](evidence/attempts/SHA256SUMS.txt.sha256). Raw output artifacts were not rewritten to repair the accounting field.

## Verification and evidence grades

All commands were sequential, headless, on Godot `4.7.2.stable.official.ed1daf0bf` at `C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe` (SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`). Each listed command exited 0:

- Cold import: `--headless --editor --path . --import --quit` — L1.
- R6-A check-only audit — PASS — L2.
- R6 campaign check-only — PASS — L2.
- R6 contracts — 49 assertions, 0 failures — L2.
- R5 contracts — 348 assertions, 0 failures — L2.
- CXR contracts — 216 assertions, 0 failures — L2.

The R6 target runs and archived structured outputs are L2 evidence. No independent source review (L5), owner GUI/visual acceptance, runtime scene acceptance, equal-LOD gate, later controls/rays/reconfirmation/mixed-LOD/repeat tests, full end-to-end validator, or `scripts/validate.ps1` run is claimed. The headless scripts do not establish owner acceptance, production readiness, or a merge decision.

## Scope and limits

No external dependency, plugin, native extension, network service, or binary download was added. The implementation is first-party GDScript. This result covers the pinned R6 fixture, finite causal-search envelope, and commands recorded here. It is not a global proof that no cavity exists, not an architecture approval, and not merge authorization. Protected F2-G1/Hyper-V/host-ACL activity remains outside this functional issue and unauthorized.