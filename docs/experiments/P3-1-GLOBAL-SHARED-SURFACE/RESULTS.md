# P3.1 — Global Shared-Surface Authority

Status: GLOBAL_SHARED_SURFACE_AUTHORITY_PASS_READY_FOR_OWNER_PLAYTEST

Qualified implementation HEAD: c7f2e5c06a6ba4e22da869d512900b2af471bba9
UI wording-only follow-up: c00fdbe0dd3cff15977cb38c2db9736701feb879
Branch: exp/p3-1-shared-surface-e2e-success

GitHub Actions run 42040564471, job 127289975740, Godot 4.7.2.stable.official.ed1daf0bf.

## Exit criteria

- X seams: PASS
- Z seams: PASS
- X/Z four-region corners: PASS
- Mixed LOD: PASS
- Async checkpoint: PASS
- Unload/reload: PASS
- Edit fidelity: PASS
- No cracks / no T-junctions / no non-manifold seam edges in tested geometry: PASS

## Ownership model

Runtime ownership is hierarchical: corner chunks are owned by one four-region X/Z authority; non-corner X edge chunks use X pair authority; non-corner Z edge chunks use Z pair authority; interiors remain independently meshed. All regional edge/corner chunks remain LOD0 and LOD1 begins one chunk inward.

## Global qualification

GLOBAL_SHARED_SURFACE_PASS: assertions=159 failures=0

Generation 1 X: 55 seam edges, 0 bad incidence, 0 T-junctions, 0 duplicates, 55/55 crossing ownership.
Generation 1 Z: 76 seam edges, 0 bad incidence, 0 T-junctions, 0 duplicates, 76/76 crossing ownership.
Four-region corner: X plane 74/74 crossings, Z plane 101/101 crossings, zero bad incidence, zero T-junctions, zero duplicates, root identity consistent.

The fixture produced no mesh edge exactly collinear with the vertical X/Z junction line (junction_edge_count=0). This is valid: the single corner authority spans both seam planes and both are non-empty/manifold.

Generation 2 adds three post-materialization edits across X, Z and the corner, checkpoints again, reloads, and remains exactly equal to the complete ordered-history oracle.
Final global signature: 4e4a2870a6aba8cd|-1aedd6e4167025f4|54af5dfdbc2e3290
Final edit count: 99.

## Mixed LOD

123 qualified internal seam edges; 0 bad incidence; 0 T-junctions; 0 crossing ownership mismatch. X left/right: 42/42 and 33/33. Z low/high: 24/24 and 24/24.

## Scalability regression

MATERIALIZED_SDF_SCALE_PASS: assertions=45 failures=0
4,096 edits; hot world open 147 us; hot-load journal reads 0; cold chunk 1,306 us; warm chunk 71 us; LOD0/LOD1 max position error 0.0; archive 4096/4096; old 65,536 cap remains removed.

## Playable runtime

RUNTIME_SCALABLE_PLAYABLE_PASS: assertions=33 failures=0
256 four-region pre-edits; diagonal excursion +64m X / +48m Z; async checkpoint overlaps rebuild; origin unloads and reloads without journal replay.

Runtime: checkpoint worker 1,168.125 ms; focus region visible after return 1,768.759 ms; full 3x3 settle 13,399.707 ms; frame p50/p95/p99 6.896/7.039/7.143 ms; journal reads during reload 0.

Runtime X: 18/18 crossing edges, 0 bad incidence, 0 T-junctions.
Runtime Z: 28/28 crossing edges, 0 bad incidence, 0 T-junctions.
Runtime corner: X plane 36/36, Z plane 48/48, 0 bad incidence, 0 T-junctions, 0 duplicates.

## Pre-edit fixture

F5 now generates general, X-boundary, Z-boundary and X/Z-corner edits across a four-region area.

## Remaining scope

This milestone closes X/Z/corner ownership for the tested production lattice and LOD0-collar/LOD1-interior policy. Remaining work is performance-oriented: focus-first streaming, directional prefetch, full-window settle optimization, future LOD levels and durable undo/reset for materialized history.