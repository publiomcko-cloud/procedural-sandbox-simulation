# Independent P0.1-F2 G1 Sandbox one-click automation review — 2026-10-08

Repository: publiomcko-cloud/procedural-sandbox-simulation
Developer PR: #32, draft/open/unmerged on review
Exactly reviewed HEAD: 26f50074db8398011583f3deb42222f9bcf81a7c
Verified HEAD parent: 56800aa83a20396a605610a2c725df395eb60129
Verified base/merge base and live main: 0b3e69cec1bd0eeb6da5ff19b50f410acf33129b
Prior accepted review PR: #33 at 534391ab6a6d7a10694c558af83f3f1707947f22, only covers earlier #31 source preparation SHA 16720f207ebfab0a19ee7b06e70fb86fed425ba9; do NOT modify.
Developer issue #34: one-click guest automation WITHOUT vendor native execution. Original G1 runtime isolation gates: issue #26.

**VERDICT: CORRECTIONS_REQUIRED — F2-AUTO-R1 (HIGH functional blocker).** No acceptance of current launcher for a new guest run. Prior live Sandbox PID 41900 used old bootstrap source and is UNVERIFIED; owner must close/discard naturally before any later run. NO F2 native runtime validation, no Godot or Voxel Tools execution, no A–G probes, no independent Windows guest execution.

## Provenance / scope / static checks
- GitHub PR #32 exact SHA, draft OPEN UNMERGED, ahead of main with 5 commits and 12 files total. Correction delta from source-reviewed 16720f2 consists of two commits changing 10 paths, all source/docs/scripts/.wsb.
- Two GitHub Actions Starter runs 37847132035 and 37847126700 completed SUCCESS at exact HEAD. Inspected job steps: Git checkout and 'Validate expected files' only, NOT PowerShell test harness or Sandbox launch/account creation.
- Developer reports source-only 9 assertions/0 failures, source AST parsing, staged reviewed inputs, and attempted Sandbox launch with process ID 41900 under an earlier bootstrap hash 2bbb945e86274b98eda6b2c08eae156c0d2851f114c895f77505576991600093. The earlier version placed the 180-second hold before account setup; source correction was made afterward. No current bootstrap's standard-user launch or guest observations have been validated.

## F2-AUTO-R1 — BLOCKING: generated local account name exceeds Windows limit
Path: tests/f2_runtime/provisioning/Start-F2SandboxDiagnostics.ps1

Current code:
```powershell
$randomBytes = New-Object byte[] 8
...
$suffix = [BitConverter]::ToString($randomBytes).Replace('-', '')
$username = "F2Diag_$suffix"
$newUser = New-LocalUser -Name $username -Password $securePassword ...
```
Eight random bytes render 16 hex characters. The literal prefix `F2Diag_` is 7 characters: final **23-character username**. Microsoft's official New-LocalUser documentation states `-Name` can contain **up to 20 characters**. See https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/new-localuser?view=powershell-5.1 .

Therefore this user-creation path is structurally invalid and expected to reject every generated account, before the script can start the diagnostic under non-administrator credentials. The fail-closed catch is good (it should report `BLOCKED_STANDARD_USER`), but an unavoidable failure violates issue #34 one-click functional completion. No source-only test currently checks computed username length or actually exercises the guest account sequence.

**Bounded correction requested:** Shorten random username to <=20 characters while retaining enough unique entropy; e.g. use **6 RNG bytes -> 12 hex characters** and original 7-character prefix => 19 chars, or a short prefix plus the existing suffix. Explicitly assert `$username.Length -le 20` before `New-LocalUser`. Add source-only regression coverage in Test-F2SandboxAutomation.ps1 that independently derives/guards produced username character count, checks permitted characters, and ensures the bootstrap keeps randomized credentials guest-local, no host fallback. Avoid source-inspection-only tests masquerading as guest account creation. Re-pin SHA-256 of the corrected bootstrap in the host preparer and host launcher and add/verify previously approved staged-file replacement hash if needed. Re-run script parsing, source-only positive/negative fixture tests, whitespace checks, static CI, then submit NEW exact head/parent for independent review. Do not execute vendor binaries.

## Checks passing at this SHA (source scope only)
- Read full host launcher, .cmd, host preparer, bootstrap, child diagnostic, static test script, .wsb, documentation and handoff.
- Independently computed normalized UTF-8/LF SHA256 for all three pinned files with a self-tested SHA256 algorithm, verified expected in host sources and report:
  - Get-F2SandboxReadiness.ps1: 78fa1dd2d0bc691cecdb5089ee409c71080d30fe0f0e928b2225c7d3bc745d9f
  - Start-F2SandboxDiagnostics.ps1: 4a28b6d8a6b56239da131204316f441ab3a486d9bcb9a7bb7e3b4c77e36800f3
  - F2-Isolated-Sandbox-automation.wsb.example: c80ef647561219f1e7ba5ff9d9cfabdda15f28244cda69af8fea580360058482
- Exact .wsb content contains Networking=Disable, ClipboardRedirection=Disable, VGpu=Disable, ProtectedClient=Enable, audio/video/printer disabled, one pinned diagnostic-only LogonCommand and only a read-only C:\F2-Approved-Inputs to C:\F2Input mapping. Host script fail-closed pin/config checks plus a Yes/No scope dialog and active WindowsSandbox process guard; it does not launch the extension, fetch vendor bytes or change Windows optional features.
- Guest bootstrap obtains random password with a cryptographic RNG, builds SecureString without printing/passing plaintext credentials through command arguments, uses Start-Process -Credential with a guest-local temporary user, checks child's reported identity and IsInRole(Admin) result, and intends to fail closed with no admin fallback. These are code-path observations, not proof that password/credential launch works in an actual guest; the generated username bug blocks execution.
- Child diagnostic preserves UNKNOWN for Godot renderer, future launch account, CPU/disk/time supervision, evidence export/discard. No READY_FOR_STAGING claim. Timeout 60 s bounds child test only, 180 s is a visible report hold only and NOT an enforceable guest/session/resource budget.

## Residual limitations and safety gates
- Owner's original manual guest diagnostic observed no active networking/default routes and a read-only mapped folder but an Administrator-capable WDAGUtilityAccount token; this remains an environment FAIL until actual new guest standard-user diagnostic evidence is observed. Current process 41900 running older bootstrap is not proof of correct setup; do not modify the mapped folder during its lifetime.
- Host launcher detects `Get-Process -Name WindowsSandbox` and refuses to stage if present; closing/discarding from guest UI before trying a NEW corrected run is mandatory. The reviewer cannot observe its current state and must not assert it has closed.
- An operational process token PASS would remain **only diagnostic account evidence**; actual Godot GL Compatibility with vGPU disabled, future native launch as standard user, CPU/disk/session supervision, reviewed evidence export and Sandbox cleanup remain separate UNKNOWN/F2 gates.
- No guest-local account, PowerShell script, native file or vendor dependency actually run by reviewer. No claim of source-code security proof or leakage absence under runtime execution; script content review only.
- Existing reviewer PR #33 remains historically intact. Do not merge #32 or this review without owner approval. F2 remains **BLOCKED_ENVIRONMENT** and ADR-0002 PROPOSED/DEFERRED.

## Recommended next action
On SAME developer PR #32 branch correct F2-AUTO-R1, update appropriate report/handoff and pinned hashes, add regression assertions (including negative case for >20 chars) and rerun pure source tests. Return exact reviewed head SHA and parent for independent reviewer. Owner should close/discard the old Sandbox normally but NOT launch the current defective build, download any vendor ZIP, execute Godot or run native DLLs. After a passing SHA-specific review, owner may run one diagnostic-only guest automation and supply screenshot of actual standard-user token; separate G1 remaining gates still apply.

**Final disposition: CORRECTIONS_REQUIRED — BLOCKED_ENVIRONMENT — A–G UNRUN.**
