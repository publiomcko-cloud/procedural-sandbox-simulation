# Developer handoff — F2 G1 `icacls` corroboration helper

Status: READY_FOR_INDEPENDENT_REVIEW
Ticket / acceptance criteria: Issue #48, finding `6101582852`; implement and source-validate the separate read-only `icacls` corroboration helper. No live collection is authorized.
Repository / remote: `publiomcko-cloud/procedural-sandbox-simulation`
Worktree / branch: `C:\Dev\f2-g1-icacls-corroboration` / `security/f2-icacls-corroboration-issue48`
Base SHA: `a62773f0553dff4a05055b18fa10834f7488ae55`
Candidate SHA: fill after commit
Parent SHA: `a62773f0553dff4a05055b18fa10834f7488ae55`
Changed paths: `.gitattributes`; `.github/workflows/f2-acl-source-only.yml`; `docs/handoffs/F2_G1_ICACLS_CORROBORATION_HANDOFF.md`; `scripts/f2-acl/F2AclIcacls.Corroboration.psm1`; `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json`; `scripts/f2-acl/Test-F2AclIcacls.Corroboration.ps1`.

## Implementation summary

Corrected the helper’s file-hash call to pass a canonical path with `Get-FileHash -LiteralPath ... -Algorithm SHA256`. The baseline reader loads `ProjectVolumeGuid` only from `integrity.json`, verifies the exact baseline payload byte length and SHA-256, and carries `EvidenceVolumeGuid` as a separate identity. Preflight rejects source/commit mismatches, changed VM identity/state/NICs, non-unique Kingston serial/model/USB/health/mapping, wrong volume GUIDs, incomplete or aliased 11-path sets, reparse ancestry, and unverified evidence storage.

The command builder emits only the system `icacls.exe` path and one quoted member of the exact 11-object allowlist, without ACL-changing or recursive switches. Its bounded process wrapper records actual PID/exit, separate stdout/stderr and hashes; timeout, incomplete drain, cleanup failure, output overflow, or unknown parse tokens never become PASS. The runner continues draining after its retained output cap, while retaining only the bounded prefix. The plan permits no elevation unless the complete standard result is explicit Access Denied, then calls the coordinator at most once for only denied targets.

Evidence publication checks the protected directory owner/DACL and non-reparse ancestry, verifies the project and evidence volume GUIDs independently, uses create-new files, and writes a hashed integrity manifest. Failed child outcomes remain diagnostic evidence with `AllCommandsSuccessful=false` and are not classified as PASS.

## Architectural impact

No changes to ACLs, Hyper-V, VM state, storage, networking, WSL, Docker or the baseline evidence. No cross-integrity IPC or UAC launcher was added; the future coordinator remains an injected boundary whose invocation count is constrained by the plan. PR #49 and its source branch are unchanged.

## Dependencies added / licenses

None. Uses Windows PowerShell/.NET Framework APIs and the existing F2 ACL protocol module.

## Tests executed (exact commands)

Commands, executed using Windows PowerShell 5.1:

- `& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclIcacls.Corroboration.ps1`
- `& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclCapture.Protocol.ps1`
- Parser sweep using `[Management.Automation.Language.Parser]::ParseFile` for all tracked `scripts/f2-acl/*.ps1` and `*.psm1` files.
- `git diff --check origin/security/f2-acl-capture-issue48...HEAD`

Results: corroboration suite 46 assertions / 0 failures; existing ACL protocol suite 152 assertions / 0 failures; 5 PowerShell files parsed / 0 parser errors; `git diff --check` exit 0. Tests use synthetic ACL text, fixture JSON, temporary protected directories and inert PowerShell child processes. They do not execute `icacls.exe`.

## Tests not executed

No live `icacls`, VM ACL/token queries, UAC elevation, ACL remediation, VM operation, G: writes, guest/native workload, Godot or Voxel Tools execution.

## Failure/recovery cases

Synthetic coverage includes missing/malformed payload fields, baseline tampering, source-pin/commit mismatch, wrong GUID source/value, wrong Kingston model, ambiguous serial, altered identity/mapping, unexpected NIC, incomplete/aliased/reparse paths, unknown rights, mismatch, standard success/failure, Access Denied-only retry, exactly one coordinator launch, timeout, oversized output, child status, stream/event cleanup, evidence directory protection, create-new output hashes and failed diagnostic publication. Failure leaves the result non-PASS/INDETERMINATE.

## Benchmark machine and metrics

Not applicable; this is an evidence helper, not a performance change.

## Known limitations

- The source contains no live observations and does not establish ACL acceptance. Future actual UAC/elevated corroboration requires fresh owner authorization after independent review.
- Rights and principal spellings that `icacls` cannot conservatively map are `INDETERMINATE`; no generic-rights expansion or effective-access claim is inferred.
- The .NET line-oriented event reader bounds retained stream data, but a single unusually long output line is materialized by the framework before the handler enforces the cap.
- The injected coordinator transport and credentialed UAC behavior are not exercised. Synthetic callbacks prove the at-most-one launch policy only.

## Visual reproduction steps

Not applicable.

## Rollback instructions

Close the draft PR and delete only this isolated topic branch/worktree after confirming no user changes. The immutable baseline and failed diagnostic evidence are not part of the changed paths and remain untouched.

## Reviewer focus / open questions

Review PowerShell 5.1 binding and event cleanup; exact volume identity sourcing; strict 11-object command allowlist; output/drain deadlines; fail-closed parse/comparison outcomes; evidence ACL and create-new publication; and the boundary between Access Denied and other failures. The next live `icacls` pass remains unauthorized.
