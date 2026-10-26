# P3.1 R3C — corrective experiment preregistration

**Status:** Frozen before final performance campaign. Exploratory engineering gates only; no product budget or approval is implied.

## Provenance and scope

R3C starts from R3B evidence PR #138, head `2b9edfab41fe5ad67f767a36aae0263f1e28e683`, which itself is based on the P3.1 production candidate `92b442d7f5b605c7bc9c48fac2aceea9d71813aa`. R3B's original workload and acceptance contract is immutable: `docs/reports/P3-1-R3B/PREREGISTRATION.md`. R3C does not alter production paths, schemas, saves, PR #138, PR #129/#134/#136/#137, or Issue #108.

## Frozen inputs

### R3B regression set

Run the byte-identical eight Issue #131 cases: 256/640/2,048/8,192, concentrated and distributed, five independent Godot processes per case. Preserve all R3B gates without averaging across scenarios or changing thresholds: exact zero mismatches; concentrated 8,192 LOD1 at least 2× faster in each run; every other original optimized/canonical build no worse than 10% in at least 4/5 runs; cold cache overhead at most 10%; fresh-process disk hit below 50% of the paired cold build; exact remote hits/local invalidations and corruption fallback.

### R3C nonperiodic dense set

Eight independent scenario IDs: `P31.R3C.NONPERIODIC.{CONCENTRATED|DISTRIBUTED}.N{0256|0640|2048|8192}.v1`, each five fresh processes when a scenario completes. Generator seed 135031. Each command has sequence 0…N-1, revision sequence+1, alternating CARVE/FILL, distinct world-space integer-millimeter centers and radius 450…1,200 mm. Concentrated commands occupy region (0,0) in a narrow strip spanning chunk boundaries and varied heights; distributed commands occupy the 9×9 neighborhood centered at region (-31,-64), with deterministic face, edge and corner seam centers, including negative coordinates. Hash generation and collision resolution are implemented by `game/tests/prototypes/generate_p3_1_r3c_inputs.ps1`; each exact command file and manifest is pinned by SHA-256. The R3C scenario-manifest SHA-256 is `0facbab3b76bdbee78741d02f57bc8c631c3610cfb8758fd42ac868855a0ee03`; the frozen `SHA256SUMS.txt` digest is `cd0026a32e50c24a8af3bec41044bbbdb4a7aa859754aeffd3ab1b0aa141200b`. Before final campaign, independently verify each file hash, command count, sequence, mode alternation, radius bounds, center uniqueness, signed seam coverage and zero repeated full command tokens. No scenario bytes or expected results may change after the preregistration hash is recorded.

## Method and metrics

Use pinned Godot `4.7.2.stable.official.ed1daf0bf` and the same reference host as R3B when available. Each scenario is a separate process with isolated profile, output and cache roots. Pair canonical full-replay and candidate queries/LOD0/LOD1 in counterbalanced order. Report all five process distributions, p50/p95/p99, extrema, failures and timeouts; never pool scenarios. Include candidate operation counts, exact distance evaluations, pruning decisions, mesh phase costs, identity encoding/hash, cache lookup, mesh/envelope serialization, disk read/write/eviction, memory and disk bytes. Clearly separate cold build, memory hit, disk hit, local-edit invalidation/rebuild and proven remote-edit hit.

For each query, compare exact float output at frozen and seeded arbitrary world points. Compare finite-difference normals, ray-picker first intersection and bisection, and exact LOD0/LOD1 positions/normals/topology. Exercise ordered alternating operations, overlaps, cave/surface values, negative coordinates, region/chunk faces/edges/corners, and points immediately around operator thresholds. Cache remains derived: corrupt, truncated, incompatible-version and interrupted-temp entries must fall back to canonical build; concurrent same-key writers must never publish partial bytes or return geometry different from canonical. Cross-process limits or claims not directly tested are labeled unresolved.

## R3C exploratory gates — fixed before final run

1. Exactness: zero mismatches in every completed process; any mismatch blocks the candidate regardless of speed.
2. New nonperiodic dense evaluator: at concentrated N8192, at least 20% LOD1 p50 reduction versus canonical in at least 4/5 processes; at each of the other seven workloads, no more than 10% regression in at least 4/5. These are prototype gates, not product criteria.
3. Cache cold total is end-to-end from identity construction through durable publication or an explicit bypass decision. Where persisted, cold overhead is measured with the unchanged R3B denominator and must be ≤10%. A bypass cannot be counted as a disk hit; every workload must report bypass frequency and the corresponding warm-revisit outcome. Existing R3B cache-hit and invalidation gates remain unchanged.
4. For adaptive admission, compare paired unconditional and policy behavior on identical mesh bytes. It must reduce cold overhead by at least 25% for at least one preregistered cheap, non-revisited chunk workload while producing identical canonical geometry. For workloads explicitly revisited, disk-hit behavior and write cost remain measured; policy cannot hide publication cost outside the reported transaction.
5. Cache corruption, incomplete writes and simultaneous same-key writers: zero invalid cache hits, no partial final file, and successful exact canonical fallback. Any quota/resource cap exceedance blocks that process. No post-result threshold changes or replacement runs.

## Reproducibility and exclusions

The final campaign is at most 80 source/candidate scenario processes (40 R3B + 40 R3C), plus only bounded pre-campaign baseline profiles and focused correctness/recovery tests. All raw attempts, including failures/outliers, are preserved. No benchmark timing is presented as rendered FPS, GPU completion, or visual acceptance. No production cache policy, concurrency contract, schema, merge, Issue #108, or F2-G1 operation is authorized.
