# F2 G1 diagnostic launch validation

## Scope

Validation used Windows PowerShell 5.1.22621.6133 for the synthetic suites. No UAC, `RunAs`, elevated probe, protected updater, live `icacls`, ACL/VM/Hyper-V/G: access, native workload, or protected write was performed. `TEST_RUN_RESULTS.log` preserves each suite's complete sanitized output and actual child exit code. The tests use disposable TEMP fixtures; ShellExecute fixtures set `UseShellExecute = $true` with an empty verb and never request elevation.

The corrected launch implementation is commit `8c14cf97c9446e11b8afbd64196c3f4558d4c3c9`, parent `1f0ddfd26554f1302fc5815084d2adb3b24ea857`. The review package is on top of that implementation commit. Runtime checkout and review checkout paths are separate as described in `README.md`.

## Corrected launch gates

| Gate | Result |
|---|---|
| Exact standard-token CMD invocation (PR #69 reviewed baseline) | 4,683 characters; below the 8,191-character CMD limit; no command chaining or expansion metacharacters. The separate PR #71 candidate command is 4,655 characters, as recorded in its README and exact command file. |
| CMD entry source equivalence | Pass; the encoded command is generated from `CMD_ENTRY_BOOTSTRAP.ps1` with the exact outer path and SHA-256 bound |
| Outer bootstrap | Opens the fixed file, checks its handle-resolved path and SHA-256, then invokes a ScriptBlock created from those same bytes |
| Elevated child argument construction | Maximum-shaped full command line tested at or below 3,600 characters; the production builder rejects the smaller injected 512-character limit |
| Elevated child bootstrap | Encoded bytes exactly match the production template after binding path, digest, pipe, requester PID/creation time and source commit |
| Harmless ShellExecute integration | Pass using temporary scripts and `UseShellExecute = $true`; no `runas` verb and no UAC |
| Successful diagnostic token label | `ELEVATED` required; synthetic `STANDARD`-labeled PASS rejected |
| Git provenance | Direct pinned core binary path/hash; four read-only queries retained; wrapper is not in the execution path |
| Source immutability | Historical source, parser, candidate, diagnostic module and retained-baseline identity/digest pins remain unchanged |

## Windows PowerShell 5.1 suites

Each command was run in a fresh `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File <suite>` child. The exact command lines, sanitized output, assertion summaries and actual exit codes are in `TEST_RUN_RESULTS.log`.

| Suite | Assertions | Failures | Exit |
|---|---:|---:|---:|
| Launch boundary, command construction, byte pins and pipe | 128 | 0 | 0 |
| ACL protocol | 152 | 0 | 0 |
| ACL corroboration | 118 | 0 | 0 |
| ACL runtime contract | 41 | 0 | 0 |
| Entrypoint arguments | 18 | 0 | 0 |
| Native helper TEMP fixtures | 20 | 0 | 0 |
| Protected-release diagnostics TEMP fixtures | 68 | 0 | 0 |
| Historical manifest parser-only regression | 40 | 0 | 0 |
| **Total** | **585** | **0** | **0** |

The focused launch suite command was:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2HistoricalManifestLaunch.ps1
```

Observed output: `Assertions=128;Failures=0`; child process exit code `0`.

During fixture development, the directory-junction cleanup initially used `Remove-Item` and triggered an interactive prompt under `-NonInteractive`. The test now removes only that exact TEMP junction via `Directory.Delete(path, false)`, which unlinks the reparse entry without recursing into its target. The corrected regression then passed; no protected or user data was touched.

## Parser and diff validation

- Windows PowerShell 5.1 `Parser::ParseFile` sweep: all 28 `scripts/f2-acl` `.ps1`/`.psm1` files plus `OUTER_BOOTSTRAP.ps1` and the CMD-entry template; 30 files, 0 parse errors, exit 0.
- `git diff --check`: pass; rerun after staging the complete final package before commit.
- The review-package `.ps1` files use LF by `.gitattributes`; `scripts/f2-acl` files use CRLF except the launch module's explicit LF rule. The command is plain ASCII plus line ending. Package hashes are physical Windows checkout bytes and appear in `FILE_SHA256_MANIFEST.txt`.

## Hosted Windows CI history

The baseline PR #69 run `38471926228` succeeded, including the protected-release diagnostics step with `Assertions=68;Failures=0` and `F2ProtectedDiagnosticsTestProcessExit=0`. The later PR #71 run `38559236368` failed in the same unchanged step: `Assertions=68;Failures=28`, process exit `1`. This is not a passing CI result for PR #71. The failure logs show a first child-integration failure followed by repeated timeout/missing-exit results. The failed test/workflow do not load the PR #71 launcher file changed here. No workflow rerun was performed for this correction; see the postmortem and `TEST_RESULTS.txt` for exact log evidence and remaining uncertainty.

The workflow still contains the complete compatible suites and parser checks. It intentionally skips the PR #68 exact-HEAD evidence verifier and the historical updater transaction suite; neither validates this stacked branch, and executing the updater is prohibited.

## PR #71 source-only postmortem correction

- Initial classification source candidate: `78a3cb3089babdab520d7d17dda920de276dfbc6`; its underlying incident cause remains UNKNOWN.
- Follow-up type-preservation correction: `41e9c34843815dbd69770de36c9525f44e218e1f`, parent `58991441cfd6ca21cf7bc3cb2fda5f69b97a8633`. The Windows checkout-byte hash for `Start-F2HistoricalManifestDiagnostic.ps1` is `db4ba16e35af4710ce1f9a7e5082052348d61d787d8fbb38327736a79c3630b1`.
- Focused Windows PowerShell 5.1 in-memory regression: 48 assertions, 0 failures, exit 0. It covers Boolean, String, PSCustomObject, production frame `Byte[]`, in-memory Stream.Write/Read, no-output return and safe exception classification. No child processes or UAC were started.
- The old launch command remains pinned to the initial source candidate and is not valid for the follow-up source bytes. No execution is authorized.
- Exact PR #71 CI run `38559236368` failed the unchanged diagnostics suite at 68 assertions / 28 failures / exit 1. Earlier PR #69 run `38471926228` passed the same step at 68 / 0 / exit 0. The failure source remains UNKNOWN; neither full CI nor the failing test was rerun.
- Launcher and regression parser checks: 0 errors; `git diff --check`: pass for the published correction.
- No UAC/RunAs, live WMI query, process inspection, protected operation, VM/Hyper-V/G: action, ACL change, baseline change, workflow rerun, or merge occurred.

## Limits

The tests prove generated launch arguments, verified-byte ScriptBlock behavior and harmless same-token ShellExecute fixtures, not actual UAC, cross-integrity named-pipe operation, Windows consent behavior, real elevated command-line visibility, or alternate-account rejection. Git for Windows runtime DLLs are not individually pinned; the installed Git tree remains an explicitly documented trust dependency. A diagnostic PASS is non-authoritative and does not establish the cause of the prior elevated failure or installation/ACL acceptance.
