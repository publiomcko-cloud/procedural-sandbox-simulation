# R10-B1R — Direct constrained triangulation preregistration

Date: 2026-10-30
Campaign: P3.1 R10-B, existing draft PR #208
Hypothesis ID: `R10B1R_DIRECT_CONSTRAINED_TRIANGULATION_FEASIBILITY`

## Status and hypothesis accounting

This is the sixth and final valid geometry hypothesis slot. Original B1 remains
`BLOCKED_HARNESS_ERROR` and is not consumed. B2–B6 are the five previously
consumed valid geometry hypotheses. No R10-B7 is authorized. The source work
adds only an isolated experimental solver and evidence orchestration; no
production or playable-terrain path is changed.

The hypothesis is that a legal fixed-root realization exists in the frozen
component even though no legal first 2–2 move exists from A6. B1R constructs
candidate triangles and searches directly; it does not reuse or traverse the
previous edge-flip move families.

## Frozen input identity

The run must use the frozen R9.2 manifest, Candidate D and R10-A authority
physical hashes already pinned by the runner:

- Candidate D: `334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a`
- Manifest: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`
- R10-A authority: `feea8237160c90a049d9f0ab63ad7ff86f46604f9d57112278d25fda20a08216`
- Godot: `4.7.2.stable.official.ed1daf0bf`
- Godot executable: `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`
- Volume: `ecf86bce57e82cd0949d4576e7b7ebe4d1ef8d0633ac7f6d540fd56df6573be2`
- Volume payload: `2ff3685296a8d035967a8c723bc42cb8320a9500dc699538a731490d089203d0`, revision 2
- Target component: `60,8,25|tet:0`; 73 roots, 34 ordered boundary roots, 39 interior roots, 84 source polygons and 110 target faces.
- Fixed triangle cutoff: `cross_squared > 1e-12`.

The run identity binds the exact Git source SHA, physical B1R solver hash,
Candidate D and manifest hashes, volume and payload hashes, revision, frozen
source-topology hash, target component, cutoff, ROI ID, ROI world minimum,
cell counts and grid step. The candidate-domain artifact is produced by the
domain-audit stage, physically SHA-256 hashed, and recorded in a separate
write-once preregistration receipt **before** the B1R geometry stage. Its
digest is intentionally absent here because those exact artifact bytes do not
exist yet.

## Candidate-domain construction

The domain is the exhaustive set of 3-root triangles formed from the 73 exact
frozen source roots. Root positions, boundary vertices/order, scalar volume,
ROI and geometry tolerance are immutable. No Steiner points or moved roots are
permitted.

For each unordered root triple, the implementation:

1. rejects nonfinite/repeated roots and nonfinite or `cross_squared <= 1e-12`
   triangles;
2. orients the triangle toward the frozen component's average emitted-normal
   authority and requires the corresponding projected orientation;
3. projects on the dominant absolute Newell-normal axis of the fixed boundary
   (ties resolve X, then Y, then Z), normalizes the boundary orientation, and
   rejects a non-simple projected boundary;
4. rejects edges that cross the fixed boundary or pass through another frozen
   root, triangles outside the projected boundary, and triangles containing
   another frozen root;
5. assigns a half-open owner cell using
   `floor(centroid_world / grid_step)` on each axis and requires that owner
   cell to occur in the 84 frozen source-polygon owners.

Boundary edges are immutable consecutive edges of the 34-root boundary cycle.
All candidates and ownership rows are serialized in deterministic combination
order. A validating load recomputes root identity, cutoff, winding, projection,
boundary/simple-polygon properties, source-cell ownership, candidate legality,
and owner-cell values. A negative domain self-test changes the first candidate
owner and must fail specifically as an ownership mismatch.

## Direct solver and acceptance

The solver uses deterministic exact-cover backtracking. It branches on the
available open edge with the fewest admissible incident candidates (MRV);
MRV changes ordering only. A selected candidate must preserve directed edge
incidence, fixed boundary ownership, non-crossing/non-overlap, root-use and
the single connected surface. At a complete state, it requires 110 faces,
every root represented, each fixed boundary edge used once, every interior
edge used twice in opposite directions, a connected triangle component, and
one connected manifold vertex link (boundary links are paths, interior links
are cycles). The solver stops at the first complete solution; no-solution is
reported as bounded-domain infeasibility only if the entire finite search ends
without hitting any limit.

Search/output states are:

- `SOLVED`: one admissible exact-root realization found; feasibility
  established, not an exhaustive enumeration of alternatives.
- `INFEASIBLE_EXHAUSTIVE_FROZEN_DOMAIN`: full finite candidate/search domain
  exhausted without a solution.
- `INCOMPLETE_LIMIT`: at least one configured bound reached; no infeasibility
  claim.

The only permissible emitted B1R geometry result is one terminal campaign
result classified `PASS`, `PARTIAL`, `FAILED_TARGET`, or
`FAILED_WITH_REGRESSION`. Any parser, source identity, evidence, domain or
orchestration error before a valid terminal geometry result remains a
tooling/preflight failure and does not consume B1R.

## Preregistered hard bounds

| Bound | Value |
|---|---:|
| Frozen roots | 73 |
| Fixed boundary roots | 34 |
| Maximum candidate triangles | 62,196 (`C(73,3)`) |
| Search nodes | 500,000 |
| Recursion depth | 110 |
| Search wall time | 120,000 ms; sampled every 64 nodes |
| Pairwise intersection checks | 2,000,000 |
| Complete solutions retained | 1 |
| Estimated solver-state memory | 536,870,912 bytes (512 MiB estimate) |
| Process-level timeout | 10 minutes |

Every limit returns `INCOMPLETE_LIMIT`; no cap is converted to a proof of
infeasibility. The memory figure is an implementation estimate and is not a
hard operating-system memory reservation. Existing process monitoring remains
in force: warning at free commit <= 3 GiB, abort only the launched Godot
process at <= 2 GiB, with a maximum of two resource-safety retries for this
exact source if a resource abort occurs before geometry completion.

## Sequential gates

Before the single geometry execution, verify on the exact source SHA:

1. frozen source and volume hashes/counts;
2. causal fixture and graph contract;
3. pinned Godot import and campaign/solver `--check-only`;
4. authority contract and ROI ray-causality fixture (0/25);
5. source topology graph contract;
6. deterministic candidate-domain generation, physical domain SHA, positive
   loader validation and negative tampered-owner rejection.

The geometry result must pass equal-LOD topology, unchanged cutoff, all six
controls, ROI-scoped rays 0/25, frozen volume integrity, mixed-LOD conformity
and deterministic repeat before full E2E and `scripts/validate.ps1` may run.
The global full-ray 9/25 metric remains diagnostic and does not replace the
frozen ROI oracle.

If a valid B1R geometry result fails any required gate, do not execute another
geometry hypothesis. Preserve the terminal result, append a closeout erratum,
and classify the six valid slots as consumed. Full E2E and full validation
remain `NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE` unless all prior gates pass.

No production adoption, merge, release, schema change, Issue #108/#154 work or
F2-G1 action is authorized. All five F2-G1 holds remain in force.
