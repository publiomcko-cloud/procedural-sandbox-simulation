# Installer publication test evidence

## Windows PowerShell 5.1 synthetic suite

Executed from the PR #51 review worktree (`C:\Dev\f2-g1-installer-evidence-review`):

```powershell
& $env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\docs\reviews\f2-g1-installer-evidence\Test-Install-F2IcaclsProtectedPackage.ps1
```

Exit code: **0**. Summary: **23 assertions, 0 failures**.

Captured output:

```text
PASS: production bootstrap pins the approved source installer path and digest
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
Assertions=23;Failures=0
TEST_EXIT_CODE=0
```

The fixed-path assertion verifies the production bootstrap constants equal `C:\Dev\f2-g1-protected-install-prep\Install-F2IcaclsProtectedPackage.ps1` and the independently approved installer SHA-256. Parameterized bootstrap tests remain synthetic. The different-SID, bootstrap tamper, and self-modifying-installer cases use synthetic data and temporary files; they do not use an elevated token or write under Program Files, ProgramData, or G:.

## Windows PowerShell 5.1 parser

Executed with Windows PowerShell 5.1 over the bootstrap, test, and unchanged installer:

```powershell
$files = @(
    '.\docs\reviews\f2-g1-installer-evidence\Invoke-F2VerifiedInstaller.ps1',
    '.\docs\reviews\f2-g1-installer-evidence\Test-Install-F2IcaclsProtectedPackage.ps1',
    '.\docs\reviews\f2-g1-installer-evidence\Install-F2IcaclsProtectedPackage.ps1'
)
foreach ($path in $files) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { $errors | ForEach-Object { Write-Error ($path + ': ' + $_.Message) }; exit 1 }
    Write-Output ('PASS PS5.1 parser: ' + $path)
}
```

Result: all three files parsed successfully; **0 parser errors; exit code 0**.
