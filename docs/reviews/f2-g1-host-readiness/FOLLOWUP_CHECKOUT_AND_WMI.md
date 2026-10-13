# F2 G1 non-elevated checkout and WMI readiness follow-up

**Disposition: BLOCKED_WITH_EVIDENCE**  
**Assessment date:** 2026-10-13  
**Scope:** Prepare the two authorized detached worktrees and attempt the permitted harmless same-token WMI observation. No UAC, RunAs, protected operation, source change, ACL change, VM/Hyper-V/G: action, baseline change, or merge occurred.

## Immutable pins and PR state

- Repository: `publiomcko-cloud/procedural-sandbox-simulation`
- PR #69 reviewed HEAD: `56a34d7899ba31b0d3fe6d3185435bc182ac453f`
- Executable implementation commit: `8c14cf97c9446e11b8afbd64196c3f4558d4c3c9`
- Implementation parent: `1f0ddfd26554f1302fc5815084d2adb3b24ea857`
- PR #68 base: `c3d1280f9905730eda8cff40865e8afbbb642367`
- PR #69 is still open, draft, unmerged, and still points to the reviewed HEAD.
- The preexisting source checkout remained clean at the expected origin and review HEAD.
- The exact published command SHA-256 remains `1f1d4f51025b853bc571728258ae220cb689be97bf7c7355a0094393c113706a`; the 15-entry checkout-byte manifest SHA-256 remains `742d55ad06bc12da80f834f29c3d5a86fc1f3fefbde5775fb3ee4b391aa42f69`.

## Authorized worktree creation and verification

Before creation, both requested paths were absent. The existing origin resolved to `https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git`; the immutable commits resolved locally; the relevant destination parents had no reparse points. I used detached worktrees only:

| Worktree | Canonical path | HEAD | Parent | Origin | State |
|---|---|---|---|---|---|
| Review | `C:\\Dev\\f2-g1-diagnostic-elevation-plan-review` | `56a34d7899ba31b0d3fe6d3185435bc182ac453f` | `8c14cf97c9446e11b8afbd64196c3f4558d4c3c9` | expected GitHub origin | detached, clean |
| Runtime | `C:\\Dev\\f2-g1-diagnostic-launch-runtime` | `8c14cf97c9446e11b8afbd64196c3f4558d4c3c9` | `1f0ddfd26554f1302fc5815084d2adb3b24ea857` | expected GitHub origin | detached, clean |

No existing data was overwritten, removed, relocated, or cleaned. Nine command/bootstrap/runtime pinned-file paths and their ancestors were checked; none was a reparse point.

All 15 review checkout-byte manifest entries still match. The runtime checkout files also match the reviewed pins:

| Runtime file | SHA-256 |
|---|---|
| `F2HistoricalManifestLaunch.psm1` | `06f117c6be29e3e150149087cb19323e83df20601b8d134f0bb02ec7335867d2` |
| `Start-F2HistoricalManifestDiagnostic.ps1` | `48b3f12dbc784e593a4ee5b468b3f005e6b6e1a53b1c09d542d0bfc2f9cdd83a` |
| `Invoke-F2HistoricalManifestDiagnosticChild.ps1` | `78c8ea2a51d3eece2914ea87f18b46186f604a357671fb0607393801bca5609e` |
| `Invoke-F2HistoricalManifestDiagnostic.ps1` | `99505626679c75511e16d524c39dfd0ff0cbd27b3a0bd36d631cbadf2c1c9536` |
| `F2HistoricalManifestDiagnostic.psm1` | `4541338491269ac2bf409c5ba0c63d93d6a5e3fd9896c9d378c79dbea43ee7ee` |

The command payload was decoded only as inert text. It still names the exact review worktree path, and its pinned outer bootstrap hash matches the file at that path. The command was not invoked.

The reviewed production `Get-F2LaunchRepositoryFacts` helper was run against the runtime worktree under a standard, non-elevated token (PowerShell 7.6.6 host): PASS for exact canonical root, origin, HEAD, clean status, and pinned Git executable. It used its four allowlisted read-only Git queries. `Get-F2LaunchTokenFacts` reported the current token was not elevated and not an administrator token.

## Actual WMI observation attempt

The earlier focused Windows PowerShell 5.1 launch suite remains reported as **128 assertions, 0 failures, exit 0**. It tests the production child-command builder and a harmless same-token ShellExecute fixture, but uses a synthetic process record for the command-line validator.

For this follow-up, I attempted one bounded Windows PowerShell 5.1 runner that would have:

1. Loaded the hash-pinned production launch module.
2. Called `New-F2LaunchChildInvocation` with a disposable TEMP-only script that sleeps briefly and exits.
3. Started that command with `UseShellExecute=$true`, an empty verb, and no RunAs.
4. Queried the real `Win32_Process` record while alive, checked PID/image/owner/argument quoting/payload, and called `Test-F2LaunchProcessCommandLine`.
5. Waited for the child’s normal exit and removed only its newly created TEMP fixture.

The command execution boundary rejected process creation **before the runner process started** (`CreateProcess ... Rejected: blocked by policy`). No fixture runner or child was created, and no alternate route was attempted. Consequently, no actual WMI command line was captured and no live comparison was made. There is no evidence of a mismatch; the required observation is simply **BLOCKED/UNKNOWN**.

## Git runtime dependency and historical attempt status

The Git core and four local DLL hashes are unchanged from the prior sanitized report at commit `2c19f161740b3efb1636134cd7f62b5c58da45e4`. The signed core executable remains distinguishable from the four unsigned local DLLs. No trustworthy local package/catalog evidence for those DLLs was found; their publisher provenance remains an explicit residual supply-chain risk. No provenance is inferred from version-resource strings.

No diagnostic UAC was initiated in the reviewed tasks or this follow-up. No relevant child was visible during the prior/current process checks. Older attempt history remains **UNKNOWN** because Security event 4688 was inaccessible and the available UAC event-log retention cannot prove a historical negative. This historical limitation is documented, not used as a hidden acceptance requirement. Any future single-use authorization requires a fresh owner declaration; any UAC prompt consumes it, and retry is not permitted.

## Gate decision

Checkout setup, fixed command binding, and source pins now pass. The actual WMI-versus-validator observation did not run because the environment rejected the permitted process creation. This follow-up is therefore **BLOCKED_WITH_EVIDENCE**, not `READY_FOR_EXPLICIT_OWNER_AUTHORIZATION`. No source correction is justified without observing a real mismatch.

The only safe next step for this gate is to obtain the actual same-token WMI observation through an execution environment that permits this exact harmless fixture, without using RunAs or another process-launch mechanism to evade the rejection. Git DLL provenance remains a residual risk for explicit owner disposition. No UAC, diagnostic, protected update, recovery, ACL change, VM/G: operation, or PR merge is authorized by this report.
