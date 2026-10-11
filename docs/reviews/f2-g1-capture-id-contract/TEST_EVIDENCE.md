# Source validation evidence

Environment: Windows PowerShell 5.1. All tests use synthetic fixtures and temporary local files. Captured text logs use LF line endings for repository whitespace checks; test messages and assertion summaries are preserved.

## Local Windows PowerShell 5.1 suites

| Exact command | Result | Full log |
| --- | --- | --- |
| `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2AclCapture.Protocol.ps1` | Exit 0; 152 assertions; 0 failures. | `WINDOWS_POWERSHELL_5_1_PROTOCOL_TEST.log` |
| `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2AclIcacls.Corroboration.ps1` | Exit 0; 118 assertions; 0 failures on immediate rerun. One initial execution had 1 transient synthetic child-process capture assertion failure; the exact failure is retained separately. | `WINDOWS_POWERSHELL_5_1_CORROBORATION_TEST.log`; `WINDOWS_POWERSHELL_5_1_CORROBORATION_TRANSIENT_FAILURE.log` |
| `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2AclIcacls.Runtime.ps1` | Exit 0; 35 assertions; 0 failures. Includes actual disk-loading function with release-provider hook disabled; v2 success; downstream seven-file contract; rejection of v1, malformed JSON and missing identities. | `WINDOWS_POWERSHELL_5_1_RUNTIME_TEST.log` |
| `powershell.exe -NoProfile -ExecutionPolicy Bypass -File docs/reviews/f2-g1-capture-id-contract/Test-Install-F2IcaclsProtectedPackage.ps1` | Exit 0; 31 assertions; 0 failures. | `WINDOWS_POWERSHELL_5_1_INSTALL_TEST.log` |

The corroboration suite's single initial failure was `bounded process runner captures stdout, stderr, PID, exit and hashes`; the unchanged immediate rerun passed. No source was modified to mask or work around it. CI results below provide an additional run of the production suites.

## Parser and whitespace checks

- Windows PowerShell 5.1 `Language.Parser.ParseFile` sweep over 6 tracked `scripts/f2-acl` PowerShell files and 3 installer/bootstrap/test files: 9 files, 0 parser errors, exit 0. Log: `WINDOWS_POWERSHELL_5_1_PARSER.log`.
- `git diff --check origin/security/f2-icacls-corroboration-issue48...HEAD`: passed after review package updates; exit 0.

## GitHub Windows CI

The workflow is `.github/workflows/f2-acl-source-only.yml` on `windows-latest`. The exact final PR SHA, Actions run URL, job result, suite summaries, parser result, and workflow log link are recorded here after the pushed review commit completes CI.

## Scope and limits

This validates synthetic/source behavior only. No UAC, protected installation, live `icacls`, live ACL or token query, VM/Hyper-V query, G: write, VM start, or native workload was performed. A passing source suite is not installation authorization or live ACL acceptance.
