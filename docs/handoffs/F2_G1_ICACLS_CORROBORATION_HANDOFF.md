# Developer handoff — F2 G1 accelerated `icacls` workflow

Status: READY_FOR_INDEPENDENT_REVIEW
Ticket / acceptance criteria: Issue #48 accelerated source-only implementation under owner approval `6102054991`; PR #50 remains draft.
Repository / remote: `publiomcko-cloud/procedural-sandbox-simulation` / `origin`
Worktree / branch: `C:\Dev\f2-g1-icacls-corroboration` / `security/f2-icacls-corroboration-issue48`
Base SHA: `58af4a8d8f83a184348082bf12fee7b1cef18779`
Candidate SHA: The immutable candidate is the final PR #50 head reported with this handoff; a commit cannot contain its own hash.
Parent SHA: `e4efd7a38bb73effb6488c542d530fbdbbe7d2f9`
Changed paths:
- `.gitattributes`
- `.github/workflows/f2-acl-source-only.yml`
- `docs/architecture/F2_G1_ICACLS_EXECUTION_BOUNDARY.md`
- `docs/handoffs/F2_G1_ICACLS_CORROBORATION_HANDOFF.md`
- `scripts/f2-acl/F2AclIcacls.Corroboration.psm1`
- `scripts/f2-acl/F2AclIcacls.Runtime.psm1`
- `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json`
- `scripts/f2-acl/Invoke-F2IcaclsCapture.ps1`
- `scripts/f2-acl/Invoke-F2IcaclsProtectedCoordinator.ps1`
- `scripts/f2-acl/Test-F2AclIcacls.Corroboration.ps1`
- `scripts/f2-acl/Test-F2AclIcacls.Runtime.ps1`

## Implementation summary

Added a closed, no-argument standard-token launcher and a fixed-path protected coordinator. The launcher validates the external ProgramData release manifest, the exact reviewed commit and source package pins, retained baseline identity/digests, then creates a bounded one-use request and can issue at most one `Start-Process -Verb RunAs`. Cancellation is returned as a terminal result; there is no retry path. The elevated coordinator accepts only the validated capture GUID and obtains identity/requester pairing and a protected four-ACE evidence mailbox through the existing PR #49 protocol.

The elevated coordinator performs a fresh Hyper-V/storage/path preflight before its first ACL read. It requires the exact VM ID and name in OFF state, zero NICs, a unique Kingston serial with the reviewed model identity, USB/healthy/online state and G: NTFS volume mapping, exact expected canonical object set and file/directory types, no aliases/reparse ancestry, and matching baseline/source pins. It then runs exactly eleven individually bounded system `icacls.exe` invocations, with no recursive or modifying switches, followed by an equivalent postflight. It reuses PR #50's fixed-chunk process capture, parser, comparator and create-new evidence publication. The result reader verifies identity, the exact 11-path set, per-object records, byte counts, stream hashes, source/baseline pins and the package integrity hash before returning sanitized comparisons.

The externally anchored release manifest is intentionally outside the mutable checkout. Its expected installed location is `C:\ProgramData\F2-G1-Icacls\approved-release.json`; package files are expected under `C:\Program Files\F2-G1-Icacls\scripts\f2-acl`. The manifest pins the final commit, baseline capture and payload/integrity digests, pin-manifest digest and exact executable file set/hashes. Both package and manifest locations are checked for exact protected owner/DACL profiles before coordinator execution. The source pin values are in `scripts/f2-acl/F2_ICACLS_SOURCE_PINS.json`; the final commit and per-file values are included in the release manifest only after independent review.

## Architectural impact

Source-only. No protected directory was created and no package installed. No actual UAC, `icacls`, live VM/SSD/ACL/token query, ACL change, G: write, VM operation, native workload, Godot/Voxel Tools execution, PR merge or baseline modification occurred. Synthetic UAC/process/identity hooks are private module test seams; they do not prove real elevation or live system behavior. PR #49 is unchanged.

## Dependencies added / licenses

None. Windows PowerShell 5.1 and inbox .NET/Windows facilities only; no external downloads or binaries.

## Tests executed (exact commands)

All suites ran locally with Windows PowerShell 5.1:

- `& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclCapture.Protocol.ps1`
- `& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclIcacls.Corroboration.ps1`
- `& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclIcacls.Runtime.ps1`
- PowerShell parser sweep: `[Management.Automation.Language.Parser]::ParseFile` for all `scripts/f2-acl/*.ps1` and `*.psm1`.
- `git diff --check`

Results: protocol `152 assertions / 0 failures`, corroboration `111 assertions / 0 failures`, runtime integration `23 assertions / 0 failures`; 9 PowerShell files parsed with 0 errors; `git diff --check` exit 0. Runtime synthetic coverage includes successful single-launch/all-11 path, scope/storage/identity failure before reads, non-admin coordinator, UAC cancellation, source tamper, package tamper, ACL-profile rejection, incomplete evidence, timeout and cleanup failure. The two existing suites cover mailbox and process failure modes plus parser/comparison adversaries. Tests do not invoke actual `icacls` or UAC.

Windows GitHub CI: See the F2 ACL source-only check attached to the exact final PR #50 head; the final delivery reports its conclusion and run ID.

## Source pins

- Protocol module: `42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728`
- Corroboration module: `06acb1d2eee45abcf1531a9b7113e342320b239bbc32aae1a10d114b55eaa13e`
- Runtime module: `e6751179d2a36abea65527c260fb0f1d1cc81bdccf867172befba4e9f5dffddc`
- Launcher: `fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0`
- Protected coordinator: `3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2`
- Existing PR #49 collector: `bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b`

These pins are repeated in `F2_ICACLS_SOURCE_PINS.json`; explicit LF checkout attributes keep the new pinned file bytes stable on Windows CI. PR #49's source remains unchanged.

## Tests not executed

No actual elevation/UAC, installation into Program Files/ProgramData, actual `icacls.exe`, live host or VM queries, token/group query, ACL assessment, VM operations, G: writes, or guest/native workload. No live result or security acceptance is claimed.

## Failure/recovery cases

Every preflight gate must pass before the first command. A failed gate, UAC cancellation, access denial, any nonzero exit, truncated/incomplete streams, timeout, cleanup error, postflight drift, missing/duplicate path, mailbox mismatch or integrity error yields incomplete status; no retry occurs. The operator must preserve the protected diagnostic package and seek review rather than bypassing a gate.

## Benchmark machine and metrics

Not applicable.

## Known limitations

- Independent exact-SHA source review and successful Windows CI are still required.
- Real package installation and exact ACL-profile verification have not been performed. The synthetic trust-root fixtures are not host-token/effective-access proof.
- A future bounded live collection requires fresh owner authorization for the specific protected package/manifest installation and then separate explicit authorization for the one-UAC execution. The owner must approve the exact source SHA, installation paths/content/ACLs, baseline digests, single UAC prompt and exactly eleven read-only commands.
- A successful collection only corroborates tool output against the retained baseline. It does not establish effective permissions or `PASS_RESTRICTIVE_ACL`; an independent reviewer must assess sanitized comparisons and remaining semantic uncertainty.
- VM state changes that begin and end between preflight and postflight remain an observation race; host administrator/kernel/VMMS and inbox `icacls.exe` are trusted.

## Visual reproduction steps

Not applicable; no visual behavior changed.

## Precise future installation and live-execution gates

1. After independent review of this exact commit and passing Windows CI, request fresh owner authorization to install only the seven pinned package files under `C:\Program Files\F2-G1-Icacls\scripts\f2-acl`, create the required protected parent directories, and place `approved-release.json` at `C:\ProgramData\F2-G1-Icacls\approved-release.json`. The release file must pin this commit, the baseline payload and integrity digests, the pin-manifest digest, and all seven file hashes. Verify the resulting owner, protected DACLs, no-reparse path and file hashes before running anything. This implementation task does not authorize or perform these writes.
2. After installation is independently checked, obtain a separate fresh owner approval for one bounded live collection, explicitly authorizing the single Windows UAC prompt. Invoke the no-argument launcher once. The coordinator must do its fresh VM/storage/path preflight before exactly eleven `icacls` reads; on any failed preflight it must stop before reads. Do not retry, modify ACLs, start the VM, write to G:, or run guest/native workloads.
3. Preserve raw evidence in the protected off-G mailbox. Submit only sanitized per-object comparisons and hashes for independent ACL review. Any remediation requires a new reviewed plan and separate owner authorization.

## Rollback instructions

Before installation, revert the source-only commit or close the draft PR; retain the prior baseline/diagnostic evidence untouched. If package installation is separately approved later, rollback requires separate owner authorization and must remove only the exact newly installed package/manifest paths after confirming they have not been modified or adopted by another process; never alter G: or the retained baseline.

## Reviewer focus / open questions

Review one-UAC boundary and cancellation behavior; external manifest trust and package/manifest ACL profiles; fixed scope and serial/model mapping; preflight-before-first-read and postflight equivalence; actual child process exit/stream/deadline/cleanup accounting; mailbox protections and payload integrity; and fail-closed status publication. Confirm the install manifest generation procedure and Windows CI for the exact candidate SHA.
