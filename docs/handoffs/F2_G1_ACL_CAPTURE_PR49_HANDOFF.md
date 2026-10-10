# F2 G1 ACL capture UAC handoff

**Status: READY_FOR_INDEPENDENT_REVIEW** — source-only mailbox-parent ACL correction for PR #49. No elevation or live ACL collection occurred.

## Ticket / acceptance criteria

GitHub Issue #48 and PR #49: produce a bounded read-only ACL collector that reports complete evidence and actual process statuses across the standard-user to Administrator UAC boundary, including credentialed alternate Administrator accounts. Preserve exact source pins, Kingston and VM gates, the 11-object scope, result integrity, output limits, and restricted evidence storage outside G:.

## Repository and Git

- Repository / remote: `publiomcko-cloud/procedural-sandbox-simulation` / `origin`.
- Worktree: `C:\Dev\f2-g1-acl-resolution`.
- Branch: `security/f2-acl-capture-issue48`.
- Reviewed start SHA for this correction: `a763174954a92ec355b0ad034dd94f23dadbdd1c`.
- Candidate SHA: this handoff is committed with the source correction; use the commit containing this file as the immutable candidate HEAD. Its parent is reported in the delivery message.
- Draft PR: #49. No merge or history rewrite is part of this work.

## Changed paths

- `scripts/f2-acl/Invoke-F2AclReadOnlyCapture.ps1` — replace cross-token named-pipe transport with a restricted mailbox; use an elevated coordinator and same-token worker; bind worker and coordinator exits, status schema, pins, and evidence hashes; preserve bounded reads/writes and report incomplete states.
- `scripts/f2-acl/F2AclCapture.Protocol.psm1` — parent ACL rights classification, protected ancestor chain validation, and unchanged source-pinned capture protocol.
- `scripts/f2-acl/Test-F2AclCapture.Protocol.ps1` — exact ProgramData SDDL and parent attack regressions, mailbox collision/tamper/reparse checks, and existing protocol suite.
- `scripts/f2-acl/F2_ACL_SOURCE_PINS.json` — updated module SHA-256 pin; launcher source is unchanged.
- `docs/security/F2_G1_ACL_CAPTURE.md` — parent ACL semantics, accepted mask, Microsoft references, and explicit test limitations.
- `docs/handoffs/F2_G1_ACL_CAPTURE_PR49_HANDOFF.md` — this handoff.

## Implementation summary

The standard-token parent generates a random mailbox identifier and launches one UAC coordinator. The coordinator verifies its actual Administrator role and accepts the requester's SID or a distinct credentialed Administrator SID. It validates the full no-reparse ancestor chain, trusted owners, and parent DACLs. The revised policy accepts the observed BUILTIN Users `0x116` mask as parent create/metadata rights while rejecting untrusted `DELETE_CHILD`, `DELETE`, `WRITE_DAC`, `WRITE_OWNER`, GENERIC_WRITE and GENERIC_ALL. It requires the CommonApplicationData parent DACL to be protected. The unique mailbox is created atomically with the exact protected DACL; the Administrators group owns it, and the requester receives read/traverse only. A precreated name fails closed and is never adopted or overwritten. The inheritable OWNER RIGHTS read/traverse ACE suppresses implicit WRITE_DAC if the requesting SID is also the owner of same-account elevated output files. It runs the collector worker without another elevation, so both use the same token. Bounded, create-new payload and stream files, status-last publication, actual coordinator/worker exit checks, source pins, integrity checks and the exact 11-object scope are unchanged. Production contains no named-pipe IPC. The coordinator can stop its own same-token worker; the standard-token parent does not try to terminate an elevated coordinator.

The prior `PipeOptions.CurrentUserOnly` design was removed. The separate PowerShell 5.1 compatibility issue was also addressed: Windows PowerShell 5.1 does not expose that enum member.

## Tests executed

- Windows PowerShell 5.1: `scripts/f2-acl/Test-F2AclCapture.Protocol.ps1` — **119 assertions, 0 failures**, process exit 0.
- Windows PowerShell 5.1 parser sweep: **3 tracked PowerShell files parsed, 0 errors**.
- `git diff --check` — exit 0.
- GitHub Windows CI — run for this revision; final status is reported with the immutable commit.

## Validation limits and risks

- Different-SID Administrator authorization is covered by synthetic policy fixtures only. No distinct Windows logon token, credentialed UAC prompt, or actual cross-account filesystem access was exercised. Parent rights are conservatively evaluated from raw DACL ACE masks; tests do not create standard-user/elevated tokens or call token-based Windows effective-access APIs. Dangerous untrusted allow ACEs are rejected whether or not a given requester token would activate them.
- No live VM, ACL, registry, disk, Hyper-V setting, or G: file was inspected or changed. No UAC elevation was requested.
- If the coordinator cannot create or publish the mailbox/status file, the parent still records its real process exit and fails closed. A protected CommonApplicationData parent with the reviewed BUILTIN Users `0x116` create/metadata mask is accepted; dangerous delete/replacement/DACL/owner rights block collection. There is no weaker-storage fallback.
- A privileged local Administrator remains trusted because the evidence directory grants BUILTIN\\Administrators Full Control. Hashes detect corruption and mismatch; they are not protection against a malicious administrator who can rewrite both evidence and integrity files.
- Actual UAC integration and one new bounded read-only capture remain unrun. The correction does not re-read live parent/ancestor ACLs, VM ACLs, G:, registry, or Hyper-V state; the future elevated collector rechecks its live gates before collection.

## Visual test steps

Not applicable. This is a source-only host PowerShell utility; elevation/live collection was expressly outside this task.

## Rollback

Revert the PR #49 source-correction commit(s) as ordinary commits. Do not reset or force-push. No host or VM state was changed.

## Reviewer focus

- Confirm the coordinator status schema exactly matches the parent validator and actual process exit checks.
- Confirm alternate credentials are accepted only when the elevated token is an Administrator and the requester SID, source pins, and evidence directory checks remain bound.
- Confirm production has no cross-token named pipe and mailbox files remain bounded, create-new, integrity-checked, and protected by the exact evidence DACL.
- Confirm failure and timeout results cannot be reported as complete.
