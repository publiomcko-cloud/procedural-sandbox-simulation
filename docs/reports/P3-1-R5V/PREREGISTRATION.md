# P3.1 R5-V — Adaptive Voxel Representation Experiment

Status: approximate research only, not production. Base source is R4 final
`051249642611a7fa9cd2006be450bad0e184e4ee`; production authority remains
`92b442d7f5b605c7bc9c48fac2aceea9d71813aa`.

## Candidate definitions

Uniform controls at spacing 0.5, 0.25 and 0.125 are taken from the pinned R4
campaign. R5-V adds a sparse-block approximation: a 0.5 base lattice is retained
for the complete chunk; a macro cell is selectively refined when its corner
densities straddle zero or its center interpolation residual exceeds 0.02 world
units. Refined cells use 0.25 or 0.125 spacing. Their boundary samples are
constrained to the shared 0.5 coarse interpolant to avoid scalar discontinuities
at macro-cell faces; interior samples come from the canonical continuous SDF
and ordered ledger. This is still an approximate field. The 0.02 selection
threshold is a research heuristic, not an approved geometric tolerance.

## Frozen workloads and sampling

Use R4 hashed scenario bytes (0/256/640/2,048/8,192, concentrated and
distributed) and seed/generator from R4. Preserve distinct scenario, region,
chunk and history identity. Use deterministic 512-point density probes, real
SDF ray-picker calls, production LOD0 CPU meshing, signed macro-face continuity
checks, canonical cave-centerline tests, and R4 mesh-cache/subledger results.
R5 results are single-process exploration and are reported per scenario; they
are never pooled with R4 repeats.

## Preregistered geometry proposal — NOT OWNER APPROVED

For discussion only, propose the following future acceptance envelope:

* Symmetric sampled vertex-to-triangle surface displacement: p95 <= 0.02 m,
  maximum <= 0.05 m. This is a sampled estimate, not certified Hausdorff distance.
* Sampled normal angular error: p95 <= 5 degrees, maximum <= 15 degrees.
* Minimum cave/tunnel diameter loss <= 0.05 m; all canonical connected tunnel
  centerline samples remain connected and negative.
* Ray-picker hit classification has zero mismatches and hit-position deviation
  <= 0.02 m.
* No chunk/LOD seam topology defect. Collision remains NOT_COMPARABLE until a
  canonical collision surface exists.

These values are proposals only. No geometry adoption or product acceptance is
permitted until the owner defines/approves the contract. Any violation is still
reported even if the candidate appears fast.

## Preregistered performance and validity gates

1. Report field build time, selected cells, samples, serialized size, restart
   rebuild/load, memory, query p50/p95/p99, CPU LOD0/LOD1, picker, and inherited
   cache lookup costs separately. No headless FPS/GPU/presented-frame claim.
2. At least four of five process repeats would be required before a future
   performance-selection claim; this R5 campaign is exploratory and does not
   meet that repeat count. Compare same source, input, machine and profile.
3. No snapshot is called exact. Any failed continuity, nonfinite value,
   disconnected centerline, corruption acceptance, or nondeterministic digest
   rejects the corresponding experimental configuration.
4. One run per frozen scenario. Stop and preserve an attempt at 600 seconds;
   do not repeat it to replace an unfavorable result.

## Artifacts and interpretation

R4 supplies five-repeat uniform voxel, subledger and exact-cache measurements
at all frozen counts where each resolution was preregistered. R5-V contributes
selective-refinement cases and must state any unavailable count/resolution as
NOT_RUN. Surface metrics are sampled vertex-to-triangle estimates. GPU,
collision, VRAM and actual presented frame behavior are unavailable in this
headless harness.
