# P3.1 R9.4-D — Materialized-Volume Extractor Correction

Date: 2026-10-28  
Scope: isolated test-only experiment on R9.3-D. No production integration or geometry-contract adoption.

## Disposition

**D_PARTIAL_CORRECTION.** The original materialized-volume extractor’s severe topology defects were corrected on the tested zero/CARVE/FILL-CARVE/neighbor/negative/historical cases. The final independent angle-ordered extractor matches the R9.3 reference mesh on the frozen X+ mesh hash and has 13 internal openings with 0 nonmanifold edges, exactly the same openings as that reference. However, the frozen R9.4 X+ target requires no openings, so it remains unmet. The 25-ray CPU proxy remains 9/25 disagreements with maximum error 2.096206769 world units. The 8 cutoff drops in the X+ path include a minimum dropped squared cross product of 8.90332212726756e-17, below the unchanged 1e-12 cutoff. D is not accepted as meeting geometry targets.

## Identity and scope

- Tested source commit: 6ea04229b5ff06090f346c8749c1f5a53994227c
- Direct parent / R9.3-D base: 51744eebf17646ca52612936146adeb0f9db001b
- Only source paths changed: game/tests/prototypes/p3_1_r9_2_candidate_impl.gd, game/tests/prototypes/p3_1_r9_3_targeted_probe.gd.
- Production files, storage schema, canonical SDF and frozen inputs were unchanged.
- Manifest SHA-256: 1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972.
- Godot 4.7.2.stable.official.ed1daf0bf, executable SHA-256 c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643.

## Corrections and results

1. **Canonical lattice-edge roots in the primary extractor.** Endpoint order was canonicalized and shared roots cached by lattice edge identity. This failed as a geometry correction: counts slightly worsened, e.g. zero 214/67→213/68 and FILL/CARVE 272/86→271/87 (opens/nonmanifold); neighbor and X+ counts were unchanged.
2. **Polygon assembly and orientation.** Replace incidental hit order with an angle-ordered intersection polygon; orient using the tetrahedron’s finite-difference gradient; use canonical root identities including exact-zero lattice nodes. The first run had a GDScript indentation/compiler error and executed no scenario. A corrected retry of the same correction passed focused execution. This is one implementation attempt; the compile repair is not a separate geometry hypothesis. The independent extractor matched the R9.3 reference mesh on the same reloaded float32 volume bytes.
3. **X+ drop diagnosis.** Preserve the fixed cutoff and record the failing three-root polygon drops. X+ remains 13 openings exactly matching the independent reference; 8 triangles are cutoff-dropped, minimum squared cross product 8.90332212726756e-17.

## Final focused topology

| Frozen case | Original extractor baseline opens / nonmanifold | Final candidate opens / nonmanifold | Final triangles |
|---|---:|---:|---:|
| Zero | 214 / 67 | 0 / 0 | 318 |
| CARVE | 219 / 71 | 0 / 0 | 324 |
| FILL/CARVE | 272 / 86 | 0 / 0 | 404 |
| Neighbor pair | 567 / 183 | 0 / 0 | 870 |
| X+ equal LOD | 446 / 136 | 13 / 0 | 654 |
| X+ mixed LOD | 446 / 136 | 13 / 0 | 654 |
| Negative-region pair | 0 / 0 | 0 / 0 | 1,148 |
| Historical triangle 3103 | 0 / 0 | 0 / 0 | 8 |

For X+, the final candidate and independent reference produce exactly equal mesh hashes and the reference itself also has 13 internal opens. That establishes agreement between those two extraction paths on this frozen materialized volume; it does not meet the no-open-edge criterion and does not establish the reference is geometrically conforming.

## E2E and performance observations

Final E2E run D-e2e-final used exact source 6ea042…, PID 55680, exit 0, 13.182 s; 21 variants completed, including D-specific corruption reload. Build p50/p95 milliseconds from five same-process samples:

| Case | p50 / p95 ms |
|---|---:|
| Zero | 46.04 / 47.56 |
| CARVE | 47.99 / 49.75 |
| FILL/CARVE | 56.73 / 58.32 |
| Neighbor pair | 130.88 / 141.48 |
| X+ equal LOD | 106.99 / 110.10 |
| X+ mixed LOD | 97.33 / 99.08 |
| Negative-region pair | 152.28 / 176.04 |
| Historical triangle 3103 | 4.06 / 4.06 |

These are headless CPU build times; not frame time, GPU, PhysicsServer or product performance. The 25-ray CPU proxy remains 9 disagreements; maximum absolute position error 2.096206769 world units. The finite root scan is not a certified oracle.

The E2E volume measurement is experimental and same-process: zero edit materialization about 3.3 ms / extraction about 14.7 ms; neighbor pair about 9.6 ms / about 40.2 ms; X+ about 8.7 ms / about 33.2 ms; negative pair about 8.4 ms / about 57.4 ms. It does not include production publication, durable storage, GUI stalls, or per-scenario RSS. See raw JSONL for individual observations.

## Validation

- Final focused probe: 9 scenarios, exit 0; X+ remains a geometry-target failure.
- Contract suite: 160 assertions, 0 failures, exit 0.
- Full scripts/validate.ps1: 21 groups, 21,464 assertions, 0 failures; exit 0, 517,271 ms. Three existing nonfatal camera warnings were preserved in stderr.
- E2E campaign completed all 21 variants; per-row limitations remain visible in JSONL.
- Evidence files and event JSONL are checksummed by SHA256SUMS.txt. The original large baseline stderr remains only at C:\r94-evidence.

## Limits

D’s focused topology improvement validates a test-only alternative extractor against its independent angle-ordered comparator for frozen data. It does not repair all X+ openings, eliminate ray disagreement, establish continuous-surface fidelity, or validate the volume as an authority. Production adoption is not authorized.
