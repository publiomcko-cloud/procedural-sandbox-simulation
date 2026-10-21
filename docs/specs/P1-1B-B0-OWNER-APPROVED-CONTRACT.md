# P1.1B-B0 — Owner-approved experimental input and benchmark methodology contract

**Decision date:** 2026-10-21 (America/Sao_Paulo).  
**Baseline:** `main` `665c5c883ae88b949f4030f7affc786064999f61`, after verified PR #97 integration.  
**Disposition:** `P1_1B_B0_R4_R4A_OWNER_APPROVED_EXPERIMENTAL_INPUTS_ONLY`.  
**Execution:** `B1_1_IMPLEMENTATION_NOT_AUTHORIZED / BENCHMARK_EXECUTION_NOT_AUTHORIZED`.  
**Evidence:** source-only independent R4a PASS; **no** new Godot execution, target-hardware performance measurement, GPU/presentation measurement or artifact hashes.

## 1. What the owner actually approved

The owner explicitly answered **"autorizo"** to the decision to approve B0 **R4 + R4a** as the narrowly scoped experimental **scenario-input and measurement-methodology** contract and register that decision online. The approval does **not** authorize implementing or executing the B1-1 test-only benchmark harness; the two later permissions must be separate. Product acceptance budgets and hardware profiles remain undecided.

Binding document set and precedence:

1. This [owner scope decision](P1-1B-B0-OWNER-APPROVED-CONTRACT.md) governs authority and exclusions.
2. [R4a accepted corrective addendum](P1-1B-B0-R4A-ACCEPTED-ADDENDUM.md) supersedes the R4's direct-diagonal streaming input/outcome, edited-revisit classification and tunnel component oracle, **and nothing else**.
3. [Complete R4 source proposal](P1-1B-B0-R4-SOURCE-PROPOSAL.md) supplies all other input formulas, scenarios, event/statistics rules and geometry methodology without retroactively rewriting historical Codex text.
4. The [owner-approved P1.1 R2 architecture](../roadmap/P1-1-APPROVED-PLAN-R2.md) and current canonical source take precedence for SDF/ledger/ownership/resource invariants. Any discrepancy is a blocker for that scenario until resolved by a new owner decision.

**FROZEN in this decision means _owner-approved input specification_ only.** No generated canonical manifest JSON bytes, SHA-256 value, numerical SDF golden output or benchmark data is claimed. Each future executable instance must carry a versioned manifest generated from these approved definitions, have its bytes/hashes verified and pass separate implementation and execution gates.

## 2. Initial included input subsets

| Workload group | Disposition | Qualified scope |
| --- | --- | --- |
| `B0A` deterministic replay | **APPROVED INPUTS** | Isolated SdfBrushEditState ledger, global canonical ordering, seed 424242/generator 1, radius **0.58**, fixed integer-millimeter commands; count/revision 0/1/32/128/255/256; geometry/replay parity required |
| `B0S` streaming | **APPROVED INPUTS** | 3×3 desired, 5×5 retention, actual active vs loading vs publication, movement/face and settled three-leg loops; atomic `B0S.CORNER.DIRECT_ATOMIC_POS_POS.v1` replaces R4's continuous/ambiguous direct diagonal |
| `B0G` detached LOD | **APPROVED INPUTS** | Signed LOD0/LOD1 single-cell fixture, separately enumerated six faces, two edges and two corners, independent adjacent reference meshes, no production LOD or LOD≥2 |
| `B0G` tunnels | **APPROVED INPUTS** | Complete R4 seeded world-space synthetic field and widths 0.5/1/2 world units plus 1.84-world-unit canonical control, with R4a centerline-seeded tunnel component and separate exterior components; requirements to preserve features remain unset |
| `B0E` seam edit and `B0S` unload/reload | **APPROVED COMMAND/ROUTE INPUTS** | Fixed carve/fill and region/probe definitions from R4, subject to canonical ledger acceptance and correct replay; **edited LOD seam geometry scoring still excluded** until nonempty independent contour preflight |

Specific expected region counts after verified settled publication: cold origin **9**; one-axis move **12**; direct *atomic* (0,0)→(1,1) **14**, from the exact initial 9-key active set; three-leg positive/negative/mixed loop **9→12→15→16**. Pending requests are never counted as active. A failed/canceled stage is not a publication. Streaming expected key sets, not counts alone, are acceptance checks.

R4a tunnel connectivity checks: identify the **centerline-seeded** empty voxel component, verify openings at both X boundary planes, and separately record `C_top` and `C_bottom`. As a targeted future harness oracle requirement, verify that all valid centerline-seeded X slices are connected **along the tunnel** and report minimum cross-sectional clearance; a detour through exterior empty air cannot satisfy continuous cave preservation. This last guard is a source-review qualification for future test code and does not claim any executed result.

## 3. Excluded or incomplete scenario instances

Keep **`NOT_FROZEN` / NOT ELIGIBLE FOR EXECUTABLE ACCEPTANCE** until independently demonstrated and separately approved:

- `B0B.VIEWPORT.HISTORY.N001/N032/N128/N255/N256.v1`: observed 1.25-radius accepted click centers/outcome list/hashes do not yet exist; one fixed viewport pose may not yield 256 consecutive hits.
- `B0B.VIEWPORT.REMOTE.N032/N256.v1`: remote direct-preseed is specified, but fixed-viewport local hit and candidate outcomes still need preflight. Remote setup is **not** evidence of mouse-generated history.
- `B0S.WARM.REVISIT.EDITED.v1`: requires successful fixed-view click and verified command hash; no valid preflight has been run.
- Edited mixed-LOD seam **geometric scoring** until canonical edited input yields nonempty adjacent contours on both reference sides under an authorized validation.

No policy permits changing camera inputs or silently replacing failed real clicks with direct ledger injection to manufacture a PASS. Even the included definitions remain **unexecuted**.

## 4. Frozen protocol rules (methodology only)

- Canonical ordered command identity and manifest: integer millimeter coordinates/radii, convert at Godot boundary; RFC 8785/JCS canonical UTF-8 JSON, no BOM or trailing newline, SHA-256 lowercase hex; do not fabricate an absent digest.
- Pin exact source/harness/Godot identities, seed/version, event-IDs and clocks. Monotonic process-local microsecond durations, no subtraction across processes.
- Separate picker, ledger acceptance, queue, worker, ArrayMesh, coherent scene publication, GPU and actual presented frame. CPU scene publication is **not** pixels on screen. Optional unavailable GPU/VRAM/RSS/presentation metrics remain `NOT_AVAILABLE`/`UNSCORED` and do not invalidate otherwise valid CPU evidence.
- Preserve different scenario/cold/warm/device run distributions; nearest-rank p50/p95/p99/max; record exact sample n, cancellations, environmental invalids, and right-censored timeouts. Proposed runs/warmups/timeouts from R4 are **experiment method proposals**, not owner-adopted product thresholds or proof of reliable population p99.
- Geometry: separately report signed canonical SDF replay, contour/topology/winding/T-junctions, bidirectional sampled numerical surface distance, normal-angle error, screen-space evidence (only if rendered) and cave connectivity. Compare quality-matched vs resolution-matched results separately. No performance winner without equivalent geometry.
- Respect canonical `SdfWorld` v1/seed+generator, ordered `SdfBrushEditState` max 256, signed floor ownership, four in-flight CPU workers, two `ArrayMesh` creations per frame and at most 25 regions/400 chunks. Detached experimental LOD0/1 fixture only.

## 5. Decisions explicitly NOT made

| Dimension | Authority |
| --- | --- |
| Minimum/reference Windows hardware; CPU/GPU/RAM/VRAM/driver | **OWNER_TO_DEFINE** |
| Target renderer, display/viewport resolution, VSync/cap/power profile and controlled cache | **OWNER_TO_DEFINE** for scored results; static source renderer is GL Compatibility |
| FPS; p95/p99/max frame time, main-thread stalls, streaming/edit/publication/first-present latency | **OWNER_TO_DEFINE** |
| Process RAM/RSS and VRAM ceilings and permitted profiler/OS tools | **OWNER_TO_DEFINE** |
| World-space/screen-space surface error, normal angles, acceptable seam and thin/cave widths | **OWNER_TO_DEFINE**; topology checks remain hard source constraints |
| Data location, raw retention, privacy/collection tool permissions | **OWNER_TO_DEFINE** |
| B1-1 opt-in test-only source implementation | **NOT AUTHORIZED**; requires new express owner decision |
| B1-1 run(s), including exploratory `UNSCORED` | **NOT AUTHORIZED**; distinct later owner decision after source review |
| Voxel Tools acquisition/native execution; production LOD; ADR-0002; P1.1C | **NOT AUTHORIZED**, separate security, architecture and owner gates |

All five F2-G1 holds remain unchanged: `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, `F2_G1_RELEASE_HOLD`.

## 6. Next authorized handoff

**Permitted now:** documentary reconciliation and owner decision collection; prepare, but **do not implement**, a bounded B1-1 ticket constrained to test-only instrumentation/harness and a future owner-selected `UNSCORED` or scored measurement regime. The existing Windows development worktree and `stash@{0}` were not touched during online documentation.

**To authorize later:** owner separately approves B1-1 code paths and exact allowed runtime commands, Codex produces tests/evidence in existing designated workspace without production changes, independent exact-SHA source review, and separate owner runtime/merge decisions. Baseline historical P1.1A developer-reported 16,807/0 assertions remain historical; no run occurred during this documentation approval.

**Status:** `B0_EXPERIMENT_INPUTS_AND_METHOD_APPROVED / PRODUCT_BUDGETS_UNDECIDED / B1_1_BLOCKED`.
