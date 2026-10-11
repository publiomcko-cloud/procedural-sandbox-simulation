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

- Windows PowerShell 5.1 `Language.Parser.ParseFile` sweep over all 9 tracked `scripts/f2-acl` PowerShell files and all 3 installer/bootstrap/test review files: 12 files, 0 parser errors, exit 0. Log: `WINDOWS_POWERSHELL_5_1_PARSER.log`.
- `git diff --check origin/security/f2-icacls-corroboration-issue48...HEAD`: passed after review package updates; exit 0.

## GitHub Windows CI

The workflow is `.github/workflows/f2-acl-source-only.yml` on `windows-latest`.

- Exact tested PR HEAD: `5c47672998209dfbacd9f59f260627bd69273750`.
- Run: [F2 ACL source-only validation #38150384900](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38150384900), conclusion `success`, exit 0.
- Windows PowerShell 5.1 protocol suite: 152 assertions, 0 failures; child exit 0.
- Corroboration suite: 118 assertions, 0 failures; child exit 0.
- Runtime suite: 35 assertions, 0 failures; child exit 0.
- Parser step: 9 tracked PowerShell files, 0 errors.
- `git diff --check`: passed.
- The complete hosted step log is retrievable at [job 114502430594](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38150384900/job/114502430594).

The final commit after this run contains only review-manifest metadata and this CI reference. It does not alter production source, installer, bootstrap, tests, or pins. The run covers the exact source-bearing SHA plus those evidence-only edits.

## Scope and limits

This validates synthetic/source behavior only. No UAC, protected installation, live `icacls`, live ACL or token query, VM/Hyper-V query, G: write, VM start, or native workload was performed. A passing source suite is not installation authorization or live ACL acceptance.
