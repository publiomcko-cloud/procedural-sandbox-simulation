# Source-only validation record

## Scope and environment

- Windows PowerShell 5.1.22621.6133, standard/non-elevated token.
- No UAC, elevated child, protected updater, ACL change, live `icacls`, VM/Hyper-V/G:, native F2 workload, or protected write was invoked.
- The new pipe integration launches only ordinary same-token PowerShell fixture children. It does not invoke `Start-F2HistoricalManifestDiagnostic.ps1` with `-ExecuteApprovedProbe` and does not reach the RunAs call site.
- The Windows workflow skips `Test-F2AclProtectedReleaseUpdater.ps1` on this source branch so it cannot run the historical transaction test. The PR #68 review evidence verifier is also skipped here because it binds the prior PR to exact HEAD `c3d1280...`; it is not a verifier for this stacked review package.

## Non-elevated fixed-input verification

The production read-only source-check functions were called under Windows PowerShell 5.1. They passed for the exact configured roots:

| Check | Observed result |
|---|---|
| Requester token / PS version | PASS; Windows PowerShell 5.1, standard non-elevated token; no SID published |
| Production source root | PASS; exact commit `396c44965c90c08292ad2835f8317e81b6b9daaf`; clean; expected repository origin |
| Historical candidate root | PASS; exact commit `7f99bc10f3e2258d2340cea4e7ba1352022cbb6d`; clean; expected repository origin |
| Pinned Git executable | PASS; SHA-256 `7b7971dd13f0c3a284e538601f2f9770b3a87dfaccb5fb52d68141c67ed22364` |
| Historical updater source | PASS; SHA-256 `d9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2` |
| Historical launcher source | PASS; SHA-256 `9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9` |
| Historical diagnostic protocol | PASS; SHA-256 `66466fd15ce161fe2b522c77cfd6500845012480fc64890aa8435f54197eedc7` |
| Candidate manifest | PASS; SHA-256 `b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022` |

These are read-only identity/hash checks. They do not execute the historical updater or read protected ACL/VM state.

## Windows PowerShell 5.1 synthetic suites

Commands are relative to a clean checkout of this branch:

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2HistoricalManifestLaunch.ps1
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclCapture.Protocol.ps1
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclIcacls.Corroboration.ps1
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclIcacls.Runtime.ps1
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclEntrypointArguments.ps1
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2AclProtectedReleaseNativeHelper.ps1
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2ProtectedReleaseDiagnostics.ps1
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\scripts\f2-acl\Test-F2HistoricalManifestDiagnostic.ps1
```

The results below are the local Windows PowerShell 5.1 runs for the immutable launch source commit and its final review-package checks. Hosted Windows CI and complete job logs are linked from the draft PR checks.

| Suite | Assertions | Failures | Process exit |
|---|---:|---:|---:|
| Launch boundary / pipe / byte pin chain | 107 | 0 | 0 |
| ACL protocol | 152 | 0 | 0 |
| ACL corroboration | 118 | 0 | 0 |
| ACL runtime contract | 41 | 0 | 0 |
| Entrypoint arguments | 18 | 0 | 0 |
| Native helper TEMP fixtures | 20 | 0 | 0 |
| Protected-release diagnostic channel TEMP fixtures | 68 | 0 | 0 |
| Historical manifest parser-only regression | 40 | 0 | 0 |
| **Total** | **564** | **0** | **0** |

## Parser and whitespace validation

- Windows PowerShell 5.1 parser sweep: 29 files (28 tracked `scripts/f2-acl` PowerShell sources plus `OUTER_BOOTSTRAP.ps1`); 0 parse errors; exit 0.
- `git diff --check` and `git diff --cached --check`: pass on the source correction before final docs staging; both are rerun on the complete review package before publication.
- The checkout uses explicit `.gitattributes` rules: launch `.ps1` sources are CRLF, the launch `.psm1` and review package are LF. All SHA-256 values in `FILE_SHA256_MANIFEST.txt` are over actual Windows checkout bytes.

## Hosted CI

The draft PR's final immutable HEAD must pass the `F2 ACL source-only validation` Windows workflow. Its exact run URL and conclusion are recorded in the final PR body after GitHub completes the run. The older create-only updater transaction suite is intentionally skipped for this PR; this task forbids executing that updater. The exact-HEAD PR #68 evidence self-check is likewise not applicable to the stacked head.

## Remaining limits

No test here proves Windows UAC consent, a real medium-to-high named-pipe connection, WMI command-line availability for the elevated process, or behavior in the historical updater execution context. The actual read-only source-input check passed, but the launch checkout must be clean at the pinned source implementation commit before a future invocation; this review-package commit is documentation-only after that pinned commit. Do not interpret source tests or a diagnostic PASS as an explanation of the historical failure.
