# R7.3 full edited-gate evidence

Run date: 2026-10-27. Tested source: `7ad45d8c817ecb0f54a8eec058babce65af287db` (parent `c54f337cb1f2b1e6d1f61de5c1b9d9f3031e892d`). Both scenario gates used the same detached checkout and isolated Godot profile. No source, manifest, oracle, production path, save, schema, or F2-G1 state was changed.

The raw `carve.stdout.log` and `fill.stdout.log` files are complete process captures. Their paired stderr files are empty. Launch intents, process records, the editor-import record, resource-sampler output, preflight records, recovery notes, parser scripts, and derived summaries are retained alongside them. `SHA256SUMS.txt` covers every artifact in this directory except itself.

## Scenario dispositions

- `cave_wall_carve`: exactly one process invocation, exit 0, one `R72_SCENARIO`, one `R72_RESULT`, 21 assertions, zero failures. Frozen input SHA-256 `47ec41f63338f98c5160f58aa71c86f6ec78412dbccad7ae86805fb115592411`.
- `center_fill_then_wall_carve`: exactly one process invocation, exit 0, one `R72_SCENARIO`, one `R72_RESULT`, 21 assertions, zero failures. Canonical input SHA-256 `55d45d387bd19829bb38c4e988da25a886765f26cc34e19dd07ed808faa1bd46`; independently recomputed from the emitted canonical JSON.

The FILL/CARVE order is sequence 0 FILL then sequence 1 CARVE, both radius 0.58. Godot's `Vector3` arithmetic serializes binary32 coordinates; the derived verifier reproduces that arithmetic and checks the JSON round-trip. The FILL run records 27/31 centerline samples as open. This is reported as a geometry observation, not an approved acceptance threshold; the frozen R7.2 scenario gate does not assert full centerline openness for edited cases.

## Gate results

For both runs, Strategy A passed and reported the external patch boundary unchanged. The local pre-repair patch contained nonzero subthreshold faces; the unchanged squared-cross threshold was `1e-12`. After the local repair and full-mesh replacement, each full mesh had zero internal open-edge cracks, zero degenerate triangles, zero nonmanifold edges, zero same-winding edges, zero extracted interface contour mismatches, zero duplicate coplanar interfaces, and zero tested T-junctions. Open edges equaled the expected crop-boundary count (CARVE 360/360; FILL/CARVE 386/386).

Each run preserved all 72 collider ray queries and matched the independent two-sided triangle oracle with zero mismatches. The one-sided control retained 33 reverse-ray misses. Each had 36 sphere probes with approximately 0.13 world-unit contact difference. These are disposable test proxies; the pinned source has no production terrain collider. Sphere sweeps are discrete at 0.05 world-unit steps, so this is not a continuous collision or MTV measurement.

Internal harness timings (microseconds) were: CARVE full build 1,734,045; local repair 5,564,664; collider 2,211,208; total 11,248,964. FILL/CARVE full build 1,627,308; local repair 2,162,280; collider 2,053,619; total 7,460,252. These are single headless runs, not performance acceptance. The CARVE external resource sampler returned invariant 6,430,720-byte working-set and 0-CPU-ms samples; treat those process resource values as unavailable. No equivalent process sampler was run for FILL/CARVE. No presented FPS, GPU completion, or gameplay claim is made.

## Preserved parser and orchestration diagnostics

- `operational-recovery-01.json`: first editor-import launcher preparation failed before process creation because a relative evidence path was resolved from the wrong directory. The corrected isolated import passed; no scenario was started by the failed attempt.
- `operational-recovery-03.json`: read-only PR preflight initially invoked `gh` outside a repository context. It failed before process creation; the correction used an explicit repository argument.
- `carve.scenario-record.json` and `summarize_carve.py` preserve a derived-parser failure caused by non-finite no-hit ray values. The raw CARVE stdout is complete and authoritative; later parser scripts produced the verified summary.
- The initial CARVE summary preserves two copied expected-hash transcription errors. `carve.acceptance-summary-verified.json` compares all 11 measured source files against the previously recorded source inventory and has no mismatches.
- Initial FILL derived summaries preserve over-strict decimal/binary64 center-offset checks. `fill.acceptance-summary-f32-verified.json` reproduces the pinned `Vector3` binary32 addition and serialization round-trip; no Godot scenario was rerun.

The initial editor import passed at the same measured source SHA with exit 0 and no stderr or parser/error markers. The full project validation previously passed at that exact source commit: 21 suites, 21,464 assertions, zero failures (three existing non-fatal camera warnings). The validation was not rerun for these two scenario gates.

All results are test-only. They do not approve production adoption, a geometry contract, GUI acceptance, PR merge, or release. All five F2-G1 holds remain unchanged.
