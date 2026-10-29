# R9.4-A Attempt Ledger

| Attempt | Defect / hypothesis and prediction | Implemented correction | Focused result | Outcome / next action |
|---:|---|---|---|---|
| 1 | Fixed 2/2 tetra quad diagonal emits a sub-cutoff triangle independently; a valid alternate pair may preserve a complete quad. Predicted fewer cutoff drops/open seams without changing cutoff. Basis: direct candidate source and R9.3 exact-edge diagnostic. | Evaluate both diagonals under unchanged 1e-12 squared-cross threshold; preserve historical if valid, otherwise emit alternate only as a complete pair; rollback partial insertions. | Synthetic regression selected alternate. Neighbor improved 4→0 internal opens. X+ remained open (12 at initial attempt; final with further root changes 8) and no frozen X+ acceptance. | PARTIAL; retain and investigate root precision separately. |
| 2 | More bisections should stabilize roots at shared boundaries. Predicted fewer seam openings. Basis: candidate root bisection and measured neighbor improvement. | Root iterations 8→20. | Neighbor improved, but frozen negative-region case exceeded the 10,000 unique sample stop-loss; exit 1 in one preserved run. | CENSORED for stop-loss; do not keep this bound-violating value. |
| 3 | A bounded 12-iteration compromise may retain most refinement while honoring sample ceiling. | Root iterations 20→12. | Negative-region pair completed below cap with 0 internal opens; neighbor 0; X+ still 8 opens / 7 cutoff drops. | PARTIAL; final A still misses X+ and ray/normal targets. |

## Provenance qualification

Intermediate attempts have no retained content-addressed source snapshots. Process metadata was emitted with R9_SOURCE_SHA set to the R9.3 base, not the intermediate working tree. Their source ID is therefore UNPINNED_WORKTREE; do not attribute the base SHA to the correction. Exact final validation is tied to f0c93415dd56886a1c05ff2e6a1340e420f22c59. A first launcher attempt is preserved separately and is not counted as an implemented correction.
