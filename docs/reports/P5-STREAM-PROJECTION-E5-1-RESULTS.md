# P5 E5.1 — stage-level profiling and deterministic noise reuse

Source: [GitHub Actions #43203102342](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/43203102342), exact seed and mod-derived geometry from 12 fixed samples. Baseline shape and opt-in variant gave **94 parity assertions, zero failures**; stderr scanning was hardened to reject any `ERROR:`.

Mean standalone shape geometry cost:
- Original: **16.309 ms**
- Fast pairwise crosses plus local lattice-noise reuse and normalized wear vectors: **15.570 ms** (4.53% faster)
- Baseline preparation: 7.096 ms (clipping 2.448, wear 3.962, triangulation 0.054, subdivision 0.570).
- Baseline roughness: 6.254 ms.
- Baseline guarded-plane intersections: 2.744 ms, optimized intersections: 2.522 ms.
- Finalization+validation+ground: ~0.214ms.

**Verdict:** NO_MATERIAL_GEOMETRY_GAIN (<10% standalone). No 16-route benchmark was initiated for E5.1; no integration into main. This exposes a larger system throughput constraint, rather than a single expensive vector operation. Next isolated experiment should test bounded projection job concurrency and budgeted publication, with unchanged authoritative geometry and revision gates, against original E2 on same SHA/runner.
