# R10-B1 attempt result — blocked before a valid geometry verdict

Attempt `B1-BFS-20261030-21C461A` was launched once, source SHA `eae562eb310d44cd6b5208eaee744d893a4139e7`. Do not rerun B1. The source runner's authoritative classification is `GODOT_SCRIPT_ERROR` (exit code 0 does not override the script-error marker).

Two harness defects were recorded in stderr:

1. `p3_1_r10_b_realizer.gd:253`: assigning untyped `Dictionary.keys()` to `Array[String]` in `_sorted_root_set`; the same typed conversion existed in full-state root validation.
2. `_run_roi_rays` received the equal-LOD seam row `R9.2.SEAM.XPLUS_EQUAL.v1`, which has no `ray_grid`, instead of the frozen ray row `R9.2.RAY.CANONICAL_PICKER.v1` and its distinct `CAVE_SMALL` volume.

Therefore the bounded B1 search did not produce valid evidence. The emitted JSON artifact's `FAILED_TARGET` marker and partial topology counters are retained but are not interpreted as a geometry result. Six control rows were reported as passing, but the overall attempt remains blocked because script errors invalidate it.

| Raw item | SHA-256 |
|---|---|
| `stdout.txt` | `f8640f8342221625f5a172815a9662be6802c553198ec844079f88c365b61afa` |
| `stderr.txt` | `792f9abe63ea78f8bc116da432739b8cf1acd87fee7e672020690d2ce2403258` |
| `process.json` | `676c09571e9e951731097661d8cf5d320441ea60f3a3fe98f7230ab656c64f34` |
| `launch-intent.json` | `a5e7bf65c7e97b1b7a8591cf7543d9f45fa941412c85f355e61ae9ee840e5409` |
| `B1-BFS-20261030-21C461A_attempt.json` | `321baef1e90914095968ccf9bd300ace09a8c5a0b5cd3e3c77296ca341b29c25` |

Evidence root: `C:\Users\PUBLI\AppData\Local\Temp\P3_1_R10B_20261030_e2d6c8b0\B1-BFS-20261030-21C461A\B1-BFS-20261030-21C461A_geometry`.

Correction is limited to the experimental harness: convert dictionary keys explicitly to strings and construct the ray gate from its own frozen scenario/volume. It preserves the B1 evidence and all frozen geometry/ray thresholds. B2 is the next distinct attempt; this B1 run is classified `BLOCKED_HARNESS_ERROR`, not pass or geometric fail.
