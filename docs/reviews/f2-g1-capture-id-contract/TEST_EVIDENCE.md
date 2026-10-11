# Source validation evidence

## Consolidated readiness audit — final source corrections

Environment: Windows PowerShell 5.1.22621.6133 on the owner host. The final local commands below ran without elevation. Installer integration cases use temporary synthetic fixtures. No actual UAC, protected installation, `icacls`, VM, G:, or ACL modification was performed. Fresh full stdout/diagnostic logs are published adjacent under the `*_CONSOLIDATED.log` names; each records the invocation, PowerShell version, assertion output and process exit.

| Exact command | Result | Complete log |
| --- | --- | --- |
| `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Dev\f2-g1-capture-id-contract-source\scripts\f2-acl\Test-F2AclCapture.Protocol.ps1` | Exit 0; 152 assertions; 0 failures. | `WINDOWS_POWERSHELL_5_1_PROTOCOL_CONSOLIDATED.log` |
| `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Dev\f2-g1-capture-id-contract-source\scripts\f2-acl\Test-F2AclIcacls.Corroboration.ps1` | Exit 0; 118 assertions; 0 failures. | `WINDOWS_POWERSHELL_5_1_CORROBORATION_CONSOLIDATED.log` |
| `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Dev\f2-g1-capture-id-contract-source\scripts\f2-acl\Test-F2AclIcacls.Runtime.ps1` | Exit 0; 35 assertions; 0 failures. | `WINDOWS_POWERSHELL_5_1_RUNTIME_CONSOLIDATED.log` |
| `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Dev\f2-g1-capture-id-contract\docs\reviews\f2-g1-capture-id-contract\Test-Install-F2IcaclsProtectedPackage.ps1` | Exit 0; 47 assertions; 0 failures. | `WINDOWS_POWERSHELL_5_1_INSTALL_CONSOLIDATED.log` |
| Windows PowerShell 5.1 `Language.Parser.ParseFile` over SourceRoot `scripts/f2-acl` and the review PowerShell files | Exit 0; 12 files; 0 parser errors. | `WINDOWS_POWERSHELL_5_1_CONSOLIDATED_PARSER.log` |

Total: **352 assertions, 0 failures**. The installer suite now covers the complete sanitized C:\ root fixture (including its inherit-only generic ACE), strict root-path binding, changed masks/principals/flags/owners, duplicates, unprotected DACLs, a writable non-root parent, both install-destination collisions, partial-stage failure, package and manifest attestation failures, wrong requester, baseline/source hash mismatch, bootstrap verified-byte behavior, and pure-string computation of the exact 11 pinned G: paths without a G: PowerShell drive.

The actual live read-only Windows PowerShell 5.1 parent validation passed for both Program Files and ProgramData. It also verified the unchanged baseline, requester/four-ACE mailbox contract, 11-record set, seven package bytes, destination absence, and zero staging collisions. Sanitized results are in `CONSOLIDATED_INSTALL_READINESS.md`; no raw SDDL or private SID is published.

The hosted Windows CI run at `e88144d15fb23ab58a2de4dc5dd0b1e281f1d3ca` passed protocol (152), corroboration (118), and runtime (35), then exposed that the runner has no G: PowerShell drive; run [38167667264](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38167667264), [job log 114553496773](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38167667264/job/114553496773). The next run at `b17be040f5d5e3c2105e0d83d1f5abce55d891f0` passed those same three suites but the installer fixture failed its strict `INSTALL_TARGET_PATH_NOT_CANONICAL` gate; see [run 38167926562](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38167926562), [job log 114554263540](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38167926562/job/114554263540). The test fixture now builds final synthetic destinations with `Path.GetFullPath`; the production canonical-path check remains strict. The corrected final-head CI result, job log and exact SHA will be added after rerun.

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
