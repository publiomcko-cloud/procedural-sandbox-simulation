# Installer publication test evidence

## Windows PowerShell 5.1 synthetic suite

Command executed from `C:\Dev\f2-g1-protected-install-prep`:

```powershell
& $env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Install-F2IcaclsProtectedPackage.ps1
```

Exit code: **0**. Summary: **22 assertions, 0 failures**.

Captured output:

```text
PASS: synthetic install succeeds in temporary directories without elevation
PASS: attestation covers four directories and seven package files plus the release manifest
PASS: package and external release manifest publish at the required relative layout
PASS: release manifest binds reviewed SHA, baseline identity and exactly seven package files
PASS: release manifest pins both evidence files and the source pin manifest
PASS: all published files and directories have exact protected ACLs and no reparse attributes
PASS: observed benign ProgramData child-create mask is accepted when isolated by protected child DACL
PASS: parent DELETE_CHILD grant is rejected
PASS: parent WRITE_DAC grant is rejected
PASS: parent WRITE_OWNER grant is rejected
PASS: parent GENERIC_ALL grant is rejected
PASS: unrecognized ordinary-user parent access mask is rejected
PASS: inheriting/unprotected file DACL fixture is rejected
PASS: synthetic reparse ancestor is rejected
PASS: preexisting destination collision fails closed without overwriting existing content
PASS: modified source package fails before publishing any protected destination
PASS: changed baseline evidence fails before publishing any protected destination
PASS: different Administrator requester SID fails closed before staging
PASS: different requester SID causes no package, release, or staging writes
PASS: modified installer is rejected before its synthetic protected write
PASS: bootstrap invokes script entrypoint from verified bytes after backing path changes
PASS: bootstrap rejects malformed pinned hashes
Assertions=22;Failures=0
TEST_EXIT_CODE=0
```

The different-SID, bootstrap tamper, and self-modifying-installer cases use synthetic data and temporary test files. They do not use an elevated token or write under Program Files, ProgramData, or G:.

## Windows PowerShell 5.1 parser

Executed with `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command <parser loop>` over:

- `Install-F2IcaclsProtectedPackage.ps1`
- `Invoke-F2VerifiedInstaller.ps1`
- `Test-Install-F2IcaclsProtectedPackage.ps1`

Result: all three files parsed successfully; **0 parser errors; exit code 0**.
