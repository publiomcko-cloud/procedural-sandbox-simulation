[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = [IO.Path]::GetFullPath($SourceRoot)
$manifestFile = Get-Item -LiteralPath $ManifestPath -Force -ErrorAction Stop
if ($manifestFile.PSIsContainer -or ($manifestFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'CandidateManifestMustBeRegularFile.'
}
$runtimePath = Join-Path $source 'scripts\f2-acl\F2AclIcacls.Runtime.psm1'
Import-Module -Name $runtimePath -Force -ErrorAction Stop
$runtime = Get-Module F2AclIcacls.Runtime
if ($null -eq $runtime) { throw 'RuntimeModuleUnavailable.' }
$runtime.SessionState.PSVariable.Set('F2RuntimeReleasePath', [IO.Path]::GetFullPath($manifestFile.FullName))
$runtime.SessionState.PSVariable.Set('F2RuntimeReleaseProvider', $null)
$runtime.SessionState.PSVariable.Set('F2RuntimeCurrentCommitProvider', $null)
$invokePrivate = {
    param([string]$Name, [object[]]$Arguments = @())
    $runtime.SessionState.PSVariable.Set('__ReviewFunction', $Name)
    $runtime.SessionState.PSVariable.Set('__ReviewArguments', $Arguments)
    $call = [scriptblock]::Create('& $script:__ReviewFunction @script:__ReviewArguments')
    return @($runtime.Invoke($call, @()))[0]
}.GetNewClosure()

try {
    $manifest = & $invokePrivate 'Get-F2RuntimeReleaseManifest' @()
    $package = & $invokePrivate 'Test-F2RuntimeReleasePackage' @($manifest, 'Source')
    $bytes = [IO.File]::ReadAllBytes($manifestFile.FullName)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $manifestSha = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    [pscustomobject]@{
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        SourceRoot = $source
        Schema = [string]$manifest.Schema
        ReviewedCommitSha = [string]$manifest.ReviewedCommitSha
        SourcePinsManifestSha256 = [string]$manifest.SourcePinsManifestSha256
        FileCount = [int]$package.Files
        ManifestSha256 = $manifestSha
        Pass = [bool]$package.Pass
    } | ConvertTo-Json -Compress
    if (-not $package.Pass) { exit 1 }
    exit 0
}
catch {
    [Console]::Error.WriteLine(('CandidateReleaseValidationFailed:' + $_.Exception.GetType().Name + ':' + $_.Exception.Message))
    exit 1
}
