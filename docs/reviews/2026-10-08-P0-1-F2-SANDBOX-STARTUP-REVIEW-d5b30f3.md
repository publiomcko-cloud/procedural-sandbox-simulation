# Independent F2 Sandbox diagnostic startup-visibility review — 2026-10-08

Repository: `publiomcko-cloud/procedural-sandbox-simulation`
Developer PR: [#32](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/32)
Issue: [#37](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/issues/37) (owner observed a blank PowerShell window that subsequently closed), bounded by automation issue #34 and original G1 issue #26
**Reviewed exact head:** `d5b30f304973bc02cf65917c4531707487bb9e13`
**Verified parent:** `d552011dee36d41f750350c9e81a55a8685eb5f9`
**Base/merge base and live main:** `0b3e69cec1bd0eeb6da5ff19b50f410acf33129b`
Prior reviews: PR #33 accepted original source-only diagnostic; PR #35 required username correction; PR #36 accepted corrected source-only account username and hash pins. These preserve immutable earlier evidence and do NOT review this new head.
Reviewer method: GitHub remote exact-source/commit/PR/CI inspection plus independently coded SHA256. **No reviewer Windows Sandbox, local PowerShell, host-side state, guest account creation or Godot/native test execution.**

**VERDICT: PASS_PREPARATION — ISSUE #37 startup-visibility source correction accepted; READY_FOR_OWNER_AUTO_SANDBOX_CHECK only.**
This is neither actual owner guest success nor READY_FOR_STAGING, F2 runtime PASS, compatibility assessment, legal clearance, nor authority to merge. F2 remains BLOCKED_ENVIRONMENT until effective safeguards pass.

## Source provenance and static CI
- PR #32 open, draft, unmerged, mergeable at reviewed SHA, based on `0b3e69cec1bd0eeb6da5ff19b50f410acf33129b`. Eight total PR commits and 12 source/docs/test paths.
- Issue #37 delta versus previously source-reviewed `e1b2e898ecb6774da1938a24632956f3620c5ba0`: exactly two commits, seven changed paths:
  `docs/handoffs/P0.1_F2_SANDBOX_AUTOMATION_HANDOFF.md`,
  `docs/specs/P0.1-F2-SANDBOX-AUTOMATION.md`,
  `tests/f2_runtime/provisioning/F2-Isolated-Sandbox-automation.wsb.example`,
  `tests/f2_runtime/provisioning/Prepare-F2SandboxInputs.ps1`,
  `tests/f2_runtime/provisioning/Start-F2SandboxDiagnostics.ps1`,
  `tests/f2_runtime/provisioning/Start-F2SandboxReadiness.ps1`, and
  `tests/f2_runtime/provisioning/Test-F2SandboxAutomation.ps1`.
- Both GitHub Actions Starter checks runs `37852473011` and `37852468745` completed SUCCESS at exactly reviewed SHA; inspected job #37852473011, which checks out code and runs `Validate expected files` static step, **not** PowerShell or a guest integration test.
- Developer-reported automation suite PASS 42 assertions/0 failures, five PowerShell parse results/0 errors and `git diff --check` PASS. Source-only test fixture exercises helper functions and simulated failures; reviewer did not independently execute PowerShell.

## Issue #37 startup/failure-visibility correction — PASS SOURCE
- The exact .wsb `LogonCommand` now invokes PowerShell `-NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -Command`, first prints `F2 DIAGNOSTIC STARTING - visible startup wrapper` with `Write-Host`, then executes only the pinned `C:\F2Input\Start-F2SandboxDiagnostics.ps1`. `-NoExit` keeps the shell open after returning or failing (if the shell successfully starts). Missing mapped bootstrap or its parse error should leave wrapper banner and shell-visible error. Actual Windows guest display remains untested.
- The bootstrap independently prints `F2 DIAGNOSTIC STARTING` immediately after initial assignments and enumerates `F2 STAGE: ...` at mapped script verification, guest PowerShell path, account-cmdlet availability, credential creation, guest-local `New-LocalUser`, child launch, 60s child wait, JSON parse, and child-token/result verification.
- The bootstrap catch emits **only** sanitized `CategoryInfo.Category/Exception type` string with controlled ASCII characters and max 80 characters; report includes last attempted stage, `BLOCKED_STANDARD_USER` or `BLOCKED_ENVIRONMENT`, child process exit code when known, unresolved gates UNKNOWN and `F2 native runtime: NOT RUN`. No raw exception message, password, SecureString, or credential object is intentionally displayed.
- The previous terminal `Start-Sleep -Seconds 180` has been removed; `-NoExit` is the explicit visible-persistence mechanism. A guest window being open is diagnostic evidence only, not CPU/disk/time limit enforcement.
- Source-only negative cases in `Test-F2SandboxAutomation.ps1` check early bootstrap failures, missing mapped script, failed/administrator standard-user child token, 60s timeout, malformed JSON and failures' stage/category output; validate `-NoExit` startup wrapper is enforced by exact hash/config validation; reject writable input map, altered command or tampered input digests. The 42 reported assertions are not evidence that a real Windows child account launched.
- Randomized guest-local account remains `F2Diag_` + 12 uppercase hex characters (19 total), prechecked `<=20`; the script uses CSPRNG/SecureString credential and `Start-Process -Credential`, with explicit child token equality/nonadmin verification and no administrator fallback. After diagnostic, guest-local account/output files/credentials are cleaned where possible. Never claim credential process execution succeeded without an observed guest report.

## Independently reproduced immutable source hashes
Retrieved exact source from PR SHA; normalized CRLF/CR to LF as the PowerShell validators do and used an independently implemented SHA-256 checked against standard `abc` vector. All pins match both host preparer and one-click launcher:
- Bootstrap `Start-F2SandboxDiagnostics.ps1`: `ac8f5952b4138c774a5193f1b5eba0abef6abca961a9573e208296812933ab0e`
- Child diagnostic `Get-F2SandboxReadiness.ps1`: `78fa1dd2d0bc691cecdb5089ee409c71080d30fe0f0e928b2225c7d3bc745d9f`
- Startup .wsb `F2-Isolated-Sandbox-automation.wsb.example`: `0edaa9ab7363c902ea1a39badd5dc8f5b9e6870811cbb32421c7562e133de941`.
Verified `Networking=Disable`, `ClipboardRedirection=Disable`, `VGpu=Disable`, `ProtectedClient=Enable`, narrow `C:\F2-Approved-Inputs` -> `C:\F2Input` `ReadOnly=true` mapping, and exactly one source-pinned diagnostic-only `LogonCommand`. The host launcher tests exact configuration and requires owner scope confirmation; the active-Sandbox process guard refuses to stage mapped inputs while any WindowsSandbox process is active.

## Residual blockers and limits — no false positives
- Owner observed an earlier PowerShell guest window opening blank and closing. There was no screenshot/exit code/stage or duration, so **the underlying cause is not diagnosed**. Added startup visibility provides future evidence but cannot retroactively identify its cause.
- Developer reports WindowsSandbox PID `35740` active during correction. Neither developer nor reviewer launched, terminated, reset, refreshed mapped input scripts or accessed the guest for this new revision. Owner must close/discard any active old guest **normally** before a future attempt. Do not claim that PID is currently running without fresh local evidence.
- The code is not a process supervisor for full native G1, does not establish session time/cpu/disk boundaries, and does not prove future Godot process token or GL Compatibility with vGPU disabled. The automatic child remains a source-only diagnostic. Guest networking and read-only map are configuration-only until observed. Evidence export and discard control remain owner requirements. Actual guest administrator bypass/fallback and cross-account child permission behavior remain unverified by live execution.
- No ZIP/DLL/Godot acquired/executed for this work; no F2 A–G probe or GUI capability result. License notices remain draft, ADR-0002 deferred, no native distribution or backend approval.

## Owner-controlled next action
A clean post-review **diagnostic-only** check may proceed without modifying G1 native scopes:
1. Owner closes/discards all active Windows Sandbox sessions via guest UI; never force-kill related/other host processes. If current session state uncertain, use the existing fail-closed launcher guard.
2. In `C:\Dev\sandbox-sim-p0-1-f2-sandbox-readiness`, launch `tests\f2_runtime\provisioning\Launch-F2SandboxReadiness.cmd` once and approve the presented scoped Yes/No dialog. No guest typing, clipboard/network/vGPU/host writable maps or vendor binaries.
3. Photograph/capture the visible wrapper banner, last bootstrap stage, error category/exit code if failed and overall summary. If only the wrapper appears, report it; do not infer success. If even wrapper not shown, record that and keep blocked.
4. Review real standard-user child token, no active network/default routes, denied input writes and remaining UNKNOWN supervisor/graphics/evidence gates. Do not promote to READY_FOR_STAGING until ALL issue #26 conditions have observed passing evidence.
5. Preserve PR #32 draft, initial and failed review PRs #33/#35 and passing correction PR #36 plus this passing SHA-specific review. **No merge** without owner authorization and no F2 runtime as a consequence of this source PASS.

**Final: PASS_PREPARATION / READY_FOR_OWNER_AUTO_SANDBOX_CHECK / F2 RUNTIME BLOCKED.**
