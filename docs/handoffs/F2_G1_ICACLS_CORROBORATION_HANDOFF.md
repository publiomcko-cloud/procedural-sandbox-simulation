# Developer handoff — F2 G1 `icacls` corroboration helper

Status: READY_FOR_INDEPENDENT_SOURCE_REVIEW
Ticket / acceptance criteria: Issue #48, findings `6101582852` and `6101813008`; correct and source-validate the separate read-only `icacls` corroboration helper. No live collection is authorized.
Repository / remote: `publiomcko-cloud/procedural-sandbox-simulation`
Worktree / branch: `C:\Dev\f2-g1-icacls-corroboration` / `security/f2-icacls-corroboration-issue48`
Base SHA: `a62773f0553dff4a05055b18fa10834f7488ae55`
Candidate SHA: `0174b277ba5cff36c3ea9cf8bd8402ab6a2ea8dc` (source implementation snapshot)
Parent SHA: `d28c1235c1ee7f186dd1e46f3a5da1752a98b561`
Changed paths: `docs/handoffs/F2_G1_ICACLS_CORROBORATION_HANDOFF.md`; `scripts/f2-acl/F2AclIcacls.Corroboration.psm1`; `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json`; `scripts/f2-acl/Test-F2AclIcacls.Corroboration.ps1`.

## Implementation summary

Corrected the helper’s file-hash call to pass a canonical path with `Get-FileHash -LiteralPath ... -Algorithm SHA256`. The baseline reader loads `ProjectVolumeGuid` only from `integrity.json`, verifies the exact baseline payload byte length and SHA-256, and carries `EvidenceVolumeGuid` as a separate identity. It now validates the exact capture-ID-derived mailbox path through the existing PR #49 coordinator-mailbox contract: protected DACL, Administrators owner, exactly four ACEs, SYSTEM and Administrators full control, and OWNER RIGHTS/requester read-execute grants. It does not apply the unrelated three-ACE requester-owned output-directory contract to the original mailbox. Preflight rejects source/commit mismatches, changed VM identity/state/NICs, non-unique Kingston serial/model/USB/health/mapping, wrong volume GUIDs, incomplete or aliased 11-path sets, reparse ancestry, and unverified evidence storage.

The command builder emits only the system `icacls.exe` path and one quoted member of the exact 11-object allowlist, without ACL-changing or recursive switches. Its process wrapper uses asynchronous fixed-size 4096-character reads from stdout/stderr rather than line events, retains a bounded UTF-8 representation, enforces one monotonic deadline across child exit and stream EOF, and records PID, actual exit, observed byte counts, decoded-text SHA-256 and cleanup state. A long single line cannot trigger a proportional allocation. Timeout, incomplete drain, cleanup failure, output overflow, or unknown parse tokens never become PASS. The plan permits no elevation unless the complete standard result is explicit Access Denied, then calls the coordinator at most once for only denied targets.

The parser requires the first non-empty output line to begin with the exact expected canonical target path, consumes the first ACE when it follows that path on the same line, and rejects wrong paths, prefix collisions, malformed entries and unexpected trailers. It maps Microsoft-documented simple and detailed codes, including `RA`, `REA`, `RD`, `S`, `GR`, `GW`, `GE`, `GA`, comma-separated specific rights, deny entries and inheritance flags. Generic masks are retained as unsigned 32-bit values and normalized using Windows file generic mappings for comparison; equal normalized file rights can PASS, ambiguous generic/residual masks stay INDETERMINATE, and only fully understood unequal ACE sets become MISMATCH. The tests use synthetic profiles and contain no protected capture SDDL or VM-specific SIDs.

Evidence publication checks the protected directory owner/DACL and non-reparse ancestry, verifies the project and evidence volume GUIDs independently, uses create-new files, and writes a hashed integrity manifest. Failed child outcomes remain diagnostic evidence with `AllCommandsSuccessful=false` and are not classified as PASS.

## Architectural impact

No changes to ACLs, Hyper-V, VM state, storage, networking, WSL, Docker or the baseline evidence. No cross-integrity IPC or UAC launcher was added. **Separate execution-readiness gate:** this module has no production standard-token UAC launcher or authenticated elevated coordinator transport. The coordinator is only an injected interface for synthetic call-count tests; this PR does not authorize or provide an executable privilege boundary, and the helper is not ready for elevated/live execution until that boundary is separately architected, reviewed and validated. PR #49 and its source branch are unchanged.

## Dependencies added / licenses

None. Uses Windows PowerShell/.NET Framework APIs and the existing F2 ACL protocol module.

## Tests executed (exact commands)

Commands, executed using Windows PowerShell 5.1:

- `& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclIcacls.Corroboration.ps1`
- `& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclCapture.Protocol.ps1`
- Parser sweep using `[Management.Automation.Language.Parser]::ParseFile` for all tracked `scripts/f2-acl/*.ps1` and `*.psm1` files.
- `git diff --check origin/security/f2-acl-capture-issue48...HEAD`

Results on source SHA `0174b277ba5cff36c3ea9cf8bd8402ab6a2ea8dc`: corroboration suite 110 assertions / 0 failures; existing ACL protocol suite 152 assertions / 0 failures; 5 PowerShell files parsed / 0 parser errors; `git diff --check a62773f0553dff4a05055b18fa10834f7488ae55...HEAD` exit 0. Corroboration module SHA-256 is `a0e53c02996a23b8648528b172302e6273891bbe0c0f85672b4e87c40f7261e8`, matching `F2_ICACLS_SOURCE_PINS.json`; collector and protocol pins remain `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b` and `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728`. Tests use synthetic ACL text, a synthetic four-ACE mailbox descriptor, fixture JSON, temporary test directories and inert PowerShell child processes. They do not execute `icacls.exe`.

## Tests not executed

No live `icacls`, VM ACL/token queries, UAC elevation, ACL remediation, VM operation, G: writes, guest/native workload, Godot or Voxel Tools execution.

## Failure/recovery cases

Synthetic coverage includes missing/malformed payload fields, baseline tampering, source-pin/commit mismatch, wrong GUID source/value, wrong Kingston model, ambiguous serial, altered identity/mapping, unexpected NIC, incomplete/aliased/reparse paths, unknown rights, mismatch, standard success/failure, Access Denied-only retry, exactly one coordinator launch, timeout, oversized output, child status, stream/event cleanup, evidence directory protection, create-new output hashes and failed diagnostic publication. Failure leaves the result non-PASS/INDETERMINATE.

## Benchmark machine and metrics

Not applicable; this is an evidence helper, not a performance change.

## Known limitations

- The source contains no live observations and does not establish ACL acceptance. Future actual UAC/elevated corroboration requires fresh owner authorization after independent review.
- Rights/principals without an unambiguous supported mapping, or generic masks with unresolved residual bits, remain `INDETERMINATE`; the helper does not claim effective access.
- Stream hashes describe UTF-8 re-encoded decoded text, not byte-for-byte OEM/native stdout. Output collection has fixed-size reads and a bounded retained text prefix; overflowing output is drained only within the deadline and cannot be complete.
- The injected coordinator transport and credentialed UAC behavior are not exercised. Synthetic callbacks prove the at-most-one launch policy only. This remains a separate execution-readiness blocker.

## Visual reproduction steps

Not applicable.

## Rollback instructions

Close the draft PR and delete only this isolated topic branch/worktree after confirming no user changes. The immutable baseline and failed diagnostic evidence are not part of the changed paths and remain untouched.

## Reviewer focus / open questions

Review PowerShell 5.1 binding and event cleanup; exact volume identity sourcing; strict 11-object command allowlist; output/drain deadlines; fail-closed parse/comparison outcomes; evidence ACL and create-new publication; and the boundary between Access Denied and other failures. The next live `icacls` pass remains unauthorized.
