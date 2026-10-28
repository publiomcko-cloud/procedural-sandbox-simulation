# P3.1 R9 Candidate C — bounded result

**Disposition: `R9_C_BLOCKED_WITH_EVIDENCE`**

Candidate C is a test-only uniform Surface Nets prototype with one linearly interpolated representative per sign-active 0.5-unit cell and dual quads around sign-changing primal edges. The one frozen zero-edit case failed its first required exact topology gate; no second deterministic build, edits, seams, ray/picking comparison, PhysicsServer, or later cases ran.

## Provenance

- Common R9 parent at execution: `a60d38df4f96b9007162e8fd917b3d14f29dcb0f`.
- Candidate source physical SHA-256: `2c8bfaf8954d0941bf63a5832148a55dae0504a06bd1445aca5b72a04945734e`.
- Shared test helper SHA-256: `a1ca1b958a15985111de71b3750090f8d226c1274e276802bd8236b66b10c671`.
- Frozen manifest SHA-256: `2b44cb52ef091c2527fa2f8b06859752cc7cfaa14bcafe94d4a4c55b0cdd908f`.
- Godot `4.7.2.stable.official.ed1daf0bf`; executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- Isolated user-data/temp roots: `C:\r9c\evidence\profile` and `C:\r9c\evidence\temp`.

The candidate source was untracked at run time on `a60d38d…`; its physical SHA-256 pins the measured bytes, subsequently committed with this report. Import and standalone check-only both exited 0. The zero case ran once and exited 1.

## Zero-edit geometry

- 2,457 unique canonical samples; 356 sign-active cells; 1,424 linearly interpolated edge constraints.
- Build duration: 59,946 µs; emitted 598 triangles; mesh SHA-256 `395bd6d1a8d81c71ef78e6193cdf0379bf5d416cd41a564a3c08cf68626f1abc`.
- Topology: 110 internal open edges; 0 ROI-boundary open edges; 0 nonmanifold edges; 0 degenerate triangles; 0 winding inconsistencies.
- Terminal record: `P3_1_R9C_RESULT`, five assertions, one failed assertion (`zero_surface_nets_no_internal_open_edges`), `BLOCKED`, reason `zero_topology_gate_failed`.

The terminal field called `quads` is actually the number of triangles returned by `_quad`, and the implementation does not report rejected triangle count. The report uses only the unambiguous emitted-triangle count and preserves this instrumentation limitation. Because the exact structural gate failed, the required second deterministic build and all downstream geometry cases were correctly not run. No threshold was relaxed.

## Shared regression validation

Full Godot 4.7.2 `scripts/validate.ps1` exited 0 with **21 suites / 21,464 assertions / zero failures** and the final `VALIDATION_PASS` marker. This is shared project regression evidence, not a Candidate C geometry pass. The raw log includes the unavailable Issue #118 reparse fixture and three non-fatal camera colinearity warnings.

Raw logs and a SHA-256 inventory are in [`evidence/`](evidence/). Candidate process PID was not captured. Headless timings do not represent rendered frame time, GPU completion, or visual acceptance. Product geometry tolerances remain unapproved.

## Conclusion

Candidate C is `R9_C_BLOCKED_WITH_EVIDENCE` at its zero-edit topology gate. The input, mesh and logs are preserved; no edits or seam cases ran. This does not establish Surface Nets as inherently nonconforming. Production source, save schemas, PR #168, and all five F2-G1 holds remain unchanged.
