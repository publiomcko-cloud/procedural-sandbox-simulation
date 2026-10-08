# Phase 0 specification: make the architecture falsifiable

## Work packages
**P0.0 Bootstrap and quality baseline**: Godot 4.7.2 clean project; deterministic pure-data test harness; static/check scripts; editor launch; screenshot and reproducible checks. Starter gives an initial implementation of this only.

**P0.1 Terrain backend comparative spike**: Investigate compatible Voxel Tools GDExtension and minimal custom SDF alternative. Implement in isolated adapters only after license/engine compatibility review. Compare caves, additive/subtractive brushes, chunk seams, collision recook cost, LOD/edit eligibility, streaming and persistence. Record exact third-party commit/release.

**P0.2 Domain commands + save spike**: Define WorldID/RegionKey, seed+version metadata, edit log/checkpoints. Test edit across chunk boundary, unload/reload, mutation revision conflicts, abrupt stop during save and deterministic restore. Never claim full crash durability without fault-injection tests.

**P0.3 Modding spike**: Parse example versioned manifest, validate dependencies and namespaces. Register a declarative procedural rock definition via standalone package. Separate data definitions from privileged script hooks; document threat model and error modes.

**P0.4 Simulation-tier spike**: Minimal scalar temperature and soil moisture over adjacent regions, active/regional/dormant transfer, fixed tick, save/load/catch-up. Test conservation drift and reactivation discontinuity with defined tolerances.

**P0.5 Decision gate**: ADR for selected terrain backend, storage scheme, IDs, mod execution scope, benchmark target and measurable budgets. Independent evaluator re-runs tests; owner visually verifies edit and collision.

## Required benchmark cases
A. Single chunk edits: add/remove/sculpt; measure mesh/collider update time.
B. Border edit: stroke crossing 2+ regions; check seams and stale-buffer suppression.
C. Streaming traverse: warm/cold load; 10 minutes moving; capture peak/steady RAM and frame-time percentiles.
D. Reopen: save, close, reopen, byte-level compare canonical serialized states where feasible.
E. Disabled/missing mod: no silent data loss; informative failure path.
F. Tier transitions: N active/inactive cycles; track energy/water inventory and discontinuity.

## Acceptance gate (not yet met)
- Exact Git SHA, deterministic seeds, engine and addon versions documented.
- Controlled saved edit restores correctly after restart and chunk reload.
- The selected backend is justified by side-by-side results, not aesthetics.
- Independent headless test report and owner GUI observation agree on behavior.
- No critical undefined persistence contract or external dependency without approval.

## Task decomposition and definition-of-done
One work package per ticket; implement test first when feasible. Publish failure-case tests, not only happy paths. Reviewer may classify ACCEPT / REVISE / BLOCKED; only owner accepts visual outcomes and approves architecture change.
