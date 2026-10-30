# R10-B3 attempt preregistration — constrained-Delaunay Lawson flips

Status: preregistered before the B3 geometry invocation. B1 remains blocked by harness errors and is not retried; B2 completed its registered search and failed the fixed geometry target.

## Exact candidate identity

- Attempt ID: `B3-LAWSON-20261030-E4BA97C`.
- Hypothesis: `R10B3_CONSTRAINED_DELAUNAY_LAWSON_FLIPS`.
- Implementation commit `e4ba97ce071670ecdd064d51ae12bad50703aebd`; direct parent `823b76111c46d7f640a59c70059c2838d7182b22`; tree `57d7e9305eccc3c7e4722f74d04b0813736276c3`.
- B3 realizer Git blob `ba6f2db90b6e5ef314ece91aced16e36e750fdd4`, physical SHA-256 `27caf1506f11097997ebd0219cec69bad2c707a0caf5ffa19fb273677576092a`.
- Campaign Git blob `3a55dd056f554025df547c83b7a78611dc20aad5`, physical SHA-256 `20b75acee6f41eef6faa49d65b510fd4d4eaad0b88682e507c4bdb2f160488a6`.
- B1 shared helper physical SHA-256 `3601d45652efc420429b5306b1c1102af1e2d008e9d5d73b3004c44bd1667eb9`; runner `a10ed1d064f1ee75ea91752cf8d16d1d0a50d8a5a895c586502f110a7344bb13`.
- Frozen Candidate D, manifest, R10-A authority, ray source, ray fixture and Godot pins are unchanged from B1/B2 preregistration. They are rechecked by the runner and emitted in the launch intent/process record.

## Frozen geometry input

B3 runs exactly `R9.2.SEAM.XPLUS_EQUAL.v1`, seed and volume from the canonical frozen R9.2 manifest, with A6 volume SHA `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`, payload SHA `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`, revision 2, graph SHA `4ecbb2496fb34f1cf3c05a60192f76bdce7a52ec3148d02ba041510b804a8c95`, component `60,8,25|tet:0`, 73 source roots, a fixed ordered 34-root boundary and 110 faces. No sample, root, source polygon, command, ROI, threshold or expected geometry is changed.

## Distinct B3 algorithm

B3 applies deterministic constrained-Delaunay Lawson flips over the 110-face source triangulation. It scans canonical edge keys in sorted order and flips the first internal diagonal whose opposite point is strictly inside the projected circumcircle (`incircle_determinant * component_orientation > 0`). Cocircular (`== 0`) cases are left unchanged; sorted edge order makes traversal deterministic. Each flip must preserve the fixed 73-root set, 34-edge outer cycle, 110-face topology, manifold incidences, projected and 3D orientation, and the global projected no-crossing condition. The root positions and scalar volume are immutable. Temporary sub-cutoff faces may occur in intermediate states; only the final emitted mesh is judged against the unchanged strict `cross_squared > 1e-12` rule.

Limits: 4,096 flips/states, 15,000 examined edge keys, and 90 seconds solver time. A cap is inconclusive. Repeated state or no remaining strictly non-Delaunay internal edge terminates the deterministic Lawson walk; if cutoff failures remain, that is a failure of this strategy, not proof no valid triangulation exists. No numeric epsilon is added to the incircle predicate.

## Gates and invocation

The exact-source `--check-only` and graph-only contract must pass before B3. Geometry requires all B1/B2 invariants, exact volume/root identity, no open/nonmanifold/degenerate/winding/adjacency defects, unchanged cutoff, 25/25 ROI ray parity using the independently rebuilt frozen `R9.2.RAY.CANONICAL_PICKER.v1` volume and its own ray grid, plus six frozen controls. If equal-LOD and ray gates pass, the campaign executes the separate mixed LOD1/L0 interface check; a missing face-owned transition or any unmatched independent segment fails. No repeat/E2E/full-validation campaign is authorized until every gate passes.

```powershell
pwsh -NoProfile -File scripts/experiments/run_r10b_stage.ps1 `
  -Stage geometry `
  -AttemptId B3-LAWSON-20261030-E4BA97C `
  -Hypothesis R10B3_CONSTRAINED_DELAUNAY_LAWSON_FLIPS `
  -EvidenceRoot 'C:\Users\PUBLI\AppData\Local\Temp\P3_1_R10B_20261030_e2d6c8b0\B3-LAWSON-20261030-E4BA97C'
```

Each attempt ID and evidence folder is unique. No rerun after geometry launch; preserve raw output, process records and hashes. All measurements are UNSCORED and experimental only.
