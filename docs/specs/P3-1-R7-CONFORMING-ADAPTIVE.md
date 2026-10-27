# P3.1 R7 — Conforming Adaptive SDF Refinement (Experimental Contract)

**Disposition:** test-only experiment; no production integration or geometry-contract adoption. The current zero-edit topology/collider preflight fails, so the edited scenarios remain unrun.

## Identity and scope

- Issue: [#148](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/148)
- R7 starts at R6-V final HEAD `0867c0c04b857fae1c71b274b8eac44c6e7dba4f`, whose parent is validated R6-V source `aef090871a7582ee5254511f55624d60882fa00d`.
- Production reference: `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`. The experiment does not alter production source, saves, schemas, playable scenes, or the authoritative terrain ledger.
- All three approaches are isolated to `game/tests/prototypes/`; each fine density sample comes from canonical SDF v1 plus the immutable ordered brush snapshot. A sampled/interpolated mesh is still an approximation to the continuous field.

## Frozen field and workloads

All values are world units. Seed is `131102026`, generator version is `Field.GENERATOR_VERSION` (1), and region is `(0,0)`. The bounded patch has minimum `(8,-2,3)`, dimensions `(8,20,12)` coarse cells, coarse spacing `0.5`, and fine spacing `0.25`. Its 1,920 coarse cells bound every prototype. Initial refinement selects a cell when its eight coarse corner values straddle zero or the exact canonical center differs from the coarse interpolant by more than the selection input `0.02`; this is not a geometry tolerance.

The seeded centerline point at world X `x` is formed by `Field.cave_center(seed, region, x) = cross_section`; world XYZ is `(x, cross_section.y, cross_section.x)`. The scenarios are:

| ID | Ordered commands | Expected canonical setup |
| --- | --- | --- |
| `P3.1.R7.ZERO_EDIT.v1` | none | Revision 0; exact canonical vertical cave opening 1.75 |
| `P3.1.R7.CAVE_WALL_CARVE.v1` | sequence 0: CARVE radius 0.58 at centerline X=8 plus world-Z offset 0.80 | Revision 1 |
| `P3.1.R7.CENTER_FILL_THEN_WALL_CARVE.v1` | sequence 0: FILL radius 0.58 at centerline X=8; sequence 1: CARVE radius 0.58 at centerline X=8 plus world-Z offset 0.82 | Revision 2; global order preserved |

Input identity is SHA-256 over UTF-8 bytes, no BOM or trailing newline, of the exact `JSON.stringify` canonical object built in fixed insertion order by the diagnostic. The measured zero-edit bytes are checked in as `../reports/P3-1-R7/evidence/input-manifest.json`; their SHA-256 is `24f70884cb0ec4c2ea90daad77dd12987d8023deabd144c24ac4235635f0451b`. Mesh identity hashes the packed position and normal array lengths, then their raw packed bytes. It is an output identity, not a semantic geometry-equivalence proof.

## Compared approaches and hard experimental bounds

All approaches use the same frozen initial refinement mask, canonical SDF samples, extraction oracle, and test-only physics proxy.

| Approach | Refinement policy | Transition policy |
| --- | --- | --- |
| A — conforming propagation | Propagate refinement through the connected bounded patch until all face-adjacent cells have a compatible level. For this single-level bounded patch, the conservative closure is uniform refinement. | No coarse/fine interior interfaces remain. |
| B — shared fine faces + transitions | Keep only the initial refined mask. | Sample shared fine-face values from the canonical field and build transition cells for each unrefined cell adjacent to refined cells. |
| C — hybrid | Expand the initial mask by one face-neighbor cell layer. | Transition remaining fine/coarse interfaces. |

Stop-loss limits are 64 propagation cells in radius, 12,000 refined cells, 16 MiB of fine scalar payload, and 250,000 extracted triangles. A, B, and C are rejected if any bound is exceeded. The limits bound this fixture only; they are not product limits. Patch-exterior edges are reported separately from internal open edges. Internal topology checks include open edges, non-manifold edges, degenerate triangles, actual extracted interface contour matches, duplicate coplanar surfaces, and strict T-junctions. Vertex welding for topology uses Euclidean distance `<= 1e-5`; this is an oracle matching/welding tolerance, not an approved product geometry tolerance.

The physics proxy builds disposable in-memory `ConcavePolygonShape3D` meshes, casts rays both into and out of the cave, and performs a discrete radius-0.1 sphere sweep at 0.05-unit steps. It is not a production collision provider, continuous collision/MTV test, or approved collision contract.

## Execution gate

Run the `zero_edit` scenario first. It must pass topology and all-direction collider outcome comparisons before either edited scenario can execute. The harness defaults to this preflight. Edited execution requires `--run-edited-after-preflight`; if zero-edit fails, the harness records later scenarios as skipped and exits nonzero. `--preflight-only` runs just the zero-edit case. The R7 result does not proceed to broad repetitions, streaming/restart tests, or production adoption while the gate is failing.

Godot 4.7.2 parser checks and the zero-edit preflight command are recorded in the [R7 result report](../reports/P3-1-R7/RESULTS.md). No owner-approved geometry or performance thresholds exist. Headless timings do not establish presented FPS or GPU completion.
