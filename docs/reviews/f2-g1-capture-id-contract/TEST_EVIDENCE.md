# Validation evidence

Environment: Windows PowerShell 5.1 (`C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`) on the local Windows host. Tests are synthetic and non-elevated.

## Exact commands and results

| Command | Result |
| --- | --- |
| `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2AclIcacls.Corroboration.ps1` | Exit 0; 118 assertions; 0 failures. Full output: `WINDOWS_POWERSHELL_5_1_CORROBORATION_TEST.log`. |
| `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/f2-acl/Test-F2AclIcacls.Runtime.ps1` | Exit 0; 29 assertions; 0 failures. Full output: `WINDOWS_POWERSHELL_5_1_RUNTIME_TEST.log`. |
| `powershell.exe -NoProfile -ExecutionPolicy Bypass -File docs/reviews/f2-g1-capture-id-contract/Test-Install-F2IcaclsProtectedPackage.ps1` | Exit 0; 31 assertions; 0 failures. Full output: `WINDOWS_POWERSHELL_5_1_INSTALL_TEST.log`. |
| PowerShell `Language.Parser.ParseFile` sweep over the six tracked `scripts/f2-acl` `.ps1`/`.psm1` files and six package/test `.ps1`/`.psm1` review files | 12 files; 0 parser errors; exit 0. Output: `WINDOWS_POWERSHELL_5_1_PARSER.log`. |
| `git diff --check` | Run against the complete source-plus-review change before commit; result recorded below after final publication. |

The corroboration tests exercise distinct producer IDs passing, wrong mailbox ID, wrong expected and embedded payload CaptureIds, changed payload/integrity digests, missing and malformed data, and duplicate records. Runtime tests require both IDs and reject legacy v1 release schema. Installer tests validate the same distinction through the actual baseline reader and emitted v2 release manifest while preserving mailbox DACL, identity, completeness, package pins, destination, and fail-closed checks.

## GitHub CI

Workflow: `.github/workflows/f2-acl-source-only.yml` (`F2 ACL source-only validation`, `windows-latest`). This section is completed after the draft PR run is available. The workflow runs the Windows PowerShell 5.1 protocol, corroboration and runtime suites, parser validation, and `git diff --check`. The installer test is also run locally as shown above.

## Evidence limits

The tests use synthetic temporary fixtures. They do not run UAC, install into protected directories, invoke live `icacls`, inspect live host ACLs/tokens or Hyper-V state, start the VM, or write to G:. A passing run is not live ACL acceptance or installation approval.
