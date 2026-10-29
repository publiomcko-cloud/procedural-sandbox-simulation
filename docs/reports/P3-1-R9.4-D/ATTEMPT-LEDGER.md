# R9.4-D Attempt Ledger

| Attempt | Defect / hypothesis and prediction | Implemented correction | Focused result | Outcome / next action |
|---:|---|---|---|---|
| 1 | Reversed endpoint interpolation of shared float32 lattice edges may create duplicate roots. Predicted exact shared root identity would reduce openings. Basis: source comparison to R9.3 independent root cache. | Canonical endpoint ordering and one root per global lattice edge in the primary extractor. | Slightly worse: zero 214/67→213/68 and FILL/CARVE 272/86→271/87; neighbor/X+ unchanged. | FAILED; investigate polygon ordering rather than repeat root caching. |
| 2 | Incidental tetra edge-hit ordering can produce crossing/fan assembly inconsistent with polygon cyclic order; gradient-based orientation and zero-node identity may restore the same polygon as an independent extractor. | Sort intersection points around the tetrahedral surface normal; orient via finite-difference gradient; deduplicate by canonical root identity. | Corrected retry passed; zero/CARVE/F-C/neighbor/negative/historical all 0 opens/nonmanifold. X+ is 13/0 and exactly matches independent R9.3 reference mesh hash. Eight cutoff drops remain, min squared cross 8.90332212726756e-17. | PARTIAL; preserve output and explain reference’s 13 X+ holes, but frozen no-open target is still failed. |

## Operational record

The first attempt-2 execution failed at GDScript compilation due indentation and built no scenario. The corrected retry used the same intended correction and is not counted as another implemented geometry attempt. A separate diagnostic run isolated the X+ dropped triangles. All raw outputs are retained.

## Provenance qualification

Intermediate attempts have no preserved exact source snapshots. Their logged source SHA points to the R9.3 base, not mutable working-tree source. They are UNPINNED_WORKTREE. Final tested commit is exact 6ea04229b5ff06090f346c8749c1f5a53994227c.
