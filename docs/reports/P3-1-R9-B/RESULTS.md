# P3.1 R9 Candidate B — bounded result

**Disposition: `R9_B_BLOCKED_WITH_EVIDENCE`**

Candidate B is a test-only one-level adaptive Hermite/QEF dual-contouring prototype. The zero-edit build completed within resource limits, but its first mandatory topology gate failed. No edits, mixed-LOD seams, frozen ray displacement case, picking/collider comparison, or later scenarios were run. This is a candidate failure, not a claim that dual contouring cannot be made conforming.

## Provenance

- Common R9 parent at execution: `a60d38df4f96b9007162e8fd917b3d14f29dcb0f`.
- Candidate source physical SHA-256: `c156a90f880e7dafeb2662b2c10083fd6616e4c8d190f46276bba8ec7847db65`.
- Shared helper SHA-256: `a1ca1b958a15985111de71b3750090f8d226c1274e276802bd8236b66b10c671`.
- Frozen JSONL SHA-256: `2b44cb52ef091c2527fa2f8b06859752cc7cfaa14bcafe94d4a4c55b0cdd908f`.
- Godot `4.7.2.stable.official.ed1daf0bf`, executable SHA-256 `c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643`.
- Isolated profile and temporary roots: `C:\r9b\evidence\profile` and `C:\r9b\evidence\temp`.

At run time the candidate script was untracked on parent `a60d38d…`; its physical hash above pins the exact script bytes. The report commit packages that source and raw output.

## Zero-edit result

Editor import and `--check-only` exited 0. The candidate was invoked once (exit 1; process PID was not captured). It reported:

- 2,457 initial coarse nodes; 6,241 unique samples after one refinement level on sign-active parents.
- 356 active parent cells; 598 emitted triangles.
- 214,694 µs build time as reported by the prototype (headless CPU duration, not frame or GPU timing).
- 110 internal open edges, 0 ROI-boundary open edges, 0 nonmanifold edges, 0 degenerate triangles, 0 winding inconsistencies.
- Mesh SHA-256 `0720bd3307b918a8c592df2aeb7c27e5643c1113abcedc1ff9d7c81eea91eb90`.

The exact structural gate requires zero unexplained internal opens and therefore failed. The code's `refined_parent_cells` metric currently increments once per Y sub-slice, so its emitted value 1,068 is not a unique parent-cell count; the unique active parent count is 356. Likewise, `quads` counts emitted triangles rather than completed quads. These instrumentation labels are explicitly unreliable and must not be used for comparison. They do not change the topology result. The prototype does not yet construct balanced adaptive leaves or transition templates; its adaptive part refines Hermite constraints while retaining parent-cell dual connectivity. This is an incomplete Candidate B implementation.

## Shared project validation

Godot 4.7.2 `scripts/validate.ps1` exited 0 on this worktree: **21 suites, 21,464 assertions, zero failures**. The log ends with `VALIDATION_PASS: L0-L2; GUI visual test remains an owner task`. This is project-regression evidence only; it does not validate Candidate B geometry. The log also records the unavailable Issue #118 reparse fixture and three non-fatal camera colinearity warnings.

All source/input/run logs and hashes are in [`evidence/`](evidence/); `SHA256SUMS.txt` covers the candidate, shared helper, manifest, import, parser check, single candidate output, and complete validation log.

## Conclusion

Candidate B is blocked by 110 internal open edges and is also incomplete against the adaptive-leaf/balanced-interface scope. The frozen stop rule was respected: zero topology failure stopped the candidate before downstream cases. No thresholds or input records changed. No production code, schemas, PR #168, or F2-G1 state changed. PhysicsServer, GUI, rendered pixels, GPU, and product tolerances are `NOT_RUN`/not approved.
