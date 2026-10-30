# P3.1 R10-B1R candidate-domain audit correction

Date: 2026-10-30  
Experiment branch: `exp/p3-1-r10-b-constrained-realization`  
Existing PR: #208, draft and unmerged  
Pre-correction source HEAD: `992e3f332dd951b5456eea7731a8e1feee58e425`

## Preserved failure

The exact-source B1R domain-audit attempt `r10b1rfinal07` failed before
candidate-domain publication and before any triangulation search:

- Evidence root: `C:\Users\PUBLI\AppData\Local\Temp\p3_1_r10b1r_992e3f332dd951b5456eea7731a8e1feee58e425_f82b19e3cc0c440a9130bc43efefbe9f`
- Process PID: 6048; exit code: 3; no resource abort or timeout.
- Terminal output: `R10B_BLOCKED`, reason
  `b1r_candidate_domain_audit_failed`, detail
  `component_orientation_authority_invalid`.
- The solver was not invoked and no B1R geometry result was emitted. This is a
  pre-geometry evidence-wiring defect and does not consume the final geometry
  slot.

## Root cause and bounded correction

The first implementation selected emitted normals only when an emitted
triangle's `patch_id` exactly equaled the target component ID. The frozen
authority output does not guarantee that label on the emitted record; those
records instead preserve the source `polygon_id` and/or
`source_polygon_ids`. The filter therefore selected zero normals despite
the frozen target component and its triangles being present.

The corrected builder binds orientation samples through the exact set of 84
source polygon IDs in the selected frozen patch. It accepts a normal only from
an emitted record whose polygon identity is in that set or whose preserved
source-polygon list intersects that set. It rejects an empty or nonfinite
orientation authority and records the exact sample count. The domain artifact
identity hash includes that count. No roots, boundary, volume values, cutoff,
geometry tolerance, or acceptance rule changed.

## Next step

The corrected source must be committed to the existing PR #208 branch. Repeat
the required exact-SHA import, parser, authority, ROI-ray, graph-contract and
domain-audit gates. If the domain audit passes, record its actual artifact
SHA-256 in a write-once external receipt before the sole B1R geometry
execution. Original B1, all B2–B6 attempts, the failed R10-B historical
closeout, this failed audit, and the preregistration checkpoint remain
preserved.

No production adoption, merge, release, Issue #108/#154 work, or F2-G1
operation is authorized. All five F2-G1 holds remain.
