# Issue #108 — Terrain / procedural rock contact architecture (design brief)

Status: DRAFT DESIGN, implementation and migration NOT AUTHORIZED by this document. Owner accepted the universal persistent excavation *design direction* on 2026-10-25, not any implementation. See [proposed ADR-0007](../decisions/ADR-0007-PERSISTENT-TERRAIN-OBJECT-IMPRINTS-PROPOSAL.md). Baseline main: `5997a76d345f45bf86edfe83f690336391e8be27`. Source issue: [#108](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/108).

## Verified present behavior

P3.0D places a rock using the SDF surface hit, a persisted millimeter-quantized world-space base anchor, and region ownership derived from that quantized position. Procedural rock geometry (`procedural_rock_mesh_adapter.gd`) and authoritative SDF terrain/ordered CARVE/FILL brush ledger remain independent. Contact artifacts/rock-terrain intersections were observed by owner and logged in #108. Rocks are not rotated to slope or conformed to ground. Repeated placement at identical target intentionally overlaps. No source evidence establishes exact artifact cause (coplanarity, normals, depth, SDF topology); do not guess.

## Design gate before source edits

1. Classify screenshots and reproduce contact failure with scoped fixtures: flat/slope, steep slopes, caves/overhang, edge of SDF regions, negative world coordinates, LOD seams, batch and placed rocks, persisted F7 transform, F8 delete/undo/redo, terrain CARVE/FILL before and after placement.
2. Compare architectural alternatives: **presentation-only contact masking/skirt**, **derived, deterministic terrain modification layered over canonical SDF**, **mesh-level localized fit/cut**; identify required authoritative data, seed/version constraints, mathematical contact envelope, ownership across region edges and unload/revisit, performance budgets, resolution of contradictory player brush edits and resulting behavior on removing a rock.
3. Preserve canonical SDF v1, terrain schema 1, save compatibility and ordered edit ledger unless a separate versioned, explicit migration design is independently approved. No invisible mutations, no double-counted shape in terrain and object representation, no stale streaming publications.
4. Specify deterministic cross-region contact generation independent of visit order, content pins, external first-party parity, signed ownership, cap on affected terrain voxels/chunks, cache invalidation, LOD and GPU visibility. Include fail-closed missing-content handling.
5. Propose incremental rollout with fixed acceptance images and automated deterministic meshes/normal/seam and persist/reload regression tests. Distinguish geometry contact from physics/collision.

## Completion gate

Author an ADR with tradeoff table, selected model, hazards, alternatives rejected and test matrix before attempting implementation. A design PR must remain draft pending independent source/architecture review and owner decision. Owner test on rendered GUI required before implementation integration. Preserve Issue #123 completion, open docs PRs #115/#117/#120/#122/#125, local stashes/untracked files, and five F2-G1 holds.

## Superseding owner requirements (2026-10-25)

Terrain displacement by intersecting solid mod objects is intended as the default for subsequent compatible mods. Imprints persist after deletion, unload, and uninstall; later excavation does not move the object until future physics; FILL/CARVE chronology must be specified. This **rules out purely transient object-presence-derived contact cuts** as the authority. A versioned permanent terrain event/ledger and recoverable cross-store transaction protocol are prerequisites. The exact policies for Undo PLACE and F7 moves, world migration, volume certification, and automatic procedural population require an explicit design decision before production work. See ADR-0007.
