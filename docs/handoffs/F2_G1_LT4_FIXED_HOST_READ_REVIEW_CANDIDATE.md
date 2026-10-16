# F2 G1 — Fixed-scope owner-operated C: read-only inspection (source candidate)

**State:** IMPLEMENTED AND CI TESTED AS SOURCE; **INDEPENDENT REVIEW PENDING**; **NO OWNER AUTHORIZATION TO RUN AGAINST HOST**. Do not execute this host command until an explicit separate owner approval is issued for the independently reviewed final exact SHA, machine, account, scope and output destination.

**Accepted source base:** LT-4 disabled adapter `182f09a2aa5759288e8fe37645e84d1ccccfed4d`; accepted local-trust ADR `29f90ef9b2310044e64d3acd775534559a404425`. The branch adds only a narrowly scoped host entrypoint, changes the existing LT-4 adapter for one transient fixed-host path, expands its Windows CI negative preflight tests, adjusts its CI trigger and records this handoff. The owner authorized **preparation and source review only**, NOT live execution. R2, R3.3, LT-1, LT-2 and LT-3 remain unmodified.

## Boundaries and intended operation

A new `scripts/f2-acl/lt4/Invoke-F2G1LT4.FixedHostC.ReadOnly.ps1` has two modes: **no arguments** reports blocked readiness and exits 2; `-InspectFixedHostC` requires **all three** `-ExpectedComputerName`, `-ExpectedUserSid`, and `-ReviewedAdapterSha256`. There are no caller-chosen file or directory paths, alternate volume options, UAC elevation, writes, repairs, installs, or Hyper-V operations. A successful historical C: observation, if ever separately approved and performed, may exit 0 and use `PASS_READ_ONLY_C_POSTFAILURE_ATTESTATION`; all other results exit 2.

`Invoke-F2G1LT4OwnerHostReadOnly` in the revised LT-4 module is the *single new operational route*. It stops **before C: observation** when: not Windows PowerShell 5.1; GitHub Actions environment; wrong machine; wrong current Windows user SID; Administrators-group membership (conservative R2-compatible restriction, including a filtered UAC admin token); failing the existing real `GetTokenInformation` medium-integrity, non-elevated check; missing/incorrect **physical SHA-256 of the imported LT-4 module**; or reentrant operation. Machine/SID/SHA parameters detect operator mistakes under the agreed trusted-local model. They are **not cryptographic owner authorization**; a malicious host Administrator is explicitly outside the threat model.

Once the owner *separately authorizes running* a concrete command, the module temporarily enables the fixed host path map, directly opens **only** the 23 R2 C: objects (8 directories, 15 files) and evaluates the five frozen immediate-child inventories, without any caller-provided scope. Read-only FileStream, owner/DACL metadata, reparse/type, bounded lengths and observed drift rules reuse LT-4. Physical file byte arrays are matched to all seven R2 installed-package SHA-256 pins and to the immutable historical manifest/payload/integrity SHA-256 hashes via LT-3. Then the **unchanged** R2 private semantic core runs in `Live` historical-check mode with the same bounded read-only provider: complete ACL profiles, manifest/payload/mailbox/diagnostics/11 historical G: **path strings**. R2's public legacy `-Live` constructor and owner authorization are still disabled.

The public result is **sanitized and finite**: coarse error category and object-count progress, no raw SDDL, private SIDs, original bytes, stack traces or full host path inventory. A passed historical C: read only means the 23 required C: objects matched at that inspection time under the owner-local assumptions. It does **NOT** qualify effective ACL token rights, current V3, G: contents/VM/Hyper-V state, absence of ADS/multiple hard links or F2 G1 release readiness. All five operational holds persist until their own evidence and approval.

## Test limits and single review gate

The existing GitHub-hosted Windows CI fixture suite is extended to parse the new entrypoint and assert both its default behavior and its explicit host parameter route **block before any C: access in CI**. All pre-existing disposable LT-4/3/2/1 and R2 suites run unchanged. GitHub CI **does not and must not exercise a successful protected-host invocation**. The host flow must receive one independent code review for real-token preflight, precise fixed path mapping, transient gate reset on exception, R2 Live semantic call, immutable bytes, and sanitized output. Test or fix material functional bugs only; do not reopen the accepted adversarial threat architecture.

## Fresh explicit owner grant required AFTER independent source review

A later grant must document, **before running**:
1. Exact reviewed Git commit SHA and independently reported physical SHA-256 of `F2G1LT4.ReadOnlyAdapter.psm1`. Do not calculate a new hash at execution time and automatically accept it as the expected reviewed hash.
2. Concrete Windows host computer name and **non-administrator** Windows account SID, validated from a non-elevated Windows PowerShell 5.1 session. Avoid the filtered admin-group ambiguity by using a standard account; denied reads result in BLOCKED, never UAC fallback.
3. The exact single command with `-InspectFixedHostC`, machine, SID and fixed reviewed module hash. The **scope is immutable**: the 23 C: objects and five inventories; G: values are compared only as captured strings.
4. A safe local, non-protected destination for **sanitized JSON only**, finite output, stop on mismatch/access denial and absolutely no protected writes, privilege changes, ACL repair, installer, Hyper-V actions, PR/merge or release.

This is a **procedural authorization** suitable for a trusted, personally administered local Windows machine; the CLI parameters alone are not proof approval exists. Neither this document, the existing user permission to *prepare*, a green CI nor a future independent **source** review is the required execution approval.

**Persistent:** `CURRENT_PROTECTED_STATE_UNKNOWN`; `V3_NOT_ATTESTED`; `ACL_REVIEW_REQUIRED`; `G1_BLOCKED_ENVIRONMENT`; `F2_G1_RELEASE_HOLD`.
