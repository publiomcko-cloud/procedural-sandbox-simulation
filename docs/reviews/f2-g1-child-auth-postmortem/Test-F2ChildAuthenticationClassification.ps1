[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:assertions = 0

function Assert-Equal {
    param([string]$Name, [object]$Expected, [object]$Actual)
    $script:assertions++
    if ($Expected -cne $Actual) { throw ('ASSERTION_FAILED:{0}: expected={1}; actual={2}' -f $Name,$Expected,$Actual) }
    Write-Output ('PASS {0}' -f $Name)
}

function Get-ParsedSource {
    param([string]$Path)
    $tokens = $null
    $parseErrors = $null
    $sourceAst = [System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count -ne 0) { throw ('SOURCE_PARSE_FAILED:{0}' -f [IO.Path]::GetFileName($Path)) }
    return $sourceAst
}

function Get-FunctionNode {
    param([System.Management.Automation.Language.Ast]$Ast,[string]$Name)
    $node = $Ast.Find({ param($item) $item -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $item.Name -ceq $Name },$true)
    if ($null -eq $node) { throw ('FUNCTION_NOT_FOUND:{0}' -f $Name) }
    return $node
}

function Invoke-ClassifierCase {
    param([scriptblock]$Action)
    try { & $Action; return 'NO_THROW' }
    catch { return Get-F2LaunchSafeCode -Record $_ }
}

function Get-SyntheticErrorClassCode {
    param([System.Exception]$Exception)
    try { throw $Exception }
    catch { return Get-F2LaunchSafeCode -Record $_ }
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$launcherPath = Join-Path $repoRoot 'scripts\f2-acl\Start-F2HistoricalManifestDiagnostic.ps1'
$modulePath = Join-Path $repoRoot 'scripts\f2-acl\F2HistoricalManifestLaunch.psm1'
$launcherAst = Get-ParsedSource -Path $launcherPath
$moduleAst = Get-ParsedSource -Path $modulePath

$functionSpecs = @(
    @{ Ast = $launcherAst; Name = 'Get-F2LaunchSafeCode' },
    @{ Ast = $launcherAst; Name = 'Invoke-F2LaunchChildAuthOperation' },
    @{ Ast = $moduleAst; Name = 'Get-F2LaunchUtf8' },
    @{ Ast = $moduleAst; Name = 'ConvertTo-F2LaunchFrame' },
    @{ Ast = $moduleAst; Name = 'Test-F2LaunchProcessCommandLine' },
    @{ Ast = $moduleAst; Name = 'Test-F2LaunchCommandLineRecord' },
    @{ Ast = $moduleAst; Name = 'Test-F2LaunchPeerFacts' },
    @{ Ast = $moduleAst; Name = 'Test-F2LaunchHello' }
)
foreach ($spec in $functionSpecs) { Invoke-Expression (Get-FunctionNode -Ast $spec.Ast -Name $spec.Name).Extent.Text }
$script:F2LaunchMaxRecordBytes = 8192

function Get-TypeNameOrNull {
    param([object]$Value)
    if ($null -eq $Value) { return '<null>' }
    return $Value.GetType().FullName
}

$wrappedBoolean = Invoke-F2LaunchChildAuthOperation -FailureCode 'LAUNCH_CHILD_REQUEST_BUILD_FAILED' -Operation { [bool]$true }
Assert-Equal 'Operation wrapper preserves Boolean type' 'System.Boolean' (Get-TypeNameOrNull $wrappedBoolean)
Assert-Equal 'Operation wrapper preserves Boolean value' $true $wrappedBoolean
$wrappedString = Invoke-F2LaunchChildAuthOperation -FailureCode 'LAUNCH_CHILD_REQUEST_BUILD_FAILED' -Operation { [string]'frame-ready' }
Assert-Equal 'Operation wrapper preserves String type' 'System.String' (Get-TypeNameOrNull $wrappedString)
Assert-Equal 'Operation wrapper preserves String value' 'frame-ready' $wrappedString
$wrappedObject = Invoke-F2LaunchChildAuthOperation -FailureCode 'LAUNCH_CHILD_REQUEST_BUILD_FAILED' -Operation { [pscustomobject]@{ Marker = 'frame-ready' } }
Assert-Equal 'Operation wrapper preserves PSCustomObject type' 'System.Management.Automation.PSCustomObject' (Get-TypeNameOrNull $wrappedObject)
Assert-Equal 'Operation wrapper preserves PSCustomObject property' 'frame-ready' $wrappedObject.Marker

$frameJson = '{"schema":"synthetic-frame-v1"}'
$directFrame = ConvertTo-F2LaunchFrame -Json $frameJson
$wrappedFrame = Invoke-F2LaunchChildAuthOperation -FailureCode 'LAUNCH_CHILD_REQUEST_BUILD_FAILED' -Operation { ConvertTo-F2LaunchFrame -Json $frameJson }
Assert-Equal 'Production frame converter returns Byte[]' 'System.Byte[]' (Get-TypeNameOrNull $directFrame)
Assert-Equal 'Operation wrapper preserves production Byte[] frame type' 'System.Byte[]' (Get-TypeNameOrNull $wrappedFrame)
Assert-Equal 'Operation wrapper preserves exact production frame bytes' ([Convert]::ToBase64String($directFrame)) ([Convert]::ToBase64String($wrappedFrame))

$memoryStream = New-Object System.IO.MemoryStream
$streamWriteResult = Invoke-F2LaunchChildAuthOperation -FailureCode 'LAUNCH_CHILD_REQUEST_WRITE_FAILED' -Operation {
    $memoryStream.Write($wrappedFrame,0,$wrappedFrame.Length)
    $memoryStream.Flush()
}
Assert-Equal 'Stream.Write and Flush operation returns no pipeline value' '<null>' (Get-TypeNameOrNull $streamWriteResult)
$memoryStream.Position = 0
$streamReadCount = 0
$streamReadFrame = Invoke-F2LaunchChildAuthOperation -FailureCode 'LAUNCH_CHILD_RESPONSE_READ_FAILED' -Operation {
    $readBuffer = New-Object byte[] $wrappedFrame.Length
    $script:streamReadCount = $memoryStream.Read($readBuffer,0,$readBuffer.Length)
    ,$readBuffer
}
Assert-Equal 'Stream.Read fills the complete production frame' $wrappedFrame.Length $script:streamReadCount
Assert-Equal 'Stream.Read roundtrip preserves Byte[] type' 'System.Byte[]' (Get-TypeNameOrNull $streamReadFrame)
Assert-Equal 'Stream.Read roundtrip preserves exact frame bytes' ([Convert]::ToBase64String($directFrame)) ([Convert]::ToBase64String($streamReadFrame))
$memoryStream.Dispose()
$noOutputResult = Invoke-F2LaunchChildAuthOperation -FailureCode 'LAUNCH_CHILD_REQUEST_WRITE_FAILED' -Operation { [void]$true }
Assert-Equal 'No-output operation remains null' '<null>' (Get-TypeNameOrNull $noOutputResult)

Assert-Equal 'Known allowlisted pipe timeout stays specific' 'LAUNCH_PIPE_TIMEOUT' (Get-SyntheticErrorClassCode -Exception (New-Object InvalidOperationException 'LAUNCH_PIPE_TIMEOUT'))
Assert-Equal 'GetNamedPipeClientProcessId Win32Exception class collapses to generic' 'LAUNCH_UNCLASSIFIED_FAILURE' (Get-SyntheticErrorClassCode -Exception (New-Object ComponentModel.Win32Exception 5))
Assert-Equal 'GetProcessById missing-process ArgumentException class collapses to generic' 'LAUNCH_UNCLASSIFIED_FAILURE' (Get-SyntheticErrorClassCode -Exception (New-Object ArgumentException 'synthetic'))
Assert-Equal 'Process.StartTime InvalidOperationException class collapses to generic' 'LAUNCH_UNCLASSIFIED_FAILURE' (Get-SyntheticErrorClassCode -Exception (New-Object InvalidOperationException 'synthetic'))
Assert-Equal 'Process.MainModule Win32Exception class collapses to generic' 'LAUNCH_UNCLASSIFIED_FAILURE' (Get-SyntheticErrorClassCode -Exception (New-Object ComponentModel.Win32Exception 5))
Assert-Equal 'RunAsClient IOException class collapses to generic' 'LAUNCH_UNCLASSIFIED_FAILURE' (Get-SyntheticErrorClassCode -Exception (New-Object IO.IOException 'synthetic'))
Assert-Equal 'RunAsClient ObjectDisposedException class collapses to generic' 'LAUNCH_UNCLASSIFIED_FAILURE' (Get-SyntheticErrorClassCode -Exception (New-Object ObjectDisposedException 'synthetic'))

$malformedJsonCode = Invoke-ClassifierCase { '{' | ConvertFrom-Json -ErrorAction Stop | Out-Null }
Assert-Equal 'Malformed hello JSON class collapses to generic' 'LAUNCH_UNCLASSIFIED_FAILURE' $malformedJsonCode

function Get-CimInstance {
    [CmdletBinding()]
    param([string]$ClassName,[string]$Filter)
    throw (New-Object UnauthorizedAccessException 'synthetic WMI provider failure')
}
$wmiMatched = Test-F2LaunchProcessCommandLine -ProcessId 39732 -ExpectedImagePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -ExpectedEncodedCommand 'QQ=='
Assert-Equal 'WMI query failure is conservatively rejected' $false $wmiMatched
$wmiOuterCode = Invoke-ClassifierCase {
    if (-not $wmiMatched) { throw 'LAUNCH_CHILD_COMMAND_MISMATCH' }
}
Assert-Equal 'WMI query failure follows explicit command-mismatch branch' 'LAUNCH_CHILD_COMMAND_MISMATCH' $wmiOuterCode

$malformedHelloCode = Invoke-ClassifierCase {
    $badHello = [pscustomobject][ordered]@{ Schema='f2-g1-diagnostic-launch-hello-v1'; ProcessId='not-an-int'; StartUtcTicks='not-a-long' }
    [void](Test-F2LaunchHello -Hello $badHello -ExpectedPid 39732 -ExpectedStartUtcTicks 1)
}
Assert-Equal 'Malformed hello numeric fields fail closed and classify generic' 'LAUNCH_UNCLASSIFIED_FAILURE' $malformedHelloCode

$peerAccepted = Test-F2LaunchPeerFacts -ExpectedPid 39732 -ExpectedStartUtcTicks 11 -ObservedPid 39732 -ObservedStartUtcTicks 11 -CommandLineMatches $false -TokenMatches $true
Assert-Equal 'Peer fact mismatch rejects child' $false $peerAccepted
$peerCode = Invoke-ClassifierCase { if (-not $peerAccepted) { throw 'LAUNCH_CHILD_COMMAND_MISMATCH' } }
Assert-Equal 'Peer fact mismatch returns allowlisted command mismatch' 'LAUNCH_CHILD_COMMAND_MISMATCH' $peerCode

$wrappedWin32Code = Invoke-ClassifierCase {
    Invoke-F2LaunchChildAuthOperation -FailureCode 'LAUNCH_PIPE_CLIENT_ID_QUERY_FAILED' -Operation { throw (New-Object ComponentModel.Win32Exception 5) }
}
Assert-Equal 'Operation wrapper classifies native client-PID failure' 'LAUNCH_PIPE_CLIENT_ID_QUERY_FAILED' $wrappedWin32Code

$wrappedProcessCode = Invoke-ClassifierCase {
    Invoke-F2LaunchChildAuthOperation -FailureCode 'LAUNCH_CHILD_PROCESS_IDENTITY_QUERY_FAILED' -Operation { throw (New-Object InvalidOperationException 'synthetic') }
}
Assert-Equal 'Operation wrapper classifies process identity failure' 'LAUNCH_CHILD_PROCESS_IDENTITY_QUERY_FAILED' $wrappedProcessCode

$preservedPipeCode = Invoke-ClassifierCase {
    Invoke-F2LaunchChildAuthOperation -FailureCode 'LAUNCH_CHILD_HELLO_READ_FAILED' -Operation { throw 'LAUNCH_PIPE_TIMEOUT' }
}
Assert-Equal 'Operation wrapper preserves an existing allowlisted timeout' 'LAUNCH_PIPE_TIMEOUT' $preservedPipeCode

$actionRan = $false
$unlistedCode = Invoke-ClassifierCase {
    Invoke-F2LaunchChildAuthOperation -FailureCode 'UNLISTED_FAILURE_CODE' -Operation { $script:actionRan = $true }
}
Assert-Equal 'Unlisted operation failure codes are rejected' 'LAUNCH_UNCLASSIFIED_FAILURE' $unlistedCode
Assert-Equal 'Rejected code prevents operation execution' $false $actionRan

$launcherText = [IO.File]::ReadAllText($launcherPath)
$requiredCallsiteCodes = @(
    'LAUNCH_PIPE_CLIENT_ID_QUERY_FAILED',
    'LAUNCH_CHILD_PROCESS_IDENTITY_QUERY_FAILED',
    'LAUNCH_CHILD_COMMAND_CHECK_FAILED',
    'LAUNCH_CHILD_PEER_CHECK_FAILED',
    'LAUNCH_CHILD_IMAGE_PATH_INVALID',
    'LAUNCH_CHILD_HELLO_READ_FAILED',
    'LAUNCH_CHILD_HELLO_JSON_INVALID',
    'LAUNCH_CHILD_HELLO_VALIDATION_FAILED',
    'LAUNCH_CHILD_TOKEN_IMPERSONATION_FAILED',
    'LAUNCH_CHILD_TOKEN_VALIDATION_FAILED',
    'LAUNCH_CHILD_REQUEST_BUILD_FAILED',
    'LAUNCH_CHILD_REQUEST_WRITE_FAILED',
    'LAUNCH_CHILD_RESPONSE_READ_FAILED',
    'LAUNCH_CHILD_RESPONSE_JSON_INVALID',
    'LAUNCH_CHILD_EXIT_WAIT_FAILED',
    'LAUNCH_CHILD_EXIT_CODE_UNAVAILABLE'
)
foreach ($code in $requiredCallsiteCodes) {
    $needle = ('Invoke-F2LaunchChildAuthOperation -FailureCode ''{0}''' -f $code)
    Assert-Equal ('Production stage has bounded mapping: {0}' -f $code) $true $launcherText.Contains($needle)
}

Write-Output ('ASSERTIONS={0}; FAILURES=0; CHILD_PROCESSES_STARTED=0; UAC_ATTEMPTS=0' -f $script:assertions)
exit 0
