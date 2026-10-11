# F2 G1 consolidated source and host-readiness evidence

## Scope

All source tests below ran under Windows PowerShell 5.1.22621.6133. Installer tests used temporary synthetic fixtures. The separate host checks were non-elevated and read-only. No UAC, installation, live `icacls`, ACL modification, VM/Hyper-V access, G: operation, baseline modification, native workload, or PR merge occurred.

## Local Windows PowerShell 5.1 validation

| Exact command | Result | Complete log |
| --- | --- | --- |
| `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Dev\f2-g1-capture-id-contract-source\scripts\f2-acl\Test-F2AclCapture.Protocol.ps1` | Exit 0; 152 assertions; 0 failures. | `WINDOWS_POWERSHELL_5_1_PROTOCOL_CONSOLIDATED.log` |
| `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Dev\f2-g1-capture-id-contract-source\scripts\f2-acl\Test-F2AclIcacls.Corroboration.ps1` | Exit 0; 118 assertions; 0 failures. | `WINDOWS_POWERSHELL_5_1_CORROBORATION_CONSOLIDATED.log` |
| `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Dev\f2-g1-capture-id-contract-source\scripts\f2-acl\Test-F2AclIcacls.Runtime.ps1` | Exit 0; 35 assertions; 0 failures. | `WINDOWS_POWERSHELL_5_1_RUNTIME_CONSOLIDATED.log` |
| `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Dev\f2-g1-capture-id-contract\docs\reviews\f2-g1-capture-id-contract\Test-Install-F2IcaclsProtectedPackage.ps1` | Exit 0; 47 assertions; 0 failures. | `WINDOWS_POWERSHELL_5_1_INSTALL_CONSOLIDATED.log` |
| Windows PowerShell 5.1 `Language.Parser.ParseFile` over SourceRoot PowerShell files and review PowerShell files | Exit 0; 12 files; 0 parser errors. | `WINDOWS_POWERSHELL_5_1_CONSOLIDATED_PARSER.log` |

Total: **352 assertions, 0 failures**. The installer tests cover the exact sanitized `C:\` root ACL profile and adversarial variants, a writable non-root parent, destination/staging collisions, partial-stage failure, baseline/source hash mismatches, requester mismatch, bootstrap verified-byte behavior, package/manifest attestation failures, and path generation for the pinned G: targets without requiring a G: PowerShell drive.

The non-elevated read-only host audit separately verified the production source checkout and seven package pins, retained baseline hashes and separate IDs, 11-record completeness, original requester/four-ACE mailbox contract, destination absence, and parent-chain validation for `C:\`, Program Files, and ProgramData. Sanitized findings and all gate dispositions are in `CONSOLIDATED_INSTALL_READINESS.md`; raw SDDL and private SIDs are not published.

## GitHub Windows CI

Workflow: `.github/workflows/f2-acl-source-only.yml`, runner `windows-latest`.

- Source-bearing SHA: `409f3103efa56ea813edc612d2c2de29f5d3ef8c`; run [38168511145](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38168511145), job [114555982388](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38168511145/job/114555982388), completed successfully.
- Exact evidence-finalization SHA: `5f1bfd22aca7ac3a7b16e6a859f77eced12982d0`; run [38168759143](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38168759143), job [114556718078](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38168759143/job/114556718078), completed successfully.
- Protocol: 152 assertions, 0 failures, process exit 0.
- Corroboration: 118 assertions, 0 failures, process exit 0.
- Runtime: 35 assertions, 0 failures, process exit 0.
- Installer/bootstrap: 47 assertions, 0 failures, process exit 0.
- Hosted PowerShell parser: 9 tracked source files, 0 parser errors.
- `git diff --check`: passed.

Earlier failed hosted runs are preserved as diagnostic history: [38167667264](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38167667264), [38167926562](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38167926562), and [38168148807](https://github.com/publiomcko-cloud/procedural-sandbox-simulation/actions/runs/38168148807). Their failures were synthetic fixture portability/normalization issues. The corrected tests passed in run 38168511145; production identity, path, and reparse checks were not relaxed.

The evidence-finalization run checked the pushed review package and source at its exact SHA. A subsequent commit may update this document with the run reference; such a documentation-only change does not alter the tested PowerShell source, installer, bootstrap, tests, or package pins.

## Limits and next gates

The audit supports independent review of the source correction and sanitized parent analysis. UAC identity/consent, protected installation, and actual installed-state attestation remain **UNKNOWN / NOT RUN**. This evidence is not an installation authorization or an ACL security acceptance. After independent review, changed executable bytes require fresh owner authorization before any protected installation.
