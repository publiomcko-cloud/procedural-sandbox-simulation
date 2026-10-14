# F2 G1 historical manifest diagnostic launch plan

## Review decision requested

This is a source-only launch design for a possible separately authorized diagnostic probe. No UAC, elevated process, protected updater, live host state, ACL, VM, or baseline was accessed. The historical elevated failure remains unexplained. A diagnostic `PASS` means only that the historical candidate manifest parsed and its `ReviewedCommitSha` matched the pinned source commit.

## Immutable lineage and fixed checkouts

- Review base: PR #68 HEAD `c3d1280f9905730eda8cff40865e8afbbb642367`.
- Candidate corrected launch source commit: `78a3cb3089babdab520d7d17dda920de276dfbc6`, parent `1057836646aba001ed1255e1ed566da5867a55d5`.
- The review package and executable launch checkout are separate. The review copy used by the short outer-command loader is `C:\Dev\f2-g1-child-auth-postmortem`; the executable source worktree is `C:\Dev\f2-g1-diagnostic-launch-runtime` and was not changed. Before any future launch, that runtime worktree must be prepared clean at the candidate source commit above. No launch is authorized here.
- Historical production source: `C:\Dev\f2-g1-protected-updater-source`, commit `396c44965c90c08292ad2835f8317e81b6b9daaf`.
- Historical candidate: `C:\Dev\f2-g1-protected-updater`, commit `7f99bc10f3e2258d2340cea4e7ba1352022cbb6d`.
- The three checkouts must have the expected origin, exact commits, clean status, canonical paths, and no reparse points. The launch gate rejects mismatches.

## Standard-token CMD entry

Open a normal `cmd.exe` from Win+R with `cmd.exe /d /k`, then paste the single line in `EXACT_UAC_COMMAND.txt`. This candidate command is for review only, was not executed, and is not authorized. Its line is 4,655 characters, below the documented 8,191-character `cmd.exe` limit. It names the system PowerShell executable by absolute path and contains only an encoded bootstrap, with no CMD metacharacters that trigger command chaining or expansion.

The small encoded entry opens the fixed outer-bootstrap path through a read-only handle, checks the opened handle's final path and exact SHA-256, and creates a ScriptBlock from those same in-memory bytes. It does not invoke a mutable checkout file with `-File`, dot-source it, or accept path/hash arguments from the command line. The outer bootstrap then verifies the separate runtime checkout and pinned launch module/launcher before continuing.

The future one-UAC child command is generated from the actual child-bootstrap template and fails closed above a 3,600-character full command-line bound. Windows PowerShell 5.1 tests exercised the exact generated argument shape through harmless, non-elevated ShellExecute fixtures; no `RunAs` verb was used. The maximum-bound fixture uses the largest accepted PID and start-tick values.

## Launch flow

```mermaid
sequenceDiagram
    participant O as Owner in standard cmd.exe
    participant C as Compact encoded CMD entry
    participant B as Hash-verified outer bootstrap bytes
    participant R as Verified standard requester launcher
    participant P as One-shot local named pipe
    participant E as UAC elevated diagnostic child
    participant G as Pinned Git core executable
    participant H as Historical manifest-only parser
    O->>C: Paste exact reviewed command
    C->>C: Handle-open fixed bootstrap; verify hash; run those bytes in memory
    C->>B: Execute verified ScriptBlock
    B->>R: Verify module and launcher bytes; execute launcher ScriptBlock
    R->>R: Recheck token, checkout, inputs, hashes and paths
    R->>P: Create random protected first-instance local pipe
    R->>E: One RunAs launch after all deterministic gates pass
    E->>P: Authenticate requester PID/time/SID and elevated token
    E->>G: Four bounded read-only Git queries
    E->>H: Parse candidate and compare ReviewedCommitSha
    H-->>E: Bounded sanitized diagnostic
    E-->>P: Nonce-bound response and child exit status
    P-->>R: Validate exact fields, identities, hashes and exit agreement
    R-->>O: Non-authoritative diagnostic result
```

## Pinned bytes

Windows checkout-byte SHA-256 values for the changed launch sources:

| File | SHA-256 |
|---|---|
| `scripts/f2-acl/F2HistoricalManifestLaunch.psm1` | `06f117c6be29e3e150149087cb19323e83df20601b8d134f0bb02ec7335867d2` |
| `scripts/f2-acl/Start-F2HistoricalManifestDiagnostic.ps1` | `82e43661e8d0be7e03ca20a0329ce272219d1da46242cf3c0457aad4a5ec8775` |
| `scripts/f2-acl/Invoke-F2HistoricalManifestDiagnosticChild.ps1` | `78c8ea2a51d3eece2914ea87f18b46186f604a357671fb0607393801bca5609e` |
| `scripts/f2-acl/Invoke-F2HistoricalManifestDiagnostic.ps1` | `99505626679c75511e16d524c39dfd0ff0cbd27b3a0bd36d631cbadf2c1c9536` |
| `scripts/f2-acl/F2HistoricalManifestDiagnostic.psm1` | `4541338491269ac2bf409c5ba0c63d93d6a5e3fd9896c9d378c79dbea43ee7ee` |
| `docs/reviews/f2-g1-elevated-diagnostic-launch/OUTER_BOOTSTRAP.ps1` | `00c8e16b7044b0d54500268ca624254cf864d9b85ea405a61ee252b1cacffaa1` |
| `docs/reviews/f2-g1-elevated-diagnostic-launch/CMD_ENTRY_BOOTSTRAP.ps1` | `436aecdab7c4baaa7f80d93c95f2d15257f366e4a83beff78e3ae4753c993156` |
| `docs/reviews/f2-g1-elevated-diagnostic-launch/EXACT_UAC_COMMAND.txt` | `010705f7fe1bd1112cfddd0e64e33590731345d36ac7ca5047d56f078f370e75` |
| Pinned Git core executable | `1a0043555d254618f2d56c936c3d9a1fbfb878bc878416a133c346bc7835eda9` |

The full child process command line includes the PowerShell executable path, fixed switches, and a compact encoded bootstrap. It is capped at 3,600 characters before the single `Start-Process -Verb RunAs` call. The synthetic ShellExecute tests use `UseShellExecute = $true` with no `runas` verb; they do not invoke UAC.

The historical pins remain unchanged: candidate manifest `b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022`; historical updater `d9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2`; historical launcher `9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9`; protocol `66466fd15ce161fe2b522c77cfd6500845012480fc64890aa8435f54197eedc7`. The reviewed diagnostic module and retained baseline identity/digests are unchanged.

## Git executable selection

The former pin at `C:\Program Files\Git\cmd\git.exe` was a wrapper entry point, not the executable implementing Git. Git for Windows documents that wrapper as setting environment variables and starting the actual program; its documentation locates the 64-bit core at `mingw64\bin\git.exe`. The launch code now starts that core executable directly and pins its full path and SHA-256. The allowlist remains four local queries: repository top level, local origin, HEAD, and clean status.

The Git core's dependent DLLs are not individually hashed by this review. They remain a trust dependency on the installed Git for Windows tree under Program Files; this source-only task did not inspect that tree's ACLs or DLL inventory. See `SECURITY_BOUNDARIES.md` for this remaining limitation.

## Review files and evidence

- `CMD_ENTRY_BOOTSTRAP.ps1` is the compact entry template. The published command is its exact generated output with the two fixed values bound.
- `OUTER_BOOTSTRAP.ps1` is read as bytes and executed only as a hash-verified in-memory ScriptBlock.
- `SECURITY_BOUNDARIES.md` documents controls and residual risks.
- `VALIDATION_RESULTS.md` gives exact commands, assertion totals, parser checks, and describes the exact-head hosted Windows CI gate; the final run URL is available from the PR checks and handoff.
- `TEST_RUN_RESULTS.log` contains the complete sanitized stdout, stderr, and actual process exit code for each local Windows PowerShell 5.1 suite.
- `DEVELOPER_HANDOFF.md` gives commit, parent, changed paths, tests and stop conditions.
- `FILE_SHA256_MANIFEST.txt` covers the complete review package using Windows checkout bytes; the manifest excludes itself.

## Separate ChildAuthentication postmortem candidate

- [Incident postmortem](../f2-g1-child-auth-postmortem/INCIDENT_POSTMORTEM.md) preserves the supplied failure fields and PID-check result, maps the reviewed ChildAuthentication operations in execution order, and separates confirmed source behavior from the still-unknown incident cause.
- [Regression source](../f2-g1-child-auth-postmortem/Test-F2ChildAuthenticationClassification.ps1), [complete test record](../f2-g1-child-auth-postmortem/TEST_RESULTS.txt), and [developer handoff](../f2-g1-child-auth-postmortem/DEVELOPER_HANDOFF.md) are included in the checkout-byte manifest.
- Candidate correction commit: `78a3cb3089babdab520d7d17dda920de276dfbc6`; this exact command has not been executed or authorized.

## Result limits

An elevated diagnostic `PASS` requires a validated response labeled `TokenClass=ELEVATED` and child exit 0. A synthetic negative test rejects a `STANDARD`-labeled `PASS`. Even an elevated diagnostic `PASS` would not attest installation, ACL acceptance, or resolve the previous failure. No retry, recovery, rollback, updater entrypoint, or automatic process termination is present.
