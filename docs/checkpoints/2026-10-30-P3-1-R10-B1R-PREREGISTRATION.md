# P3.1 R10-B1R preregistration checkpoint

Date: 2026-10-30
Repository: `publiomcko-cloud/procedural-sandbox-simulation`
Experiment branch: `exp/p3-1-r10-b-constrained-realization`
Existing implementation/evidence PR: #208, open/draft/unmerged
Verified starting HEAD: `f4c6bfdaf78720dc8aad8834fd16e456f0aee07a`
Starting parent: `0b192d4724c9a5ad3b65134a7f50e39f8677a5cb`

## Authorization and scope

The owner authorized one final R10-B geometry hypothesis, B1R direct
constrained triangulation. The independent correction says original B1 was a
harness error and not a consumed geometry hypothesis. B2–B6 are the five
previous valid geometry results. B1R is slot six; no B7 is authorized.

This remains an isolated test-only investigation. No production terrain,
playable scene, save, schema, merge, release, Issue #108/#154 or protected F2-G1
operation is authorized.

## Preregistered contract

The complete direct candidate domain, ordering, validity predicates, exact
root/boundary/ownership requirements, deterministic MRV exact-cover search,
termination classifications, limits and sequential gates are frozen in
[B1R attempt preregistration](../reports/P3-1-R10-B-CAMPAIGN/B1R-ATTEMPT-PREREGISTRATION.md).
The existing accepted cutoff remains `cross_squared > 1e-12`; no geometry
tolerance is changed. Domain artifact bytes and SHA-256 do not exist until the
pre-geometry domain-audit stage and must be captured before the one geometry
execution.

## Preserved preflight evidence and corrections

The original base source passed Godot import, campaign check-only, authority
check-only, ROI ray-causality and graph-contract preflight in evidence root:

`C:\Users\PUBLI\AppData\Local\Temp\p3_1_r10b1r_c2788509cea44d55abe0cfed1a37493e`

The first B1R check-only attempt exposed a missing cutoff declaration in the
new harness. Its parser failure is preserved at:

`C:\Users\PUBLI\AppData\Local\Temp\p3_1_r10b1r_tooling_77169f9ce8dd4468ad26d801db698e12`

No geometry code executed in that failed attempt. The correction was bounded
to declaring the unchanged `1e-12` cutoff. A later source review also corrected
the scope of candidate insertion and added loader checks for fixed source
ownership, candidate ownership, boundary simplicity and connected vertex
links. Current dirty-tree parser evidence is separately preserved under:

`C:\Users\PUBLI\AppData\Local\Temp\p3_1_r10b1r_preflight_e1ca7b5576794da295aa83e98e802b15`

Those check-only results are not represented as final-commit validation.
Before B1R, all gates must be rerun against the exact committed source, with
physical source hashes and fresh process records.

## Repository preservation

The isolated R10-B worktree, its stashes, pre-existing untracked Godot UID
files, prior attempt records, PR #207 and all user workspaces are preserved.
No user save or protected host state was read or changed. The five F2-G1 holds
remain:

`CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`,
`ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`,
`F2_G1_RELEASE_HOLD`.

## Next authorized step

Finish source/static checks, commit the experimental B1R implementation and
this preregistration to the existing PR #208 branch, then run import, parser,
authority, ray, graph-contract and deterministic domain-audit gates on that
exact SHA. Record the generated domain hash in a write-once external evidence
receipt before the single geometry execution. Tooling failures before a valid
geometry terminal result do not consume B1R; a valid B1R terminal result does.
