> **Repository registration (2026-10-21).** This is the unmodified owner-provided R4a corrective addendum, preserved as source evidence and accepted together with the [R4 source](P1-1B-B0-R4-SOURCE-PROPOSAL.md), subject to the narrower [B0 owner decision](P1-1B-B0-OWNER-APPROVED-CONTRACT.md). Acceptance of experiment definitions does **not** authorize B1-1 code or execution.

---

# P1.1B-B0 R4a — Corrective Addendum

**Terminal status:** `P1_1B_B0_R4A_READY_FOR_OWNER_DECISION`

Planning only. No repository changes, Godot execution, benchmarks, native Voxel Tools operations, or F2-G1 actions occurred. The five F2-G1 holds remain unchanged.

I reviewed [independent comment #6314132611](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/97#issuecomment-6314132611) against the exact main baseline `665c5c883ae88b949f4030f7affc786064999f61`. The replacements below are limited to the three requested sections; all other accepted R4 definitions remain in force.

## 1. Replacement: direct diagonal streaming scenario

Replace `B0S.CORNER.DIRECT_POS_POS.v1` with this **atomic focus-update** case. It is distinct from the continuous movement scenarios.

**Scenario ID:** `B0S.CORNER.DIRECT_ATOMIC_POS_POS.v1`

- Start focus: `(15500, 3200, 11500)` mm, region key `(0,0)`.
- Initial condition: the origin’s requested 3×3 window has fully published; `active_regions` is exactly that 9-key set, with no relevant pending or failed loads.
- Trigger: on one test-driver callback, call `_move_focus(Vector3(1.0, 0.0, 1.0))` exactly once. Do not interpolate the focus or update X and Z separately. This moves the focus to `(16500,3200,12500)` mm, region key `(1,1)`.
- Observation: record the focus key and reconciliation event before and after that call. The expected observed sequence is exactly `(0,0) → (1,1)`; any intermediate key, extra reconciliation, or additional movement invalidates the scenario.
- Readiness: after the atomic update, wait for the final requested set to publish. Do not count requests or loading stages as active.
- Expected final set: `A_prev ∩ R2(1,1) ∪ D(1,1)`. Given the stated initial condition, this has 14 keys. Verify the actual keys and publication events, not just the count.
- Report requested, retained-active, pending, successfully published, failed/canceled, and final active key sets independently.

This construction makes both boundary changes visible to the streaming code in one synchronous focus update. It therefore does not assume that equal ideal crossing times automatically produce a single observed transition.

The existing three-leg positive, negative, and mixed-sign corner loops remain unchanged.

## 2. Replacement: edited revisit classification

**Scenario ID:** `B0S.WARM.REVISIT.EDITED.v1` — **`NOT_FROZEN`, excluded from the executable benchmark contract.**

Retain the R4 route:

1. Settle at focus `(8000,3200,6000)` mm.
2. Apply one left click at `(640,360)` in the frozen `1280×720` viewport configuration, using the frozen camera pose.
3. Record actual picker hit, mode, production radius `1.25`, accepted sequence/revision, center, support/rebuild regions, and resulting command hash.
4. Travel to `(72000,3200,6000)` mm at `+8000 mm/s`; wait for actual readiness.
5. Return to origin at `-8000 mm/s`; wait for actual readiness and verify the replayed revision and canonical samples.

The scenario remains `NOT_FROZEN` until an authorized preflight confirms that the fixed click hits, is accepted, publishes coherently, and produces a reproducible outcome hash. A miss, busy state, or timeout invalidates preflight. Do not change the click or camera recipe in response. No runtime evidence is claimed here.

## 3. Replacement: tunnel component oracle

Keep the complete R4 density equations, domain, seed/phase definition, sign convention, and width variants. The tunnel widths remain:

| Scenario ID                             | Width   | Radius |
| --------------------------------------- | ------- | ------ |
| `B0G.TUNNEL.SYNTH.W500.v1`              | 500 mm  | 0.25   |
| `B0G.TUNNEL.SYNTH.W1000.v1`             | 1000 mm | 0.50   |
| `B0G.TUNNEL.CANONICAL_CONTROL.W1840.v1` | 1840 mm | 0.92   |
| `B0G.TUNNEL.SYNTH.W2000.v1`             | 2000 mm | 1.00   |

Use the proposed deterministic 125-mm lattice over the declared domain, including both endpoints: 257 X samples, 81 Y samples, and 193 Z samples. Classify density `<0` as empty and `>=0` as solid.

For each X sample, compute the centerline from the seeded R4 formulas. Choose the nearest Y/Z lattice sample with a fixed tie rule, and use those centerline-nearest empty voxels to identify the tunnel-seeded component `C_tunnel`. Verify that this component reaches at least one empty voxel on **each** X boundary plane.

Track other negative-density components separately:

- `C_top`: component identified by a fixed sample at `(x=0, y=7.875, z=0)`, representing exterior top air.
- `C_bottom`: component identified by a fixed sample at `(x=0, y=-1.875, z=0)`, representing below-floor empty space.

Record component sizes and whether these seed-selected components overlap. The tunnel test does **not** require the entire negative-density volume to be a single component, nor does it require the tunnel component to remain disconnected from exterior air. It only checks the centerline-seeded tunnel’s connection to both X openings and reports its relationship to the separately seeded exterior components.

The 125-mm lattice is a proposed numerical oracle, not a product feature-preservation threshold. Required cave widths and acceptable feature loss remain owner decisions. The synthetic widths are not claimed to be identical to production SDF v1; the 1840-mm control uses the production tunnel radius.

## Source-to-contract evidence

| Source evidence at reviewed main                                                                                                                                                          | Contract consequence                                                                                                                                  |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `terrain_demo.gd:_move_focus` updates the target, focus key, and region window synchronously. `_process` also checks focus and reconciles each frame.                                     | The direct diagonal case uses one atomic `_move_focus` call and asserts no intermediate key. Continuous paths must record observed focus transitions. |
| `_reconcile_region_window` separates `active_regions` from `loading_regions`; `_begin_region_stage` stages work; `_publish_region` creates active residency; `_unload_region` removes it. | Requested, pending, published, canceled, and failed sets remain distinct.                                                                             |
| `sdf_world.gd:sample_density` defines the seeded surface and YZ cross-section tunnel distance at fixed X.                                                                                 | Preserve the R4 equations and distance convention; select a tunnel-seeded component rather than conflating all empty space.                           |
| Existing source/test review does not provide a successful runtime click or frozen observed command hash for the revisit route.                                                            | `B0S.WARM.REVISIT.EDITED.v1` remains `NOT_FROZEN`; no validated viewport input is claimed.                                                            |

## Scenario classification

| Scenario group                                               | Status                                                                                                                                  |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| Canonical-ledger replay with fixed integer-mm commands       | `FROZEN` as a proposed input contract; final manifest digest does not yet exist.                                                        |
| Streaming face routes and three-leg corner loops             | `FROZEN` inputs; readiness and resident results remain event-observed.                                                                  |
| Atomic direct diagonal `B0S.CORNER.DIRECT_ATOMIC_POS_POS.v1` | `FROZEN` input and explicit expected active set, conditional on the stated settled initial state and single-callback assertion.         |
| LOD face, edge, and corner fixture cases                     | `FROZEN` inputs and topology checks; no performance or product-quality acceptance implied.                                              |
| Tunnel formulas, domain, widths, and component oracle        | `FROZEN` definitions; numerical outputs are unmeasured and feature thresholds unapproved.                                               |
| Canonical edit seam replay and edited unload/reload recipe   | `FROZEN` command inputs; any case requiring a non-empty edited contour remains excluded until its preflight confirms that precondition. |
| Remote picker histories and repeated real-click histories    | `NOT_FROZEN` until the fixed hit/preparation preflight succeeds and expected outcomes are frozen.                                       |
| Warm edited revisit                                          | `NOT_FROZEN` until its fixed viewport click preflight and command outcome are reproducible.                                             |

No hashes are asserted for manifests or outcome artifacts whose bytes have not been generated.

## Owner decision matrix

| Item                                                                                                   | Status                                        | Owner action                                                               |
| ------------------------------------------------------------------------------------------------------ | --------------------------------------------- | -------------------------------------------------------------------------- |
| SDF v1, seed/version, ordered ledger, spatial mapping, worker/upload/residency limits                  | `OWNER_APPROVED` / `EXISTING_HARD_CONSTRAINT` | Preserve as defined in R4.                                                 |
| Scenario inputs, integer-mm command schema, route definitions, synthetic field and connectivity oracle | `PROPOSED`                                    | Approve or revise the experiment contract.                                 |
| Target hardware, renderer/configuration, viewport, and cache-control method                            | `OWNER_TO_DEFINE`                             | Select before comparative measurement.                                     |
| FPS/frame-time, stalls, edit/presentation latency, RAM/VRAM, geometry and normal tolerances            | `OWNER_TO_DEFINE`                             | Set product acceptance budgets; none are implied by B0.                    |
| Required cave widths and acceptable feature loss                                                       | `OWNER_TO_DEFINE`                             | Decide whether any synthetic width represents a product requirement.       |
| External measurement tools and raw-artifact retention                                                  | `OWNER_TO_DEFINE`                             | Approve tools, correlation, storage, and retention.                        |
| Exploratory baseline                                                                                   | Optional `UNSCORED`                           | Requires separate authorization; does not count as performance acceptance. |
| B1-1 harness implementation and later benchmark execution                                              | `OWNER_TO_DEFINE`                             | Each requires its own authorization gate.                                  |

**The corrected B0 contract is ready for owner approval.** Approval would freeze planning inputs only; it would not authorize harness implementation, benchmark execution, backend selection, P1.1C, or protected-host operations.

**Terminal status:** `P1_1B_B0_R4A_READY_FOR_OWNER_DECISION`.