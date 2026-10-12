[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$git = Get-Command git.exe -ErrorAction SilentlyContinue
$cim = Get-Command Get-CimInstance -ErrorAction SilentlyContinue
$cimModuleInstalled = @(Get-Module -ListAvailable CimCmdlets).Count -gt 0
Write-Output ([pscustomobject]@{
    PowerShell = $PSVersionTable.PSVersion.ToString()
    Edition = $PSVersionTable.PSEdition
    GitAvailable = ($null -ne $git)
    GitPath = if ($null -ne $git) { $git.Source } else { $null }
    CimCmdletAvailable = ($null -ne $cim)
    CimModuleName = if ($null -ne $cim) { $cim.ModuleName } else { $null }
    CimModuleInstalled = $cimModuleInstalled
} | ConvertTo-Json -Compress)
