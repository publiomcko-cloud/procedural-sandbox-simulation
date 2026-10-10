# F2 G1 ACL capture UAC handoff

**Status: READY_FOR_INDEPENDENT_REVIEW** — source-only UAC/file-mailbox correction for PR #49. No elevation or live ACL collection occurred.

## Ticket / acceptance criteria

GitHub Issue #48 and PR #49: produce a bounded read-only ACL collector that reports complete evidence and actual process statuses across the standard-user to Administrator UAC boundary, including credentialed alternate Administrator accounts. Preserve exact source pins, Kingston and VM gates, the 11-object scope, result integrity, output limits, and restricted evidence storage outside G:.

## Repository and Git

- Repository / remote: `publiomcko-cloud/procedural-sandbox-simulation` / `origin`.
- Worktree: `C:\Dev\f2-g1-acl-resolution`.
- Branch: `security/f2-acl-capture-issue48`.
- Reviewed start SHA: `60b39fc4da2d1f75e92e56d599e436668bf0e89d`.
- Candidate SHA: this handoff is committed with the source correction; use the commit containing this file as the immutable candidate HEAD. Its parent is reported in the delivery message.
- Draft PR: #49. No merge or history rewrite is part of this work.

## Changed paths

- `scripts/f2-acl/Invoke-F2AclReadOnlyCapture.ps1` — replace cross-token named-pipe transport with a restricted mailbox; use an elevated coordinator and same-token worker; bind worker and coordinator exits, status schema, pins, and evidence hashes; preserve bounded reads/writes and report incomplete states.
- `scripts/f2-acl/F2AclCapture.Protocol.psm1` — identity-pair/status validation, administrator-owned read-only requester mailbox DACL, and atomic bounded file helpers.
- `scripts/f2-acl/Test-F2AclCapture.Protocol.ps1` — Windows PowerShell 5.1 tests for production topology, status contract, synthetic same/different Administrator identities, requester tamper/delete ACL rejection, file mailbox integration, and process failures.
- `scripts/f2-acl/F2_ACL_SOURCE_PINS.json` — refreshed exact SHA-256 pins for launcher and protocol module.
- `docs/security/F2_G1_ACL_CAPTURE.md` — UAC/file-mailbox protocol, simulation limits, and updated capture instructions.
- `docs/handoffs/F2_G1_ACL_CAPTURE_PR49_HANDOFF.md` — this handoff.

## Implementation summary

The standard-token parent generates a random mailbox identifier and launches one UAC coordinator. The coordinator verifies its actual Administrator role and accepts the requester's SID or a distinct credentialed Administrator SID. It creates a protected mailbox below CommonApplicationData only after validating the protected parent, owner, ACL, volume and no-reparse chain; the Administrators group owns it, and the requester receives read/traverse only. An inheritable OWNER RIGHTS read/traverse ACE suppresses implicit WRITE_DAC if the requesting SID is also the owner of same-account elevated output files. It runs the collector worker without another elevation, so both use the same token. The worker writes bounded, create-new framed payload and stream files; the coordinator validates them and atomically writes a status document last. The parent waits on the coordinator process handle, records its actual exit code, verifies the mailbox ACL, validates the coordinator status against that exit, and independently revalidates the final evidence and source pins. Production contains no named-pipe IPC. The coordinator can stop its own same-token worker; the standard-token parent does not try to terminate an elevated coordinator.

The prior `PipeOptions.CurrentUserOnly` design was removed. The separate PowerShell 5.1 compatibility issue was also addressed: Windows PowerShell 5.1 does not expose that enum member.

## Tests executed

- Windows PowerShell 5.1: `scripts/f2-acl/Test-F2AclCapture.Protocol.ps1` — **103 assertions, 0 failures**, process exit 0.
- Windows PowerShell 5.1 parser sweep: all tracked `scripts/f2-acl/*.ps1` and `*.psm1` files — results recorded in the delivery message.
- `git diff --check` — results recorded in the delivery message.
- GitHub Windows CI — results recorded in the delivery message.

## Validation limits and risks

- Different-SID Administrator authorization is covered by synthetic policy fixtures only. No distinct Windows logon token, credentialed UAC prompt, or actual cross-account filesystem access was exercised. Requester write/delete/WRITE_DAC refusal is checked by synthetic DACL fixtures; no distinct requester access token is created in tests.
- No live VM, ACL, registry, disk, Hyper-V setting, or G: file was inspected or changed. No UAC elevation was requested.
- If the coordinator cannot create or publish the mailbox/status file, the parent still records its real process exit and fails closed. Unsafe CommonApplicationData parent permissions block collection; there is no weaker-storage fallback.
- A privileged local Administrator remains trusted because the evidence directory grants BUILTIN\\Administrators Full Control. Hashes detect corruption and mismatch; they are not protection against a malicious administrator who can rewrite both evidence and integrity files.
- Actual UAC integration and one authorized read-only capture remain unrun. The tool is ready for independent review before any fresh owner authorization.

## Visual test steps

Not applicable. This is a source-only host PowerShell utility; elevation/live collection was expressly outside this task.

## Rollback

Revert the PR #49 source-correction commit(s) as ordinary commits. Do not reset or force-push. No host or VM state was changed.

## Reviewer focus

- Confirm the coordinator status schema exactly matches the parent validator and actual process exit checks.
- Confirm alternate credentials are accepted only when the elevated token is an Administrator and the requester SID, source pins, and evidence directory checks remain bound.
- Confirm production has no cross-token named pipe and mailbox files remain bounded, create-new, integrity-checked, and protected by the exact evidence DACL.
- Confirm failure and timeout results cannot be reported as complete.
