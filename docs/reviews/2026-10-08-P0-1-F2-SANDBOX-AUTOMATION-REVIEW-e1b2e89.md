# Independent F2 Sandbox automation correction re-review — 2026-10-08

Repository: `publiomcko-cloud/procedural-sandbox-simulation`.
Developer PR: [#32](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/pull/32), draft/open/unmerged at review.
Prior independent finding: PR #35, `CORRECTIONS_REQUIRED` at reviewed SHA `26f50074db8398011583f3deb42222f9bcf81a7c` (F2-AUTO-R1, invalid 23-character New-LocalUser account name). Preserve #35 as historical.
**Exact corrected reviewed HEAD:** `e1b2e898ecb6774da1938a24632956f3620c5ba0`.
Verified parent: `26f50074db8398011583f3deb42222f9bcf81a7c`.
Verified base and live main: `0b3e69cec1bd0eeb6da5ff19b50f410acf33129b`.
Developer issue: #34, scoped diagnostic-only automation; parent G1 native execution issue: #26.
Reviewer: GitHub remote connector, source inspection and independent programmatic SHA-256 / deterministic text checks; **no reviewer Windows/PowerShell/guest execution**.

**VERDICT: PASS_PREPARATION — F2-AUTO-R1 RESOLVED. Operational status READY_FOR_OWNER_AUTO_SANDBOX_CHECK; NOT READY_FOR_STAGING, not an F2 runtime result. No merge authorized by this review.**

## Git and CI

- Verified PR #32 exact HEAD and unchanged `main`, draft/open/unmerged/mergeable; entire PR changes 12 source/test/docs files, without binary assets or native Godot modifications.
- Exactly one correction commit above the prior failed-review head, touching only six expected paths: `Start-F2SandboxDiagnostics.ps1`, `Test-F2SandboxAutomation.ps1`, `Prepare-F2SandboxInputs.ps1`, `Start-F2SandboxReadiness.ps1`, `docs/specs/P0.1-F2-SANDBOX-AUTOMATION.md`, and `docs/handoffs/P0.1_F2_SANDBOX_AUTOMATION_HANDOFF.md`.
- GitHub Starter runs `37848172033` and `37848164877` completed SUCCESS at exact HEAD. Independently read CI job steps; each runs checkout plus **Validate expected files** static only. Neither runs PowerShell, an actual local account, or the Sandbox.
- Developer reports Windows local automation suite PASS **15 assertions/0 failures**, parsing **5 PowerShell scripts/0 errors**, JSON/config/hash checks and `git diff --check` PASS. Reviewer confirmed source of assertions but did not execute these tests on Windows.

## F2-AUTO-R1 RESOLVED: bounded guest-local username

The guest bootstrap now uses `New-Object byte[] 6` with `System.Security.Cryptography.RandomNumberGenerator`. `BitConverter` yields exactly 12 uppercase hexadecimal characters; the fixed prefix `F2Diag_` is seven characters. Final local username is **19 characters**, under Windows `New-LocalUser -Name` 20-character maximum. See https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/new-localuser?view=powershell-5.1.

New `Assert-GuestDiagnosticUsername` explicitly enforces both maximum length 20 and `^F2Diag_[0-9A-F]{12}$`. Verified it is called **before** `New-LocalUser`. New source-only PowerShell test extracts this function from the parsed AST, then exercises bounded valid 19-char input, oversized 23-char input rejection, and malformed nonhex input rejection; it also checks use of 6 random bytes, presence of validator invocation and unique function definition. The full suite now claims 15 assertions including previous security fixture tests. These are genuine direct validator checks but are NOT proof of guest account creation or `Start-Process -Credential` success.

## Independently verified exact pins and boundaries

Retrieved source directly at corrected GitHub HEAD. Recomputed SHA-256 from independently normalized UTF-8/LF text using a self-checked SHA-256 implementation (known `abc` vector). Exact hashes:
- Guest diagnostic `Get-F2SandboxReadiness.ps1`: `78fa1dd2d0bc691cecdb5089ee409c71080d30fe0f0e928b2225c7d3bc745d9f`.
- Corrected guest bootstrap `Start-F2SandboxDiagnostics.ps1`: `88cad4600e8417ab524728a27cd638b27b5f46fcf0c0495f7ff21e9cda80288e`.
- Automation `.wsb.example`: `c80ef647561219f1e7ba5ff9d9cfabdda15f28244cda69af8fea580360058482`.

The new bootstrap pin appears unchanged and equal in **both** the host preparer and one-click launcher. Diagnostic pins remain equal between host scripts; launcher pins the WSB hash. Reviewed template explicitly has Networking=Disable, ClipboardRedirection=Disable, VGpu=Disable, ProtectedClient=Enable, read-only `C:\F2-Approved-Inputs` mapped to `C:\F2Input`, and exactly one diagnostic `LogonCommand` invoking only the pinned bootstrap. Actual runtime enforcement still requires owner guest observation.

The host one-click launcher checks active WindowsSandbox sessions before staging; checks expected files, hash and template, requires a scope Yes/No dialog, then launches only the Sandbox host executable. Bootstrap creates a random-password **guest-local** account, checks it is not in Administrators, attempts `Start-Process -Credential` with a child 60-second bound, compares reported child identity/nonadmin state, cleans guest-local credentials and outputs, and refuses any administrator diagnostic fallback. There is no persistent execution-policy change; PowerShell Bypass applies to the launched diagnostic process only. Password generation uses cryptographic randomness and transient SecureString/char array; no deliberate plaintext password printing/persistence was found in source. This is source inspection, **not** an executed security certification.

## Residual runtime unknowns / mandatory next step

- Previous owner manual diagnostic (before automatic standard-user work) observed no UP adapters/default routes and denied writes to the read-only mapping, but `WDAGUtilityAccount` was Administrator. That fail is historically accurate.
- Prior automation attempt used an obsolete bootstrap, WindowsSandbox process PID `41900` was previously observed but guest behavior remained unknown. Developer reports it did not terminate/launch a Sandbox or overwrite staged files during the correction, and that the earlier process was absent in the latest local process listing. Reviewer has **not** observed a clean guest exit. Before a new attempt, owner confirms and closes/discards **all** active Sandbox sessions via the guest UI. The revised launcher deliberately blocks staged-file changes when a WindowsSandbox process is present.
- **READY_FOR_OWNER_AUTO_SANDBOX_CHECK**, not guest-ready: owner double-clicks `tests/f2_runtime/provisioning/Launch-F2SandboxReadiness.cmd` in the correct worktree; reviews scope and accepts, waits for compact report, captures screenshot. No commands need be entered in guest. If account creation/credential launch, token, network or read-only mapping fails, record FAIL/BLOCKED and do not run vendor code.
- A successful child token observation would establish only that **the diagnostic** ran nonadmin. Future Godot launch token, actual GL Compatibility renderer under vGPU off, enforced CPU/disk/time supervision, controlled evidence export and guest discard remain **UNKNOWN**; never treat a diagnostic pass as `READY_FOR_STAGING` automatically.
- F2 native ZIP has not been obtained/executed in this workstream; no vendor DLL, Godot runtime, probe A–G, owner visual verification, legal distribution clearance, final backend/ADR-0002 acceptance, or integration was authorized by this review.

## Recommendation

The owner may integrate developer PR #32 and preserved historical reviews #33 (initial source-only acceptance), #35 (failed automation review), and **this passing correction review** in their intended dependency order after explicit approval, retaining F2 `BLOCKED_ENVIRONMENT` until actual observed guest readiness. More immediately, with PR #32 source accepted, owner can safely perform **diagnostic-only** one-click Sandbox check provided there are no active guests and all review-pinned files are in the correct worktree; capture the outcome for review. No vendor runtime execution or security downgrade.

**Final classification: PASS_PREPARATION / F2-AUTO-R1 RESOLVED / READY_FOR_OWNER_AUTO_SANDBOX_CHECK / F2 RUNTIME UNTESTED.**
