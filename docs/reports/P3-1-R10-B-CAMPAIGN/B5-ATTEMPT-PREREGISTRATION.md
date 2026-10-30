# R10-B5 attempt preregistration — nested local field refinement

Status: preregistered before any B5 geometry invocation. B1 remains blocked by its one recorded harness-error run and is not repeated. B2, B3, and B4 have recorded terminal geometry failures.

## Identity and fixed inputs

- Attempt ID: `B5-NESTED-20261030-310C53F`.
- Hypothesis: `R10B5_NESTED_LOCAL_FIELD_REFINEMENT`.
- Implementation commit: `310c53f0a250cc16449f52ec8d10497ac5c1af35`; parent `0aa6295cb2864767819e8de268c1e7af7b32f1eb`.
- Campaign Git blob: `5934ecb74f46a99e8e0fe08bc86cd05a8b38adf8`; physical SHA-256 `0a945a052dceff3a2dd505cba96bbf5928df0fa1a2f94b7ebeb1715f2c31065fe`.
- Frozen scenario: `R9.2.SEAM.XPLUS_EQUAL.v1`, original A6 volume/payload and snapshot from the registered B1 contract. The existing canonical R9.2 manifest, Candidate D byte pin, R10-A topology authority byte pin, source topology, R2 ray fixture and Godot executable pins remain mandatory and are rechecked by the stage runner.
- The original coarse volume is retained unchanged: 8×8×8 cells, 0.25 spacing, same fixed world bounds and ordered snapshot. B5 separately builds a derived 16×16×16 local field at 0.125 spacing from that same canonical SDF v1 plus ordered snapshot. It does not overwrite or relabel the A6 volume.

## Candidate and measurements

The fine lattice is nested over the coarse lattice. All 9×9×9 = 729 shared sample positions are compared as exact float32 values; the fine volume's own bytes and reload digest are verified independently. R10-A6 topology extraction is run on the derived fine field with the existing fixed `cross_squared > 1e-12` emission rule. This remains sampled-field polygonization and is not claimed to equal the continuous SDF surface between samples.

The extracted fine mesh is compared with the fixed coarse mesh on all six outer ROI planes (X/Y/Z × negative/positive). The independent triangle-plane contour oracle compares canonical segment keys at the campaign's existing 1e-6 coordinate-key quantization. This quantization is diagnostic bookkeeping, not an owner-approved geometric tolerance. Record per-face segment totals, unmatched segments, mesh topology, cutoff rejections, the derived volume/payload digests, sample-map parity, and the frozen ray/control gates. The hard B5 boundary gate requires all six segment sets to match exactly under that fixed oracle; no tolerance adjustment or post-result recipe change is allowed.

The local workload is bounded at 4096 cells / 4913 samples. Use the existing monitored runner and its existing timeout/free-commit stop-loss. No timing result is a performance acceptance claim. If the fine volume cannot be built/reloaded, topology realization is invalid, or the process stop-loss fires, preserve the result and do not relaunch B5.

## Gates and one invocation

Run exact-source `check-only` and graph-contract first. If either fails, do not start geometry. Otherwise execute B5 once with the registered attempt ID. It can only pass the equal-LOD portion if the fine mesh is complete, has zero unexplained internal opens/nonmanifold/degenerate faces/winding errors/missing required adjacency/fixed-cutoff rejections, retains exact volume integrity, preserves all 729 nested samples, and matches all six coarse outer contour sets. The existing 25-ray parity and six controls remain required. Mixed-LOD testing runs only if equal-LOD and ray gates pass; the existing face-owned transition requirement remains unchanged. No `scripts/validate.ps1` or broader geometry campaign unless the required geometry gates pass.

B5 is one bounded experiment. It does not establish an approved geometry tolerance, continuous-field exactness, production readiness, or a production adaptive-refinement design. No production adoption, merge, storage/schema change, Issue #108/#154, or change to the F2-G1 holds is authorized.
