# Developer handoff: F2 G1 C: postfailure inspector

Status: READY_FOR_INDEPENDENT_REVIEW

Ticket / acceptance criteria: Prepare a bounded Windows PowerShell 5.1 source-only inspector and inert synthetic suite; do not perform the protected C: attestation. Preserve `CURRENT_PROTECTED_STATE_UNKNOWN`, `V3_NOT_ATTESTED`, `ACL_REVIEW_REQUIRED`, `G1_BLOCKED_ENVIRONMENT`, and `F2_G1_RELEASE_HOLD`.

Repository / remote: `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`

Worktree / branch: `C:\Dev\f2-g1-c-postfailure-inspector-r1` / `fix/f2-g1-c-postfailure-inspector-r1`

Base SHA: `33e985b8e7807bf1feda935374889efd5e5f158a` (accepted PR #50 PowerShell 5.1 entrypoint bridge)

Candidate source SHA: `6008e453ad2be152ef6fc4306f9b609c39d30474` (inspector/test implementation commit; no source files changed afterward)

Parent SHA: `33e985b8e7807bf1feda935374889efd5e5f158a`

Changed paths:

- `scripts/f2-acl/F2G1CPostfailureAttestation.psm1`
- `scripts/f2-acl/Invoke-F2G1CPostfailureAttestation.ps1`
- `scripts/f2-acl/Test-F2G1CPostfailureAttestation.SourceOnly.ps1`
- `docs/handoffs/F2_G1_C_POSTFAILURE_INSPECTOR.md`

Implementation summary: Adds an exact path allowlist for the reviewed C: system parents, F2 package directories/files, active manifest, seven-file baseline mailbox, and enumerated immediate transaction-artifact names. The live provider uses bounded read-only file reads, path/ancestor reparse checks, ACL metadata reads and immediate-child enumeration only. It rejects administrator tokens, requires a new Issue #48 comment reference in live mode, and rejects the spent comment `6196160426`. The wrapper has no default execution mode and only imports the new inspector module. The test creates a single disposable fixture document under a guarded direct TEMP child and removes only that guarded fixture directory.

Architectural impact: None to production. Historical V2 preservation evidence is inspected only as data. No installed script/module is imported or executed; no external authority, cryptographic signature, durable storage, or effective token authorization is provided. The report cannot establish `PASS_RESTRICTIVE_ACL`, V3 readiness, or production readiness.

Dependencies added / licenses: None.

Tests executed (exact commands):

- Windows PowerShell 5.1 parser-only process, started by `ProcessStartInfo` with `UseShellExecute=false`, redirected stdout/stderr, bounded 15-second startup, exit capture and disposal. Parsed module, wrapper, and test source before execution.
- Windows PowerShell 5.1 inert suite: `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2G1CPostfailureAttestation.SourceOnly.ps1`, run as a child with redirected streams and a 30-second bound.
- `git diff --check`

Results / assertion counts: parser-only process exited 0 with `PARSE_ERRORS=0` for all three candidate PowerShell files. Synthetic suite exited 0 with `ASSERTIONS=18 FAILURES=0`; stdout and stderr were drained, no timeout occurred, and the fixture cleanup completed. `git diff --check` passed after staging.

Tests not executed: No live C: inspection; no C:, G:, Hyper-V, VM, UAC, `icacls`, updater, installation, ACL mutation, CI, or release operation.

Failure/recovery cases: Synthetic cases cover simulated access denial, missing required object, unexpected immediate artifact, malformed active manifest, package hash mismatch, incomplete 11-object baseline, administrator token, and reparse object. All failures return a closed blocked verdict.

Benchmark machine and metrics: Not applicable.

Known limitations: A future owner must separately authorize a fresh, exact-SHA, exact-scope read-only C: inspection after independent source acceptance; the prior authorization is spent. The live inspector only checks that a supplied reference has Issue #48 comment URL shape and is not the spent ID; a human must independently verify the new comment's author, scope, and latest restrictions. It does not read repository metadata or prove the running inspector's Git identity. ACL ACE checks are not effective-token analysis. No production behavior or protected state was observed.

Visual reproduction steps: Not applicable.

Rollback instructions: Delete the isolated local topic worktree/branch only after review evidence has been retained; no shared branch or remote was changed.

Reviewer focus / open questions: Verify the live allowlist against current Issue #48 restrictions, baseline evidence format and historical pins; inspect fail-closed path handling and synthetic coverage. In particular, confirm the report's ACL metadata remains sanitized and is not mistaken for effective-token acceptance.
