# P3.1 R9.7 D3 Evidence Publication

Date: 2026-10-29
Event: created a draft evidence PR after the five-attempt D3 campaign closeout.
Evidence grade: GitHub PR/source identity observed; independent review pending.

## Verified publication identity

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- Last verified remote `main`: `5997a76d345f45bf86edfe83f690336391e8be27`
- PR #206: [P3.1 R9.7-D3: bounded interface convergence campaign closeout](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/206)
- State observed: OPEN, DRAFT, UNMERGED.
- Branch: `exp/p3-1-r9-7-d3-interface-convergence`
- PR head observed at creation: `92cf4403fce35f1ca0ec024523568c6f190c8cad`
- Base: `bench/p3-1-r9-6r1-candidate-d-evidence` at `7d058899abc1663ff7d4175b5a508532367cd5da`, the pinned D3.1 Candidate D source.
- Existing PR #204 was verified still OPEN/DRAFT at head `7d058899abc1663ff7d4175b5a508532367cd5da`; PR #205 was verified still OPEN/DRAFT at `d89646ced9ec9797ebd5352d39fa8c5eab09e856`. Neither was modified.

PR #206 records the already completed campaign; it does not change the five `FAILED_TARGET` results, authorize further geometry attempts, or adopt the prototype. A final documentation commit updates the report/status/index and therefore advances PR #206's head beyond the creation SHA above. The exact current head is verified in the final handoff from the GitHub PR and remote branch.

## Boundaries retained

No production integration, merge, release, save/schema change, native dependency, Issue #108/#154 implementation, or protected F2-G1 operation occurred. All five F2-G1 holds remain unchanged. The full E2E matrix and `scripts/validate.ps1` remain `NOT_RUN_NO_SURVIVING_GEOMETRY_CANDIDATE`.

See [campaign closeout checkpoint](2026-10-29-P3-1-R9-7-D3-CAMPAIGN-CLOSEOUT.md) and [campaign report](../reports/P3-1-R9.7-D3-CAMPAIGN-CLOSEOUT.md) for the five attempt results and evidence inventory.
