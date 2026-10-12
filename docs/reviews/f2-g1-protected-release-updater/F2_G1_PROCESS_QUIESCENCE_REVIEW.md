# F2 G1 updater process-quiescence correction

Status: SOURCE-ONLY; awaiting independent exact-SHA review. No UAC, protected update, host process query, process termination, ACL query, VM/G: operation or native workload was performed.

Finding: PR #59 review `5493067444`; Issue #48 comment `6127688692`. Reviewed starting PR head: `5d231f4697673569de526c03cedf61c72e769e07`. Previously accepted production source: `691eae48d67789bf798e270cb9cca7790d728d26`. Corrected production source: `8b70a70934445bee660c1e53e71b2e7b20a6191f` (parent `5d231f4697673569de526c03cedf61c72e769e07`). Test-only diagnostic commits `3a3383c6fd08b87dada4e3e4c1e9421657afba7c`, `c95ce9b5751d7d3a6cb79b85eb2d836d87d762a4`, and `d63b51db7c2de8b8e1197ebede653f4d762cae9a` refine synthetic path normalization and failure detail. Production updater/launcher and the SourceRoot candidate remain at `8b70a70934445bee660c1e53e71b2e7b20a6191f`.

## Supported v2/v3 runtime surfaces

The updater now enumerates every script/module path that belongs to the supported runtime layouts. The `RuntimePathInventory` contains the capture launcher, protected coordinator, and runtime module for each row. This path map supports closed-scope assertions; it is not used to allow a process. The fail-closed rule rejects every unrecognized PowerShell process, including invocations whose command lines do not disclose a script/module path.

| Release surface | Launcher | Coordinator | Runtime module |
|---|---|---|---|
| v2 source checkout | `C:\Dev\f2-g1-capture-id-contract-source\scripts\f2-acl\Invoke-F2IcaclsCapture.ps1` | `C:\Dev\f2-g1-capture-id-contract-source\scripts\f2-acl\Invoke-F2IcaclsProtectedCoordinator.ps1` | `C:\Dev\f2-g1-capture-id-contract-source\scripts\f2-acl\F2AclIcacls.Runtime.psm1` |
| v3 source checkout | `C:\Dev\f2-g1-protected-updater-source\scripts\f2-acl\Invoke-F2IcaclsCapture.ps1` | `C:\Dev\f2-g1-protected-updater-source\scripts\f2-acl\Invoke-F2IcaclsProtectedCoordinator.ps1` | `C:\Dev\f2-g1-protected-updater-source\scripts\f2-acl\F2AclIcacls.Runtime.psm1` |
| fixed installed v2 | `C:\Program Files\F2-G1-Icacls\scripts\f2-acl\Invoke-F2IcaclsCapture.ps1` | `C:\Program Files\F2-G1-Icacls\scripts\f2-acl\Invoke-F2IcaclsProtectedCoordinator.ps1` | `C:\Program Files\F2-G1-Icacls\scripts\f2-acl\F2AclIcacls.Runtime.psm1` |
| versioned installed v3 | `C:\Program Files\F2-G1-Icacls\releases\<reviewed-commit>\scripts\f2-acl\Invoke-F2IcaclsCapture.ps1` | `C:\Program Files\F2-G1-Icacls\releases\<reviewed-commit>\scripts\f2-acl\Invoke-F2IcaclsProtectedCoordinator.ps1` | `C:\Program Files\F2-G1-Icacls\releases\<reviewed-commit>\scripts\f2-acl\F2AclIcacls.Runtime.psm1` |

The versioned path is constructed from the candidate's already-validated commit. The source path is the fixed `SourceRoot`, which the existing origin/commit/clean-worktree/source-pin checks validate. Direct module imports and encoded PowerShell commands have no dependable file-path signature, so path matching is not used as the process allow rule.

## Exclusion rule

After acquiring both the exclusive `release.lock` lease and the active-manifest handle opened for read with `FileShare.Delete`, the updater inventories all local `Win32_Process` entries named `powershell.exe`, `powershell_ise.exe`, or `pwsh.exe`.

Only two processes may be present:

1. The current elevated Windows PowerShell 5.1 updater process, matched by its live PID and required to be named `powershell.exe`.
2. Exactly one requester-side `powershell.exe`, bound across UAC by the requester PID, UTC process creation ticks, original requester SID, and a command line containing the exact source commit, launcher/updater/candidate SHA-256 values and fixed source-checkout updater launcher. The requester's command must be the reviewed `-Command` bootstrap form; encoded or command-line-ambiguous requester forms are rejected. It is never exempted merely because it is an ancestor.

Every other PowerShell process blocks the transaction with `UPDATE_RUNTIME_PROCESS_ACTIVE_OR_UNKNOWN`, regardless of whether its command line names a known script. A missing/unreadable command line blocks with `UPDATE_PROCESS_COMMAND_LINE_UNKNOWN`; failed or malformed process inventory blocks with a stable `UPDATE_PROCESS_*_UNKNOWN` error. The updater does not terminate, suspend, or otherwise modify processes. This deliberately strict policy also blocks unrelated PowerShell work and can make an update unavailable until those processes close.

An already-running v2 launcher, coordinator, direct runtime-module caller, or encoded PowerShell invocation is a foreign PowerShell process and blocks. An arbitrary non-PowerShell process host or renamed/custom PowerShell executable is outside the supported runtime interface and is not declared covered.

## Supported launch topology (documentation/test correction)

The previous proposed command was run from an interactive standard-user PowerShell session and started a second requester PowerShell. During UAC the updater would therefore see three PowerShell processes: the original interactive caller A, the pinned requester B, and the elevated updater C. A is not B or C and is correctly rejected. No ancestor exception is added.

For a future separately authorized run, all `powershell.exe`, `powershell_ise.exe`, and `pwsh.exe` processes must first be exited normally. Then use Explorer's Win+R dialog to open a fresh `cmd.exe /d /k`; do not start CMD from a PowerShell session or PowerShell-backed terminal. Paste the exact CMD command in the main updater review and read `%ERRORLEVEL%` after it returns. The supported topology is:

```text
Explorer -> cmd.exe -> requester Windows PowerShell 5.1 B -> UAC -> elevated Windows PowerShell 5.1 C
```

At the quiescence point, the system-wide PowerShell inventory must contain exactly B and C. CMD is not one of the PowerShell hosts in the inventory. Any unrelated or legacy PowerShell process still running causes the existing fail-closed block; nothing is closed or terminated automatically. The exact command keeps the source commit, candidate, updater and launcher pins, hashes and dot-sources the exact verified launcher bytes in memory. A synthetic CMD fixture validated quoting and return-code propagation only; the production command and updater were not launched.

## Barrier, inventory and activation ordering

Normal update path:

```text
verify old/new inputs and source
  -> acquire exclusive release.lock lease
  -> acquire active-manifest read handle with FileShare.Delete
  -> process inventory #1
  -> verify held old-manifest bytes
  -> stage, hash and DACL-check complete v3 package
  -> move complete package to its unique versioned directory
  -> process inventory #2 immediately before activation
  -> atomically replace active manifest; retain old manifest backup
```

Both handles remain open from the first inventory through activation. The v3 runtime must acquire a shared `release.lock` lease, so the updater's exclusive lease prevents new v3 readers. The v2 runtime does not use that lease, but it must read `approved-release.json` before it can select/run its package. The held manifest handle's share mode permits deletion/replacement only; it denies a new read-open that requests read sharing. Thus a v2 process which obtained/cached the old manifest before the barrier must still be a running PowerShell process at inventory #1 or #2 and is rejected. If it starts a coordinator after a scan, that coordinator must freshly read the manifest and is denied while the barrier remains open. A new direct module invocation likewise cannot reach the runtime operation without its manifest read. The final inventory catches processes that appeared during package staging; the barrier closes the remaining supported-launch window after that snapshot.

Recovery-to-forward follows the same ordering for its activation path: it acquires the exclusive lease and manifest barrier, then inventories immediately before its single `File.Replace`. Recovery verification-only and preserve-old paths do not activate the manifest.

No process is killed to make the gate pass. Any process list, owner lookup, PID/creation-time check, path identity, or held-handle failure stops before manifest activation. Post-activation behavior remains governed by the existing exact hash, DACL, backup and journal checks.

## Synthetic Windows PowerShell 5.1 cases

`Test-F2AclProtectedReleaseUpdater.ps1` uses synthetic `Win32_Process`-shaped records and TEMP-only transaction fixtures. It covers:

- Old and new source-checkout launchers; fixed installed coordinator; all 12 canonical launcher/coordinator/runtime-module paths.
- Direct module invocation, encoded command, PowerShell ISE, and a v2 process annotated as having cached the old manifest. All foreign processes block without needing a successful path match.
- Missing command line, inventory exception, requester PID reuse/creation-time mismatch, changed SHA pin, and encoded requester command.
- A normal exact requester process bound by PID, creation time, SID and reviewed command pins.
- The old caller/requester/updater three-PowerShell process inventory is rejected; the corrected two-record requester/updater inventory is accepted without an ancestor exemption. The CMD-to-PowerShell quoting and exit-code propagation shape passes an inert TEMP-only `exit 37` probe.
- Wrong/missing requester PID, SID, creation timestamp, source commit, launcher hash, updater hash or candidate hash is rejected. Unrelated PowerShell, `pwsh.exe`, encoded invocation, inaccessible command line and cached-v2 activity also fail closed.
- A late process appearing between the first and activation-edge inventories. The update fails before replacing the old manifest. A separate real TEMP-only sharing fixture verifies that a new manifest reader is denied while the barrier is held; the activation hook repeats that read attempt immediately after the second synthetic inventory and verifies it remains denied.
- Event ordering: barrier acquisition precedes inventory #1, inventory #2 occurs before activation, and all failure cases retain old active-manifest bytes.

These tests model process inventory data and call ordering; the CMD probe runs only a TEMP fixture and exits with a synthetic nonzero status. The final direct Windows PowerShell 5.1 suite totals are Protocol 152, Corroboration 118, Runtime 41, Entrypoint 18, Updater 133, and Native helper 20: **482 assertions, zero failures**, all six child exit codes 0. The PS5.1 parser sweep parsed 14 tracked PowerShell files with zero errors; `git diff --check` passed. Complete stdout/stderr and command evidence are in `evidence/WINDOWS_POWERSHELL51_FULL_SUITE.txt`; hosted CI is linked from the PR. No production updater, UAC, actual process inventory, C: update, or process termination was performed. These tests do not prove elevated WMI visibility/owner lookup or protected NTFS sharing/rename behavior.

## Security limits and remaining gates

- The process table is a point-in-time inventory. The lock/barrier, rather than polling alone, excludes new supported runtime reads after the barrier. This proof depends on the reviewed v2/v3 entrypoints continuing to require their active release manifest before runtime work; arbitrary user-authored code that carries a copied old manifest is outside the supported interface.
- The exact elevated visibility of the requester process, `Win32_Process.GetOwnerSid`, and `CreationDate` round-trip remains UNKNOWN until a separately authorized real UAC run. Failure is fail-closed.
- Real C: NTFS share-mode/replace behavior, Administrator ownership/DACL behavior, and update recovery remain untested.
- No production source, seven-file release member, `F2_ICACLS_SOURCE_PINS.json`, updater/launcher pin, candidate `ReviewedCommitSha`, versioned `PackageRoot`, or candidate SHA changed in this documentation-and-test-only correction.
- The existing native C# `IntPtr.Zero` correction remains unchanged.

## Acceptance summary

| Gate | Result |
|---|---|
| Legacy and current source-checkout paths represented | Synthetic PASS |
| Installed fixed and versioned paths represented | Synthetic PASS |
| Direct and encoded PowerShell activity excluded | Synthetic PASS; blanket foreign-host block |
| Cached-old-manifest process rejected | Synthetic PASS |
| Documented three-PowerShell command rejected | Synthetic PASS; no ancestor exception |
| Fresh Explorer/CMD launch with exactly requester and updater PowerShell accepted | Synthetic PASS |
| CMD quoting and exit propagation | TEMP-only synthetic PASS (`exit 37`) |
| Wrong requester PID/SID/time/source/hash pins rejected | Synthetic PASS |
| Barrier/inventory/activation sequence | Synthetic PASS |
| Late process between inventories | Synthetic PASS; rejected before switch |
| Fresh reader after final inventory | TEMP file-sharing fixture PASS |
| Inventory error / inaccessible command line | Synthetic PASS; fail-closed |
| Actual elevated process visibility and owner verification | UNKNOWN; not run |
| Protected C: update or recovery | NOT RUN; prohibited |

## Reviewed byte identities

- Updater Windows CRLF checkout SHA-256: `d26eb89a424e3f268099e0ac1d3ffd674dde1128321567df3a0702abb591f75e`.
- Standard launcher Windows CRLF checkout SHA-256: `8278bbff8e5b7cdb313235bcc271fa31a947ca384d7496053650c3097af19720`.
- Candidate v3 manifest SHA-256: `74d178917fba4f50fdca40505d8c1dc81639f3c60bbb25c0332fd737c681562c`; it binds `ReviewedCommitSha` and versioned `PackageRoot` to the corrected source commit.
- All seven runtime package hashes and the source-pin manifest remain unchanged; they are listed in the candidate and artifact manifest.
