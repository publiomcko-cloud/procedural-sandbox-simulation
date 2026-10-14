# F2 G1 same-token WMI command-line observation

## Purpose and scope

This package performs one harmless, non-elevated Windows PowerShell 5.1 observation of the command line produced by the reviewed `New-F2LaunchChildInvocation` builder. It captures a real local `Win32_Process` record while a temporary fixture is alive, calls the reviewed `Test-F2LaunchProcessCommandLine` validator for that PID, and reports whether the observed full command line equals the builder's expected command line under exact .NET string comparison.

It does not invoke the published diagnostic command, the production launcher, the elevated coordinator, or any updater. It does not use `Start-Process`, a `RunAs` verb, UAC, `icacls`, ACL APIs, VM/Hyper-V commands, G:, or native F2 workloads. It creates one new temporary directory and one inert PowerShell fixture beneath the current user's local TEMP path; after the fixture exits normally it removes only those exact new objects. It never terminates the fixture. The production repository-facts helper may terminate its own Git query process if that query reaches its reviewed timeout. If the fixture may remain or cleanup is uncertain, the script leaves the temporary objects in place and reports failure.

The expected child script only validates its four builder-supplied arguments, sleeps for 25 seconds, then exits 0. It never opens the test pipe and performs no filesystem or host operations.

## Immutable implementation inputs

- PR #69 review package: `56a34d7899ba31b0d3fe6d3185435bc182ac453f`.
- Runtime implementation: `8c14cf97c9446e11b8afbd64196c3f4558d4c3c9`.
- Runtime launch module checkout-byte SHA-256: `06f117c6be29e3e150149087cb19323e83df20601b8d134f0bb02ec7335867d2`.
- This observation script's Windows checkout-byte SHA-256: `4fe30974cdab3b1ca4a87aaf26591c0192f5fa0c4423b23b155c5bab7a1abc4d`.
- Git core path/SHA used by the production repository-facts helper: `C:\Program Files\Git\mingw64\bin\git.exe` / `1a0043555d254618f2d56c936c3d9a1fbfb878bc878416a133c346bc7835eda9`.
- The script reads the launch module through a read-only handle, verifies the complete bytes, decodes those same bytes, and creates an in-memory dynamic module from that ScriptBlock. It does not import the module by reopening its path after verification.

## Prerequisites

The manual environment must already contain the two verified, clean detached worktrees at these fixed paths:

- `C:\Dev\f2-g1-diagnostic-elevation-plan-review` at `56a34d7899ba31b0d3fe6d3185435bc182ac453f`.
- `C:\Dev\f2-g1-diagnostic-launch-runtime` at `8c14cf97c9446e11b8afbd64196c3f4558d4c3c9`.

The review worktree must have the expected GitHub origin. The runtime worktree must have the expected origin, exact implementation commit, and clean state. The script checks both through the reviewed production repository-facts helper. It also checks the runtime module hash, path-chain reparse status, Windows PowerShell version, standard non-administrator token, and local fixed TEMP volume before creating its fixture.

Do not substitute paths, hashes, branches, commands, or PowerShell versions. This package is not an elevated diagnostic and does not authorize one.

## Exact manual procedure

1. Obtain this review package at its final published immutable commit. In a standard PowerShell 5.1 session, verify the script's Windows checkout-byte SHA-256 before running it:

```powershell
$scriptPath = 'C:\Dev\f2-g1-manual-wmi-observation\docs\reviews\f2-g1-manual-wmi-observation\Observe-F2LaunchWmiCommandLine.ps1'
(Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
```

It must equal `4fe30974cdab3b1ca4a87aaf26591c0192f5fa0c4423b23b155c5bab7a1abc4d`. Confirm the two prerequisite worktrees above are still clean at their exact commits.
2. Open a normal, non-administrator Windows PowerShell 5.1 window. Do not choose **Run as administrator**. If Windows presents a UAC prompt, cancel and stop; this package has no reason to request one.
3. Paste these lines exactly into that standard-token window:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\Dev\f2-g1-manual-wmi-observation\docs\reviews\f2-g1-manual-wmi-observation\Observe-F2LaunchWmiCommandLine.ps1"
$LASTEXITCODE
```

The nested PowerShell process is Windows PowerShell 5.1 and uses `-NoProfile`. It is not elevated. Its only launched child is the inert fixture, started by `.NET Process.Start` with `UseShellExecute = $true` and an empty `Verb`. The script independently rejects an elevated or Administrator requester token. There is no automatic retry.

4. Preserve the single sanitized JSON line and its process exit code. `Outcome=PASS` and script exit 0 mean only that this same-token ShellExecute fixture's actual WMI command line matched the builder, the production validator accepted it, the child exited 0, and fixture cleanup completed. Any other outcome or exit code is failure; do not launch an elevated diagnostic.
5. If `CleanupOutcome` is not `COMPLETE` or `NO_TEMP_OBJECTS_CREATED`, do not delete anything manually while the fixture may remain. Preserve the reported temporary-root GUID and sanitized JSON for review. The script does not kill the fixture or recursively remove a directory.

## Evidence and limits

The result includes the actual child PID and image path, actual command-line character count and SHA-256, exact full-line equality, encoded-payload equality, the production validator result, same-requester SID comparison, child exit code, timeout state, and cleanup outcome. It never prints the raw command line, encoded payload, requester SID, exception text, or profile path. The observed command line is retained only in memory long enough to compare and hash it.

The ShellExecute call uses an empty verb from a requester whose token the production helper classified as standard and non-administrator; the script additionally verifies the child process owner SID equals the requester SID. It does not independently query the child's token integrity level. This observation does not test UAC, cross-integrity command-line representation, an elevated token, a named-pipe handshake, or the elevated diagnostic. A passing result is not authorization to execute the published elevated command.

The child and WMI queries are bounded. Direct WMI reads set `OperationTimeoutSec=2`; while calling the production validator, the script temporarily sets the process-global `PSDefaultParameterValues` entry and restores its prior value. The separate `-File` process exits after the result, so this temporary preference does not persist in the operator's shell. The production repository-facts helper bounds each of its four fixed Git queries to 10 seconds and may terminate its own Git query process on timeout. The fixture exits naturally after 25 seconds; the WMI observation window is 14 seconds from child start and the overall script deadline is 120 seconds. A missing/duplicate WMI record, identity mismatch, validator rejection, timeout, nonzero child exit, or incomplete cleanup produces a nonzero script exit. No source correction should be inferred unless a real observed mismatch is returned.

Microsoft PowerShell 5.1 references: [Get-CimInstance timeout parameter](https://learn.microsoft.com/powershell/module/cimcmdlets/get-ciminstance?view=powershell-5.1), [New-Module](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/new-module?view=powershell-5.1), and [Import-Module](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/import-module?view=powershell-5.1).
