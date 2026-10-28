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
