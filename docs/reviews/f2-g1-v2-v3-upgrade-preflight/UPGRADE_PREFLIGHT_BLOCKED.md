# F2 G1 v2-to-v3 protected-upgrade preflight — blocked before UAC

Status: **BLOCKED_WITH_EVIDENCE**
Date: 2026-10-12
Owner authorization: Issue #48 comment 6129100523
Independent source approval: PR #59 review 5493936404

## Approved immutable inputs

- PR #59 review HEAD: 9e9915e6eb15bcb20cc2f5a1c990791e2a822b90
- Production SourceRoot HEAD: 8b70a70934445bee660c1e53e71b2e7b20a6191f
- Candidate v3 manifest SHA-256: 74d178917fba4f50fdca40505d8c1dc81639f3c60bbb25c0332fd737c681562c
- Updater CRLF SHA-256: d26eb89a424e3f268099e0ac1d3ffd674dde1128321567df3a0702abb591f75e
- Launcher CRLF SHA-256: 8278bbff8e5b7cdb313235bcc271fa31a947ca384d7496053650c3097af19720
- Candidate source-pin manifest SHA-256: 7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce

The review worktree was clean at the exact PR #59 HEAD. The production SourceRoot was clean at its pinned commit and expected origin. Candidate manifest schema, source commit, versioned PackageRoot, baseline identity pins, and raw manifest digest matched the approved values. All seven production package files matched the candidate pins. The exact approved command remains available in [PR #59's updater review](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/blob/9e9915e6eb15bcb20cc2f5a1c990791e2a822b90/docs/reviews/f2-g1-protected-release-updater/F2_G1_PROTECTED_RELEASE_UPDATER_REVIEW.md#exact-proposed-command--not-executed).

## Read-only preflight results

| Gate | Result | Sanitized evidence |
|---|---|---|
| Reviewed PR and production commits/remotes/clean worktrees | PASS | Exact pinned commits; both worktrees clean; expected repository origin |
| Candidate v3 manifest and source pins | PASS | Candidate SHA, v3 schema, commit and PackageRoot matched |
| Seven production source package hashes | PASS | 7/7 match |
| Requester token | PASS | Standard, non-administrator account; identity value withheld |
| Existing v2 active manifest | PASS | SHA-256 b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9; v2 schema and old production commit |
| Retained baseline identities | PASS | Mailbox ecb6deeb424e40feb5354d18908986df; payload CaptureId 489e7fec-0300-467c-bfbd-a46fb8cf7211; payload/integrity hashes match approved pins |
| Existing v2 package files | PASS | 7/7 hashes match the old release pins; per-file values are listed below |
| Existing protected installation ACLs | PASS | 4 directories, 7 package files and 1 manifest: Administrators owner, protected DACL and reviewed exact three-ACE profile |
| Canonical paths and reparse checks | PASS | 12 installed objects and their path chains checked; no reparse points or aliases observed |
| C: parent ACL policy | PASS | C: root, Program Files and ProgramData passed the reviewed safe-parent policy |
| Existing tree and transaction collisions | PASS | Exact existing child sets; versioned v3 destination, release lock, updates and backups paths absent |
| Process topology for approved launch | **BLOCKED** | A pre-existing Windows Terminal PowerShell host remained active. Starting the pinned requester and UAC child would violate the updater's exact two-PowerShell allowlist. No ancestor exception is permitted. The required Explorer Win+R launch cannot be established by this automation. |

Read-only checks ran under PowerShell 7.6.6. No protected write, UAC, updater invocation, process termination, recovery, cleanup, icacls, VM/Hyper-V/G: operation or native workload occurred.

## Verified active v2 file hashes

| Installed file | SHA-256 |
|---|---|
| F2AclCapture.Protocol.psm1 | 42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728 |
| F2AclIcacls.Corroboration.psm1 | a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b |
| F2AclIcacls.Runtime.psm1 | 950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5 |
| Invoke-F2IcaclsCapture.ps1 | fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0 |
| Invoke-F2IcaclsProtectedCoordinator.ps1 | 3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2 |
| F2_ICACLS_SOURCE_PINS.json | bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7 |
| Invoke-F2AclReadOnlyCapture.ps1 | bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b |

## Execution and transaction resul

- UAC attempts: **0**; the one-time authorization was **not consumed**.
- Approved requester launcher / elevated child: not launched.
- Child PID, exit code, transaction ID and diagnostic stage: not applicable; no child or transaction was created.
- Timeout / cancellation: none; launch was blocked before UAC.
- Postflight attestation: not run because no update occurred.
- Active state at preflight: approved v2 manifest and files remain active. No update, backup, lock, journal, staging or release objects were created by this attempt.

## Required next action

The existing Windows Terminal PowerShell session must be exited normally. Once all PowerShell hosts have exited and this Codex command host is no longer running, the exact approved command must be started from a fresh CMD opened directly through Explorer's Win+R dialog. Do not launch it from a PowerShell-backed terminal. The approved updater will then recheck process quiescence and all safety gates before it can request UAC. The owner authorization remains unused; this report does not authorize any retry, recovery, or alternate launch path.

## Privacy

This package contains hashes and sanitized gate results. It omits requester SIDs, raw SDDL, credentials and raw host security descriptors.
