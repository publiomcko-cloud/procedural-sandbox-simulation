[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:F2ApprovedInstallerPath = 'C:\Dev\f2-g1-protected-install-prep\Install-F2IcaclsProtectedPackage.ps1'
$script:F2ApprovedInstallerSha256 = '235aea7748c2c67b6c52996d5de4dd02a88709b46b96fff1710bd671b4fac0e4'
$script:F2InstallerMaximumBytes = 1048576

function Invoke-F2VerifiedInstallerCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstallerPath,
        [Parameter(Mandatory)][string]$ExpectedSha256
    )

    if ($ExpectedSha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'BOOTSTRAP_EXPECTED_HASH_INVALID' }

    # Read once, hash those exact bytes, decode those same bytes, and execute the
    # resulting script block. Never reopen the mutable installer path to execute it.
    $bytes = [IO.File]::ReadAllBytes($InstallerPath)
    if ($bytes.Length -lt 1 -or $bytes.Length -gt $script:F2InstallerMaximumBytes) {
        throw 'BOOTSTRAP_INSTALLER_SIZE_INVALID'
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actualHash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    if ($actualHash -cne $ExpectedSha256) { throw 'BOOTSTRAP_INSTALLER_HASH_MISMATCH' }

    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try { $source = $utf8.GetString($bytes) }
    catch { throw 'BOOTSTRAP_INSTALLER_ENCODING_INVALID' }
    if ($source.Length -gt 0 -and $source[0] -eq [char]0xFEFF) { $source = $source.Substring(1) }

    $verifiedScript = [ScriptBlock]::Create($source)
    & $verifiedScript
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($args.Count -ne 0) {
        [Console]::Error.WriteLine('F2_INSTALL_BOOTSTRAP: arguments are not accepted.')
        exit 2
    }
    try {
        Invoke-F2VerifiedInstallerCore -InstallerPath $script:F2ApprovedInstallerPath -ExpectedSha256 $script:F2ApprovedInstallerSha256
        exit 0
    } catch {
        [Console]::Error.WriteLine(('F2_INSTALL_BOOTSTRAP: ' + $_.Exception.Message))
        exit 1
    }
}
