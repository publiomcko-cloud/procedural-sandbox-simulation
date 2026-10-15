# F2 G1 — minimum viable isolated runtime route R2 independent review PASS

**Recorded:** 2026-10-15 (America/Sao_Paulo).
**Verdict:** `MINIMUM_G1_PATH_DESIGN_PASS` — architecture/design only, not guest readiness.
**Reviewer:** Codex on a fresh detached Windows review worktree; review report supplied by the owner.
**Repository:** https://github.com/publiomcko-cloud/procedural-sandbox-simulation
**Exact reviewed HEAD:** `05ee627d25e6bca4a1cb39d768ddae34c1135f34`
**Direct parent:** `5d818f0ccb220e4ef11ff7c85527a959a1713b01`
**Reviewed ref:** `docs/f2-g1-minimum-viable-g1-route-r2`
**Historical R1:** `5d818f0ccb220e4ef11ff7c85527a959a1713b01` — `BLOCKED_WITH_EVIDENCE` preserved in `docs/reviews/2026-10-15-F2-G1-MINIMUM-PATH-5d818f0-BLOCKED.md`.

## Scope and independent evidence

The reviewer reported a matching repository origin, exact branch and commit identity, verified parent/ancestry and a clean detached worktree. The R2 parent diff changed **exactly three documentation paths**:

- `docs/decisions/F2_G1_MINIMUM_VIABLE_RUNTIME_PATH.md` — modified.
- `docs/reviews/2026-10-15-F2-G1-MINIMUM-PATH-5d818f0-BLOCKED.md` — added as a preserved historical R1 finding.
- `docs/status/F2_G1_ACTIVE_HANDOFF.md` — modified.

**Codex-reported Windows-checkout SHA-256**, distinguished from Git blob identities:

| R2 reviewed file | SHA-256 |
|---|---|
| Minimum-path decision | `85FB10D607A7A2B90E539F50DB54DB3F76F5171C9D367B062B9C41FED495D35C` |
| Active handoff | `0F9E92CB3574445E058FD344BB76D7D8A9F2112C843588E520608619D6209B05` |
| Preserved R1 blocked review | `AA66652EBEA6DEDCF30E3D2F7C825696C26EF74F20B0CD390B27757F32EC156E` |

The R2 correction resolved the sole R1 material finding: prior v2 installation acceptance is described as **historical**, the current post-third-UAC protected C: installed state is **not verified**, and the failed updater's diagnostic stage does not prove v2 preservation, v3 activation or absence of transaction artifacts. The current protected installation remains `CURRENT_PROTECTED_STATE_UNKNOWN / V3_NOT_ATTESTED`, independent of F2's standalone guest experiment. No fourth UAC is authorized.

The reviewer confirmed the smallest **conditional** compliant architecture identified: reuse the already provisioned, *historically reported OFF* Hyper-V VM from [Issue #48](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/48) and the already independently reviewed **source-only** supervision design at [PR #45](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/45) HEAD `5a5ba68350d316a2626c3c1a3598d45d1498804c` ([PR #47](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/47) `PASS_DESIGN`). Preserve [Issue #26](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/26) native isolation prerequisites and [Issue #44](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/44) supervision/evidence safeguards. Do **not** make a protected production v2/v3-to-v4/v5 migration a prerequisite for the isolated P0.1-F2 compatibility experiment. The R3 transaction design supports no live v2/v3 predecessor cutover and creates no such authorization.

## Nonblocking observations

- Codex reported `git diff --check` trailing whitespace on Markdown hard-break lines in the **historical R1 review**. This is cosmetic; preserve the reviewed R1 file and original verdict byte-for-byte rather than silently rewriting evidence to remove it.
- The R2 decision text calls the Hyper-V capability SID *unexplained*. The [Issue #48 comment of 2026-10-09](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/48#issuecomment-6090291045) already identified the capability's **Hyper-V VM Bus Provider / vmwp.exe-related purpose**. What remains unaccepted is the **effective scope** of broad Full Control across the project tree (and shared Virtual Machines group directory-create/write rights), not the basic SID purpose. This clarification is recorded as a review note without editing the exact R2 decision.
- A retained protected local ACL baseline was **owner/Codex reported** complete on 2026-10-10: 11 approved paths, 82 ACEs. Its independent `icacls` corroboration for the *same pinned baseline*, current ACL effective-rights review and potential remediation remain unresolved. An older 2026-10-09 `icacls` observation is historical, not an automatic substitute for the requested later corroboration. Do not infer `PASS_RESTRICTIVE_ACL`.

## Gate disposition and next minimal decision

**Accepted:** `MINIMUM_G1_PATH_DESIGN_PASS / FEASIBLE_CONDITIONAL`.
**Still blocked:** `ACL_REVIEW_REQUIRED / VM_OFF_LAST_REPORTED / WATCHDOG_NOT_QUALIFIED / INERT_ENFORCEMENT_NOT_RUN / GUEST_TOKEN_UNVERIFIED_FOR_GODOT / RENDERER_UNKNOWN / EVIDENCE_DISPOSAL_UNKNOWN / F2_A_TO_G_NOT_RUN / G1_BLOCKED_ENVIRONMENT / F2_G1_RELEASE_HOLD`.

The **smallest next scoped action** is an owner decision on independently reconciling the already retained, locally protected ACL baseline and the missing read-only `icacls` corroboration of exactly the 11 pinned VM objects. Start with existing source/evidence provenance and an exact reviewed, no-guest, no-write command plan. Any *live* G:/Hyper-V query, `icacls` access, token/elevation or protected evidence read/write must be separately authorized within an explicitly pinned scope. If broad capability/group privileges remain unresolved after corroboration, record `ACL_REVIEW_REQUIRED` and propose (not execute) minimal remedial options.

**Not authorized here:** any C: protected updater or recovery, fourth UAC, VM start/stop or guest installation, G: writes, ACL mutation, live target `icacls`, Godot, Voxel Tools, CI, PR, merge, release or backend selection. Neither this record nor R2's accepted design asserts a fresh Windows host inspection or G1 operational readiness.
