# P3.1 R9.5 Shared Oracle — Preregistration

Status: frozen diagnostic implementation; no candidate correction has run.
Scope: test-only causal analysis for Issue #191. Candidate C is control only.

## Frozen provenance

- Oracle branch base: R9.4 comparison HEAD 9bdfcd59241d76bd57b95b9e2bb5c1982834071b.
- Frozen E2E manifest: game/tests/prototypes/p3_1_r9_2_e2e_inputs.jsonl,
  SHA-256 1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972.
- Seed/generator: 131102026 / canonical SDF v1.
- Triangle rejection threshold remains squared cross product 1e-12.
- Candidate source commits are recorded in SOURCE-IDENTITIES.md; copies in
  r9_5_source_snapshots must be byte-identical to those measured sources.
- This report and the diagnostic script must be committed before the first run.
  Every invocation records oracle HEAD and candidate source SHA in environment
  metadata and output. The R9.4 UNPINNED_WORKTREE records remain historical
  and are not promoted to exact-source evidence.

## Ray-root method

The 25 frozen inputs are in x-major/z-minor order, origin Y=8, direction -Y,
maximum distance 12. Candidate mesh remains the frozen CAVE_SMALL ROI
[7.5,-1,4.5], dimensions [4,8,6], step 0.5; its Y bounds are [-1,3].

For the zero-edit row, an analytic reference enumerates every possible
vertical root of the canonical min field:

- top plane surface_y(x,z)-y = 0;
- lower plane y-MIN_Y = 0;
- tunnel circle sqrt((y-cy(x))^2+(z-cz(x))^2)-0.92 = 0.

Candidates are filtered through the full canonical sampler to honor the active
min branch and the ray interval. This is complete for the specified zero-edit
vertical rays by direct component-root enumeration; it is not generalized to
arbitrary direction or edits.

An independent adaptive interval method cross-checks the roots using the
1-Lipschitz bound of the min of the canonical distance components. Sign changes
are bisected; same-sign possible tangent intervals remain explicitly
unresolved. It has a 50,000 density-evaluation cap per ray and 1e-5 interval
width. No completeness claim is made for unresolved tangencies.

The adaptive implementation applies interval exclusion only when the absolute
density at an interval endpoint exceeds the complete interval width (with a
small arithmetic guard); this follows directly from the 1-Lipschitz bound.
It recursively checks both halves otherwise. A separately recorded 256-step
finite scan remains a comparison method, never the completeness oracle. The
analytic and adaptive root sets are compared; unresolved same-sign intervals
are acceptable only when they overlap an analytically identified tangent.
Candidate intersections are compared against all canonical roots inside the
candidate ROI, while a nearer global root outside that cropped ROI is reported
separately. This avoids mislabeling a correctly cropped mesh as a missed global
first surface.

Candidate intersections are computed independently with two-sided
Moller-Trumbore and cross-checked against the existing CPU triangle helper.
Every full-field first root is classified against the mesh ROI before comparing
it with candidate mesh intersections. Roots outside the ROI are scope
disagreements, not mesher failures. X- uses the bounded adaptive method because
its frozen row has ordered edits. Triangle 3103 remains the frozen historical
global-index witness; a one-cell rebuild does not claim index equivalence.

## X+ oracle

The original equal/mixed/historical rows are retained, and are reported
explicitly as single-ROI proxies. A separate candidate-pair diagnostic builds:

- Equal: left [15,1,6] to [16,3,8], right [16,1,6] to [17,3,8],
  each at step 0.25.
- Mixed: left same spatial interval at step 0.5, right at step 0.25.

For each pair the harness records both actual candidate mesh hashes, boundary
segments on X=16, exact binary32 interface edge incidence, combined exact-edge
topology and mismatched contour segments. An independent fixed 2D face
triangulation samples the canonical SDF and bisects each crossing edge; its
segments are reported separately from candidate output.

The frozen 533 face samples are reconstructed as a 41 x 13 grid:
X=16, Y=-2..8 at 0.25, Z=6..9 at 0.25. Each coordinate is sampled once as
region (0,0) local X=16 and once as region (1,0) local X=0, then compared
bitwise as binary32 with the canonical world sampler. The two frozen edits are
also compared through the full snapshot; any difference fails the sample
identity result. This coordinate oracle is distinguished from instrumentation
of production chunk-builder calls.

Every original dropped triangle reported by candidate metrics must be mapped
to a cell/tetrahedron, source density bits, root identities/positions and
cross-squared value in the subsequent targeted cutoff-trace report. The
1e-12 threshold is immutable. Cropped ROI boundary edges are not internal
openings.

## Stop losses and attempt limits

Reuse R9.4 preregistered bounds: 10,000 unique samples, 20,000 triangles,
60 seconds per scenario, 600 seconds aggregate per candidate, and
536,870,912 bytes process-tree working set where available. Timeouts are
right-censored. Candidate A and D hypotheses are separately pinned before
execution, at most three distinct hypotheses each and no more than two source
revisions per hypothesis. Candidate C is never edited.

This diagnostic does not score performance or establish gameplay, physics,
GPU, GUI, or production acceptance. Final A and D sources require the complete
frozen applicable fixture matrix and Godot 4.7.2 scripts/validate.ps1.
