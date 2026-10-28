# R9.3-A — exact global edge-root identity findings

Measured candidate source: `e6cce1417fc140ad71b249fb561755ea80a6ea86`; it descends from the R9.3 preregistration commit `fb599d9a940e38f0fd985b9209d589200c217b47` and R9.2 evidence head `9c2b187abc93b155a2546d66035b8075390bd451`. Frozen manifest SHA-256: `1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972`.

## Hypothesis and correction

The candidate previously keyed scalar samples using a quantized world-point string and cached bisection roots in traversal order. That permitted nearby samples to collide and could make opposite traversal directions use different floating-point bisection arithmetic. R9.3 uses the exact packed Vector3 bytes for sample keys and an unordered pair of global integer lattice endpoints for root identity. It canonicalizes endpoint/value order before the fixed eight bisection iterations. Canonical SDF sampling, operation order, mesh extraction and the `1e-12` squared-cross-product cutoff remain unchanged.

The focused root identity probe ran on eight frozen scenarios (zero, CARVE, ordered FILL/CARVE, same-resolution neighbors, X+ equal seam, known X+ defect, X− displacement, triangle 3103). It reported a valid probe in all eight: forward/reverse roots were bitwise equal and deliberately colliding quantized sample keys had distinct exact packed keys.

| Frozen case | R9.2 internal open edges | R9.3 internal open edges | R9.3 nonmanifold |
|---|---:|---:|---:|
| zero | 0 | 0 | 0 |
| CARVE | 0 | 0 | 0 |
| FILL/CARVE | 0 | 0 | 0 |
| neighbor pair | 4 | 4 | 0 |
| X+ equal seam | 12 | 12 | 0 |
| known X+ defect | 12 | 12 | 0 |
| X− displacement | 0 | 0 | 0 |
| triangle 3103 | 8 | 8 | 0 |

The root arithmetic property is corrected, but it does not repair the known neighbor, X+ seam or triangle 3103 topology counts. This probe demonstrates edge identity and deterministic arithmetic; it does not establish continuous-SDF root exactness or mixed-LOD conformity.

## Disposition

`PARTIAL_CORRECTION`. Root-key collision and endpoint-order variation are addressed by a direct property check, while the material topology failures remain unchanged. Full frozen E2E recampaign, canonical ray-grid parity and independent mixed-LOD interface verification remain required for broader claims. Mesh cave connectivity remains `NOT_IMPLEMENTED`; no GUI/GPU or production claim is made.

## H2/H3 correction and final frozen E2E evidence (2026-10-28)

The measured test-only source is now `4f9925f6b87bb80eecc98acb25e9e385579b525e` (parent `71e68101a67f9b75017e57644501fdf83ba9c637`). H1 retains exact packed-Vector3 sample keys and canonical unordered global lattice-edge keys. H2 adds an exact-zero endpoint rule: when one edge endpoint has density exactly zero and the other is negative, use/cache the zero endpoint instead of approximating it through the frozen eight bisections. It does not change the canonical SDF, operation order, mesh cutoff, or tolerances. H3 independently counts exact binary32 vertex-edge incidence alongside the existing quantized topology view.

Focused H2/H3 validation covered the same eight fixtures. The exact endpoint tests passed in both edge traversal orders with zero additional SDF samples. Exact-byte topology incidence agreed with the quantized core counts on all eight fixtures, so the remaining neighbor and X+ openings are not an artifact of that topology quantization. Results are still not topology acceptance:

| Fixture | Internal open edges | Other boundary evidence | Nonmanifold |
|---|---:|---|---:|
| zero / CARVE / ordered FILL-CARVE | 0 / 0 / 0 | ROI boundaries remain separately counted | 0 |
| same-resolution neighbor pair | 4 | internal openings remain | 0 |
| X+ equal / known X+ defect | 12 / 12 | internal openings remain | 0 |
| X− displacement | 0 | finite ROI diagnostic only | 0 |
| historical triangle 3103 | 0 | 8 openings are on the cropped ROI boundary after H2; this is not proof of a closed full mesh | 0 |

The two independently audited final-source E2E processes each emitted 44 JSONL records (one campaign start, 21 scenario start/complete pairs, one campaign completion), with 20 in-scope cases `COMPLETE`, the D-only corruption case `NOT_RUN`, zero `FAIL` and zero `CENSORED`. Run IDs are `R9.3.A.2.0d635ad8fa514ed7b6a5dd9327c93e76` and `R9.3.A.3.dec642b808c64cca93717664c6d14ae2`. Their process records show exit 0, no timeout/stop reason, and sampled process-tree peaks of 109,686,784 and 110,174,208 bytes. Independent audit status is `PASS_EVIDENCE_STRUCTURE_AND_EXECUTION` for both. The prior A1 campaign is preserved, not counted as a valid repetition: its events completed, but process exit remained null and its audit reported only `process_record_not_successful`.

| Scenario | R9.3 A2 p50 / nearest-rank p95 µs | R9.3 A3 p50 / nearest-rank p95 µs | Topology / ray observation |
|---|---:|---:|---|
| zero | 38,177 / 40,157 | 36,465 / 37,080 | 0 internal opens / 0 nonmanifold |
| CARVE | 39,074 / 41,941 | 39,715 / 45,176 | 0 / 0 |
| FILL-CARVE | 48,493 / 53,535 | 46,766 / 50,884 | 0 / 0; normal deviation p95 remains 57.96° |
| neighbor pair | 106,919 / 115,095 | 104,174 / 105,715 | 4 internal opens / 0 nonmanifold |
| X+ equal seam | 81,959 / 86,544 | 99,205 / 136,842 | 12 internal opens / 0 nonmanifold |
| local rebuild | 139,292 / 143,290 | 151,106 / 165,481 | Full diagnostic snapshot rebuild, not incremental production remeshing |

Each build distribution above contains five samples within that process; p95 is nearest-rank and is not pooled across processes. This headless ray proxy still reports **9/25 hit/miss disagreements**, absolute position-error p50 `1.3209` and maximum `1.7962` world units. That matches the R9.2 A disagreement count and maximum within reported precision; H2 did not repair picking. Timings are CPU-only, and E2E process-tree peak is not per-scenario memory.

Godot `4.7.2.stable.official.ed1daf0bf`, executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`. The full `scripts/validate.ps1` run on exact source `4f9925f6b87bb80eecc98acb25e9e385579b525e` exited 0 in 514.98 s: 21 assertion markers, 21,464 assertions, zero failures, 24 L2 pass markers. Stderr contained three pre-existing nonfatal colinear camera-vector warnings from `procedural_object_tests.gd`; no parser/script errors. Full logs and process record are under `evidence/validation/`.

Campaign raw stdout/stderr, process records, JSONL-derived CSVs and independent audit outputs are committed under `evidence/campaigns/`; SHA-256 manifests cover evidence and source pins. Standard-output hashes: A2 `39cf37e4fde1494616d89b246de8a21dc2a9712f682a7388c91924f701af2afa`; A3 `d7f6c359c5c74f59941d0b70522fd572ac2d8b2aac48c75cb31682f773b7cd29`. A1 remains recorded as an evidence-capture blocker, not hidden.

**Disposition remains `PARTIAL_CORRECTION`.** Root identity and exact-zero endpoint behavior are directly corrected, but the known neighboring/X+ topology and ray defects persist. Nothing here establishes mesh watertightness, mixed-LOD chunk joining, rendered/GPU behavior, GUI acceptance, or production readiness.
