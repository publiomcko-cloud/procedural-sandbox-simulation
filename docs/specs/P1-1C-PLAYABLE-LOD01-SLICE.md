# P1.1C — Playable custom LOD 0/1 slice

**State:** implementation candidate on `feat/p1-1c-playable-lod01`; draft/unmerged. This is not final backend selection, production acceptance, or visual approval.
**Architecture:** [owner-approved P1.1 R2](../roadmap/P1-1-APPROVED-PLAN-R2.md).

## Contract

- The existing `SdfWorld` v1, seed/generator identity, global ordered brush ledger (including its 256-operation cap), signed region/chunk ownership, edit semantics, and streaming remain authoritative and unchanged.
- P1.1C adds a camera-distance selector for LOD0/LOD1 with hysteresis (coarse at 56 world units; return to fine at 46). These are prototype switch values, not product budgets. L remains an explicit toggle; the scene starts on LOD0 for backwards-compatible startup.
- LOD1 uses the global half-unit integer lattice, 1-unit cells, and the reviewed P1.1A transition builder. Chunk perimeter cells use fine-compatible X/Z boundary triangulations, so a ready LOD0 neighbor can meet LOD1 at supported faces, edges, and corners. LOD2 and arbitrary multi-resolution mosaics are excluded.
- CPU jobs receive immutable canonical ledger snapshots and never create scene nodes or `ArrayMesh`. The main thread creates/publishes meshes under the existing four in-flight CPU-worker and two-`ArrayMesh`-per-frame caps. At most one LOD partial-region replacement transaction is staged at once; stale camera selections and stale ledger revisions are rejected before publication.
- A failed LOD1 build falls back to the existing LOD0 mesher and records the fallback per chunk. LOD0 remains available by toggling L off. The mesh/LOD state is derived; edits continue to live only in the canonical ledger and replay on later region loads.

## Validation and proof boundary

The candidate adds deterministic policy, CPU chunk, mixed-resolution seam, edited-snapshot/rebuild, stale-selection, fallback, and actual scene publication/rollback tests. The focused fixture compares chunk-wide shared-cache output byte-for-byte at the packed-array level against a retained per-cell reference for positions and normals. Current local Godot results and the exact SHA belong to the dated implementation checkpoint.

Headless tests establish CPU geometry and scene publication state, not displayed pixels, GPU completion, VRAM, or owner GUI acceptance. The measured triangle reduction and all timings are exploratory; the owner has not set geometry, frame, memory, or fine-feature budgets. Thin caves may disappear at LOD1. LOD2+, collision policy changes, persistence, networking, native extensions, Voxel Tools, and ADR-0002 are excluded.

## Owner GUI procedure

On the draft candidate after source review: run the main scene in Godot 4.7.2; wait for the initial 3×3 window to settle; press **L** and move/orbit the camera across several chunks until HUD `LOD chunks 0/1` changes; inspect terrain silhouettes and chunk boundaries, including mixed LOD contacts; press **L** to return to LOD0; use carve, Shift+carve, C, R, and X to verify existing interactions remain; traverse positive and negative region coordinates and return to an edited region. Record any seam, flicker, stale switch, stream error, missing cave, or rollback issue. This procedure is not yet owner acceptance.
