# P3.1 R10-B1R hypothesis ID correction

Date: 2026-10-30
Draft PR: #208
Source: `45a05d75de983d2452f87bf2df8a9910bea51446`

## Preserved pre-geometry result

The exact-source import, script checks, ray diagnostic and graph contract passed.
The domain-audit process (`b1r-jsonfix-domain-audit`, PID 13008, parent
23768) exited 3 after 2,388 ms. Its first campaign output was
`candidate_domain_stage_requires_b1r`; no candidate domain was written and no
solver or geometry operation ran.

The launch used the frozen hypothesis ID
`R10B1R_DIRECT_CONSTRAINED_TRIANGULATION_FEASIBILITY`, specified by the
preregistration and owner procedure. The campaign guard still required the
older shortened string `R10B1R_DIRECT_CONSTRAINED_TRIANGULATION`. This
pre-geometry input-contract mismatch is a harness defect. It is not a
feasibility result, and B1R remains unconsumed.

## Correction

The campaign guard now requires the complete preregistered hypothesis ID. No
candidate generation, solver constraints, cutoffs or geometry expectations
changed. The new source SHA must pass its full exact-source gates, then generate
and pin a new deterministic domain before the one geometry invocation.

No solver terminal marker exists for this attempt. The pinned receipt and failed
attempts from prior source SHAs remain preserved in their original evidence
roots. No R10-B7, production adoption, merge or F2-G1 operation is authorized.
