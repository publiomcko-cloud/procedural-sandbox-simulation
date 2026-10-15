# Developer handoff: F2 G1 C: postfailure inspector

Status: R1 independent review BLOCKED_WITH_EVIDENCE; R2 source-only fail-closed patch awaiting independent review.

Ticket / acceptance criteria: Prepare a bounded Windows PowerShell 5.1 source-only inspector and inert synthetic suite; do not perform the protected C: attestation. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.

Repository / remote: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`

Worktree / branch: `C:\Dev\f2-g1-c-postfailure-inspector-r1` / `fix/f2-g1-c-postfailure-inspector-r1`

Base SHA: `33e985b8e7807bf1feda935374889efd5e5f158a` (accepted PR #50 PowerShell 5.1 entrypoint bridge)

Candidate source SHA: `11773a928f39efda32a8f79c7133debe3d5c00bc` (inspector/test implementation commit; no source files changed afterward)

R1 candidate direct parent: `11773a928f39efda32a8f79c7133debe3d5c00bc` (implementation parent: `c45127d567653fdae47bef9f017803568f3686f9`). The accepted bridge `33e985b8e7807bf1feda935374889efd5e5f158a` is an ANCESTOR, not the direct parent. R2 source branch parent is R1 candidate `009d77cfdb62c4f054dd19b90dd8654f96f354b4`.

Changed paths:

- `scripts/f2-acl/F2G1CPostfailureAttestation.psm1`
- `scripts/f2-acl/Invoke-F2G1CPostfailureAttestation.ps1`
- `scripts/f2-acl/Test-F2G1CPostfailureAttestation.SourceOnly.ps1`
- `docs/handoffs/F2_G1_C_POSTFAILURE_INSPECTOR.md`

Implementation summary: Adds an exact path allowlist for the reviewed C: system parents, F2 package directories/files, active manifest, seven-file baseline mailbox, and enumerated immediate transaction-artifact names. The live provider uses bounded read-only file reads, path/ancestor reparse checks, ACL metadata reads and immediate-child enumeration only. It rejects administrator tokens and membership in the local Administrators group, requires a new Issue #48 comment reference in live mode, and rejects the spent comment `6196160426`. The wrapper has no default execution mode and only imports the new inspector module. The test creates a single disposable fixture document under a guarded direct TEMP child and removes only that guarded fixture directory.

Architectural impact: None to production. Historical V2 preservation evidence is inspected only as data. No installed script/module is imported or executed; no external authority, cryptographic signature, durable storage, or effective token authorization is provided. The report cannot establish `PASS_RESTRICTIVE_ACL`, V3 readiness, or production readiness.

Dependencies added / licenses: None.

Tests executed (exact commands):

- Windows PowerShell 5.1 parser-only process, started by `ProcessStartInfo` with `UseShellExecute=false`, redirected stdout/stderr, bounded 15-second startup, exit capture and disposal. Parsed module, wrapper, and test source before execution.
- Windows PowerShell 5.1 inert suite: `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2G1CPostfailureAttestation.SourceOnly.ps1`, run as a child with redirected streams and a 30-second bound.
- `git diff --check`

Results / assertion counts: parser-only Windows PowerShell 5.1 process exited 0 with `PARSE_ERRORS=0` for all three candidate PowerShell files. The inert suite exited 0 with `ASSERTIONS=19 FAILURES=0`; stdout and stderr were drained, no timeout occurred, and the guarded TEMP fixture was cleaned up. `git diff --check` passed after staging.

Tests not executed: No live C: inspection; no C:, G:, Hyper-V, VM, UAC, `icacls`, updater, installation, ACL mutation, CI, or release operation.

Failure/recovery cases: Synthetic cases cover simulated access denial, missing required object, unexpected immediate artifact, malformed active manifest, package hash mismatch, incomplete 11-object baseline, administrator token, and reparse object. All failures return a closed blocked verdict.

Benchmark machine and metrics: Not applicable.

Known limitations: A future owner must separately authorize a fresh, exact-SHA, exact-scope read-only C: inspection after independent source acceptance; the prior authorization is spent. The live inspector only checks that a supplied reference has Issue #48 comment URL shape and is not the spent ID; a human must independently verify the new comment's author, scope, and latest restrictions. It does not read repository metadata or prove the running inspector's Git identity. ACL ACE checks are not effective-token analysis. No production behavior or protected state was observed.

Visual reproduction steps: Not applicable.

Rollback instructions: Delete the isolated local topic worktree/branch only after review evidence has been retained; no shared branch or remote was changed.

Reviewer focus / open questions: Verify the live allowlist against current Issue #48 restrictions, baseline evidence format and historical pins; inspect fail-closed path handling and synthetic coverage. In particular, confirm the report's ACL metadata remains sanitized and is not mistaken for effective-token acceptance.

## R2 independent-security correction (source-only, no host attestation)

- R1 was **rejected** because it trusted a user-supplied Issue #48 comment URL without authenticating the owner/scope/source-SHA, and used path-based ACL/file reads vulnerable to TOCTOU. The previous owner grant 6196160426 is spent.
- R2 removes the unsafe live provider entirely. The pure authorization hook denies *every* reference, including genuine-looking and forged URLs. The exported -Live route returns BLOCKED_WITH_EVIDENCE before constructing any C: provider, and a future change to the authorization hook alone cannot enable it. A second stable-identity gate also denies. No C: read-only attestation is possible with this R2.
- **TOCTOU disposition:** The path-based live access was deleted, so it cannot attest stale, replaced or mismatched objects. Handle-based no-follow object identity (including parent directories, held ACL/content handles and stable inventories) is **not implemented**. It remains a mandatory future independent design/qualification gate; do not claim a live race-free success now.
- **R1 SHA discrepancy independently resolved:** R1 Git/LF SHA-256 values `2e43c03c79409c510d7a5c6457bc0299744b835c15d02e44fb7b82ab695427d5` (module), `c2bae816034cc2f6295f746509d45e1b9c2c71281f8d426877c77c30553f2d3b` (wrapper), `82d53b4117a31c1004ba9262147989ff5971fc9f88c43b9747a3dd6ef56aae3d` (test) match original author; CRLF hashes `f0c4d787ba70277ff2f72e3862aa5105931061608a705b905a5adc162b09e844`, `9f0c3d50db089eaeb45ba1156c44871ad5a285fc63e58e08de6e4a44284f5a7e`, `556f826cb88501304ca81d6a6451a2c5b54601d6626743d0e756033089dc2701` match independent reviewer exactly. The handoff LF SHA `cd3414b8200745b7a3be9a3a9d785b7fb3250b49978f002cb524a603c844fe71` matches. Exact LF checkout is explicitly pinned for the three PowerShell files in R2 `.gitattributes`.
- R2 synthetic tests retain the prior 19 assertions, add denial of four untrusted authorization references **without running live mode**, deny direct construction of the live provider, and simulate object replacement in a disposable TEMP fixture. Passing fixture tests cannot qualify future live handles.
- No installed-package trust root, owner-authentication service, cryptographic signing key, remote API access or Windows handle-based identity is implemented or implied. No protected Windows objects were accessed by this change. A fresh exact-SHA reviewed live architecture and owner authorization remain necessary.
- Keep `CURRENT_PROTECTED_STATE_UNKNOWN / V3_NOT_ATTESTED / ACL_REVIEW_REQUIRED / G1_BLOCKED_ENVIRONMENT / F2_G1_RELEASE_HOLD`. No UAC, protected updater, `icacls`, VM, native test, merge or release is authorized.
