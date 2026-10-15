# F2 G1 — minimum viable isolated G1 route, R1 independent review BLOCKED

**Recorded:** 2026-10-15 (America/Sao_Paulo).  
**Independent review result:** `BLOCKED_WITH_EVIDENCE`, retained without retroactive modification.  
**Independent reviewer:** Codex (owner-supplied verbatim review; ChatGPT records, does not self-certify).  
**Repository:** https://github.com/publiomcko-cloud/procedural-sandbox-simulation  
**Reviewed branch:** `docs/f2-g1-minimum-viable-g1-route-r1`  
**Exact reviewed HEAD:** `5d818f0ccb220e4ef11ff7c85527a959a1713b01`  
**Direct parent:** `d6887464c8fdcf153a2cbd9b8c037464049dd7a9`.

## Identity and scope

Codex reported correct origin, reviewed branch at exact HEAD, verified parent/ancestry, clean detached worktree and **exactly two documentation paths**:

1. `docs/decisions/F2_G1_MINIMUM_VIABLE_RUNTIME_PATH.md`
2. `docs/status/F2_G1_ACTIVE_HANDOFF.md`

No VM, Hyper-V/G:, live ACL, elevated updater, production migration, Godot, Voxel Tools, CI or release operation was exercised in this independent documentation review.

## Architectural assessment accepted conditionally

The reviewer judged the path to be the smallest viable **conditional architecture identified**: reuse the previously reported-OFF, already-provisioned isolated Hyper-V candidate and the independently reviewed source-only PR #45/#47 supervision design; **do not** make production v2/v3-to-v4/v5 migration a dependency of the isolated P0.1-F2 experiment. Existing Issue #26 isolation, Issue #44 watchdog/resource/evidence requirements, R3's unsupported cutover and release hold remain binding. PR #47 `PASS_DESIGN` proves neither live VM readiness nor native authorization.

## Exactly one blocking provenance finding

Decision paragraph 2, originally line 11, asserted **"Production v2 is retained"** as present state. The last Issue #48 owner report dated 2026-10-13 records a third failed protected update (elevated child exit 1) and **mandates read-only postfailure attestation** before treating the installed C: state as verified. Previous protected v2 pass reports are historical. The GitHub issue record does not prove current v2 preservation, successful v3 activation or absence of transaction artifacts. Require `CURRENT_PROTECTED_STATE_UNKNOWN / V3_NOT_ATTESTED` until a separately authorized and completed read-only host postflight; this unknown must not be a dependency for F2's disposable-VM experiment.

**Required correction:** qualify current protected C: state as unverified, attribute old v2 acceptance to dated receipts, and preserve the independence of the isolated-guest route. The reviewer recommended a new immutable correction candidate and fresh independent review, rather than approving R1.

## Unresolved operational gates and restrictions

`ACL_REVIEW_REQUIRED / WATCHDOG_NOT_QUALIFIED / INERT_ENFORCEMENT_NOT_RUN / RENDERER_UNKNOWN / EVIDENCE_DISPOSAL_UNKNOWN / G1_BLOCKED_ENVIRONMENT / F2_G1_RELEASE_HOLD`. No live ACL/G:/Hyper-V access, UAC, staging, Godot, native probe, CI, PR, merge, production upgrade, rollback, cleanup or release is authorized by this report.

**Follow-up:** New separately authored R2 source-only correction candidate must receive its own independent exact-SHA review. Preserve this blocked R1 result unchanged.
