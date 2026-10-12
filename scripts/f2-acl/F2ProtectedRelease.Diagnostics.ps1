Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:F2UpdateDiagnosticMaxPayloadBytes = 4096
$script:F2UpdateDiagnosticSchema = 'f2-g1-protected-update-diagnostic-v1'
$script:F2UpdateDiagnosticAuthority = 'NON_AUTHORITATIVE_DIAGNOSTIC'
$script:F2UpdateDiagnosticNativeSource = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace F2UpdateDiagnostics {
  public static class NativePipe {
    private const uint PIPE_ACCESS_DUPLEX = 0x00000003;
    private const uint FILE_FLAG_FIRST_PIPE_INSTANCE = 0x00080000;
    private const uint FILE_FLAG_OVERLAPPED = 0x40000000;
    private const uint PIPE_TYPE_BYTE = 0x00000000;
    private const uint PIPE_READMODE_BYTE = 0x00000000;
    private const uint PIPE_WAIT = 0x00000000;
    private const uint PIPE_REJECT_REMOTE_CLIENTS = 0x00000008;
    [StructLayout(LayoutKind.Sequential)] private struct SECURITY_ATTRIBUTES {
      public int nLength;
      public IntPtr lpSecurityDescriptor;
      [MarshalAs(UnmanagedType.Bool)] public bool bInheritHandle;
    }
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string sddl,uint revision,out IntPtr descriptor,out uint size);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true, EntryPoint="CreateNamedPipeW")]
    private static extern IntPtr CreateNamedPipeNative(string name,uint openMode,uint pipeMode,uint maxInstances,uint outBufferSize,uint inBufferSize,uint defaultTimeout,ref SECURITY_ATTRIBUTES attributes);
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern bool GetNamedPipeClientProcessId(SafePipeHandle pipe,out uint clientProcessId);
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern bool CancelIoEx(SafePipeHandle handle,IntPtr overlapped);
    [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr memory);

    public static SafePipeHandle CreateServer(string pipeName,string ownerSid) {
      if(String.IsNullOrEmpty(pipeName) || !System.Text.RegularExpressions.Regex.IsMatch(pipeName,@"^F2G1Diag-[0-9a-f]{32}$")) throw new ArgumentException("Diagnostic pipe name rejected.");
      if(String.IsNullOrEmpty(ownerSid) || !System.Text.RegularExpressions.Regex.IsMatch(ownerSid,@"^S-1-[0-9]+(-[0-9]+)+$")) throw new ArgumentException("Diagnostic owner SID rejected.");
      string sddl="O:"+ownerSid+"D:P(A;;GRGW;;;"+ownerSid+")S:(ML;;NW;;;ME)";
      IntPtr descriptor;uint descriptorSize;
      if(!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl,1,out descriptor,out descriptorSize)) throw new Win32Exception(Marshal.GetLastWin32Error());
      try {
        SECURITY_ATTRIBUTES attributes=new SECURITY_ATTRIBUTES();attributes.nLength=Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));attributes.lpSecurityDescriptor=descriptor;attributes.bInheritHandle=false;
        IntPtr raw=CreateNamedPipeNative(@"\\.\pipe\"+pipeName,PIPE_ACCESS_DUPLEX|FILE_FLAG_FIRST_PIPE_INSTANCE|FILE_FLAG_OVERLAPPED,PIPE_TYPE_BYTE|PIPE_READMODE_BYTE|PIPE_WAIT|PIPE_REJECT_REMOTE_CLIENTS,1,8192,8192,0,ref attributes);
        if(raw==new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
        return new SafePipeHandle(raw,true);
      } finally { LocalFree(descriptor); }
    }
    public static int GetClientProcessId(SafePipeHandle pipe) {
      uint pid;if(!GetNamedPipeClientProcessId(pipe,out pid)) throw new Win32Exception(Marshal.GetLastWin32Error());
      if(pid==0 || pid>Int32.MaxValue) throw new InvalidOperationException("Diagnostic client process identity rejected.");
      return (int)pid;
    }
    public static void CancelPendingIo(SafePipeHandle handle) { if(handle!=null && !handle.IsClosed && !handle.IsInvalid) CancelIoEx(handle,IntPtr.Zero); }
  }
}
'@

$script:F2UpdateDiagnosticStages = @(
    'ChildBootstrapInitialization','UpdaterAndCandidateHashValidation','UpdaterScriptLoading',
    'ElevatedIdentityValidation','UpdaterInvocation','CandidateAndSourceValidation',
    'AcquireReleaseBarrier','RuntimeQuiescence','CreateTransactionRoots','StagePackage',
    'ActivatePackageSideBySide','ActivateManifest','Complete'
)
$script:F2UpdateDiagnosticCodes = @(
    'NONE','UPDATE_CHILD_BOOTSTRAP_INITIALIZATION_FAILED','UPDATE_UPDATER_SCRIPT_LOAD_FAILED',
    'UPDATE_ELEVATED_REQUESTER_IDENTITY_MISMATCH','UPDATE_ELEVATED_REQUESTER_IDENTITY_UNVERIFIABLE',
    'UPDATE_UPDATER_HASH_MISMATCH','UPDATE_CANDIDATE_HASH_MISMATCH','UPDATE_CANDIDATE_MANIFEST_INVALID',
    'UPDATE_SOURCE_GIT_UNAVAILABLE','UPDATE_SOURCE_COMMIT_MISMATCH','UPDATE_SOURCE_ORIGIN_MISMATCH',
    'UPDATE_SOURCE_WORKTREE_NOT_CLEAN','UPDATE_SOURCE_PACKAGE_HASH_MISMATCH','UPDATE_SOURCE_INTERNAL_PIN_MISMATCH',
    'UPDATE_SOURCE_PIN_MANIFEST_HASH_MISMATCH','UPDATE_SOURCE_PIN_PROVENANCE_INVALID','UPDATE_SOURCE_PINS_HASH_INVALID',
    'UPDATE_SYSTEM_DRIVE_ROOT_DACL_UNSAFE','UPDATE_PROGRAM_FILES_PARENT_DACL_UNSAFE',
    'UPDATE_PROGRAM_DATA_PARENT_DACL_UNSAFE','UPDATE_PARENT_CHAIN_UNSAFE','UPDATE_PARENT_ROOT_NOT_C',
    'UPDATE_OLD_RELEASE_COMMIT_MISMATCH','UPDATE_OLD_RELEASE_PIN_MISMATCH','UPDATE_MANIFEST_HASH_MISMATCH',
    'UPDATE_MANIFEST_JSON_INVALID','UPDATE_MANIFEST_SCHEMA_INVALID','UPDATE_MANIFEST_SIZE_INVALID',
    'UPDATE_MANIFEST_IDENTITY_OR_BASELINE_INVALID','UPDATE_MANIFEST_PACKAGE_ROOT_INVALID',
    'UPDATE_MANIFEST_FILE_SET_INVALID','UPDATE_MANIFEST_FILE_PIN_INVALID','UPDATE_FILE_HASH_MISMATCH',
    'UPDATE_FILE_TYPE_OR_SIZE_INVALID','UPDATE_INPUT_TYPE_OR_SIZE_INVALID','UPDATE_REPARSE_INPUT_REJECTED',
    'UPDATE_REPARSE_POINT_REJECTED','UPDATE_ACL_PROFILE_INVALID','UPDATE_REQUIRED_DIRECTORY_MISSING',
    'UPDATE_REQUIRED_DIRECTORY_TYPE_INVALID','UPDATE_EXISTING_OBJECT_SET_INVALID',
    'UPDATE_EXISTING_TRANSACTION_OBJECTS_PRESENT','UPDATE_RELEASE_ROOT_TYPE_INVALID',
    'UPDATE_TRANSACTION_ROOT_TYPE_INVALID','UPDATE_RELEASE_LOCK_TYPE_INVALID','UPDATE_CREATE_NEW_COLLISION',
    'UPDATE_NATIVE_HELPER_COMPILE_FAILED','UPDATE_RELEASE_LOCK_CREATE_FAILED',
    'UPDATE_MANIFEST_BARRIER_UNAVAILABLE','UPDATE_PROCESS_INVENTORY_UNKNOWN',
    'UPDATE_PROCESS_COMMAND_LINE_UNKNOWN','UPDATE_PROCESS_SELF_IDENTITY_UNKNOWN',
    'UPDATE_REQUESTER_LAUNCHER_IDENTITY_UNKNOWN','UPDATE_REQUESTER_LAUNCHER_UNKNOWN',
    'UPDATE_RUNTIME_PROCESS_ACTIVE_OR_UNKNOWN',
    'UPDATE_RECOVERY_TRANSACTION_ID_REQUIRED','UPDATE_RECOVERY_LOCK_MISSING_OR_INVALID',
    'UPDATE_RECOVERY_OBJECT_SET_INVALID','UPDATE_RECOVERY_JOURNAL_INCOMPLETE',
    'UPDATE_RECOVERY_JOURNAL_INVALID','UPDATE_RECOVERY_JOURNAL_CHAIN_INVALID',
    'UPDATE_RECOVERY_JOURNAL_STATE_INVALID','UPDATE_RECOVERY_ACTIVE_MANIFEST_UNKNOWN',
    'UPDATE_RECOVERY_OLD_BACKUP_INVALID','UPDATE_RECOVERY_POSTCHECK_FAILED',
    'UPDATE_OLD_MANIFEST_BACKUP_INVALID','UPDATE_ACTIVE_MANIFEST_POSTCHECK_FAILED',
    'UPDATE_DIAGNOSTIC_MISSING','UPDATE_DIAGNOSTIC_INVALID','UPDATE_DIAGNOSTIC_IDENTITY_MISMATCH',
    'UPDATE_DIAGNOSTIC_CHANNEL_FAILURE','UPDATE_DIAGNOSTIC_TIMEOUT','UPDATE_DIAGNOSTIC_PROTOCOL_HASH_MISMATCH',
    'UPDATE_UNCLASSIFIED_FAILURE'
)

function Initialize-F2UpdateDiagnosticNative {
    if ($null -ne ('F2UpdateDiagnostics.NativePipe' -as [type])) { return }
    Add-Type -TypeDefinition $script:F2UpdateDiagnosticNativeSource -ErrorAction Stop
}

function Get-F2UpdateDiagnosticSha256 {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-F2UpdateDiagnosticSidHash {
    param([Parameter(Mandatory)][ValidatePattern('^S-1-[0-9]+(-[0-9]+)+$')][string]$Sid)
    return Get-F2UpdateDiagnosticSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($Sid))
}

function ConvertFrom-F2UpdateDiagnosticHex {
    param([Parameter(Mandatory)][ValidatePattern('^(?:[0-9a-fA-F]{2})+$')][string]$Hex)
    $bytes=New-Object byte[] ($Hex.Length/2)
    for($i=0;$i -lt $bytes.Length;$i++){$bytes[$i]=[Convert]::ToByte($Hex.Substring($i*2,2),16)}
    return ,$bytes
}

function New-F2UpdateDiagnosticRequest {
    param(
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$SourceCommit,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$LauncherSha256,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$UpdaterSha256,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$CandidateManifestSha256,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$RequesterPid,
        [Parameter(Mandatory)][ValidateRange(1,9223372036854775807)][long]$RequesterCreationUtcTicks,
        [Parameter(Mandatory)][ValidatePattern('^S-1-[0-9]+(-[0-9]+)+$')][string]$RequesterSid
    )
    $nonceBytes = New-Object byte[] 32
    $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
    try { $rng.GetBytes($nonceBytes) } finally { $rng.Dispose() }
    $requestId = [guid]::NewGuid().ToString('N').ToLowerInvariant()
    return [pscustomobject]@{
        Schema=$script:F2UpdateDiagnosticSchema
        RequestId=$requestId
        Nonce=([BitConverter]::ToString($nonceBytes)).Replace('-','').ToLowerInvariant()
        PipeName=('F2G1Diag-' + $requestId)
        SourceCommit=$SourceCommit
        LauncherSha256=$LauncherSha256
        UpdaterSha256=$UpdaterSha256
        CandidateManifestSha256=$CandidateManifestSha256
        RequesterPid=$RequesterPid
        RequesterCreationUtcTicks=$RequesterCreationUtcTicks
        RequesterSidSha256=(Get-F2UpdateDiagnosticSidHash -Sid $RequesterSid)
        OwnerSid=$RequesterSid
    }
}

function New-F2UpdateDiagnosticServer {
    param([Parameter(Mandatory)]$Request)
    if ($Request.Schema -cne $script:F2UpdateDiagnosticSchema -or $Request.PipeName -cne ('F2G1Diag-' + $Request.RequestId)) { throw 'UPDATE_DIAGNOSTIC_CHANNEL_FAILURE' }
    Initialize-F2UpdateDiagnosticNative
    $handle = [F2UpdateDiagnostics.NativePipe]::CreateServer([string]$Request.PipeName,[string]$Request.OwnerSid)
    try { return [IO.Pipes.NamedPipeServerStream]::new([IO.Pipes.PipeDirection]::In,$true,$false,$handle) }
    catch { $handle.Dispose(); throw 'UPDATE_DIAGNOSTIC_CHANNEL_FAILURE' }
}

function Normalize-F2UpdateDiagnosticStage {
    param([string]$Stage)
    if ($Stage -in $script:F2UpdateDiagnosticStages) { return $Stage }
    return 'UpdaterInvocation'
}

function Normalize-F2UpdateDiagnosticCode {
    param([string]$Code,[string]$Stage,[string]$ExceptionType)
    if ($Code -ceq 'UPDATE_SOURCE_PACKAGE_HASH_MISMATCH:' -or $Code -like 'UPDATE_SOURCE_PACKAGE_HASH_MISMATCH:*') { return 'UPDATE_SOURCE_PACKAGE_HASH_MISMATCH' }
    if ($Code -ceq 'UPDATE_SOURCE_INTERNAL_PIN_MISMATCH:' -or $Code -like 'UPDATE_SOURCE_INTERNAL_PIN_MISMATCH:*') { return 'UPDATE_SOURCE_INTERNAL_PIN_MISMATCH' }
    if ($Code -in $script:F2UpdateDiagnosticCodes) { return $Code }
    if ($ExceptionType -ceq 'System.Management.Automation.CommandNotFoundException' -and $Stage -ceq 'CandidateAndSourceValidation') { return 'UPDATE_SOURCE_GIT_UNAVAILABLE' }
    if ($Stage -ceq 'ChildBootstrapInitialization') { return 'UPDATE_CHILD_BOOTSTRAP_INITIALIZATION_FAILED' }
    if ($Stage -ceq 'UpdaterScriptLoading') { return 'UPDATE_UPDATER_SCRIPT_LOAD_FAILED' }
    return 'UPDATE_UNCLASSIFIED_FAILURE'
}

function New-F2UpdateDiagnosticRecord {
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$ChildPid,
        [Parameter(Mandatory)][ValidateRange(1,9223372036854775807)][long]$ChildCreationUtcTicks,
        [Parameter(Mandatory)][ValidateRange(-2147483648,2147483647)][int]$ChildExitCode,
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$ErrorCode
    )
    $safeStage = Normalize-F2UpdateDiagnosticStage -Stage $Stage
    $safeCode = Normalize-F2UpdateDiagnosticCode -Code $ErrorCode -Stage $safeStage -ExceptionType ''
    if ($safeStage -eq 'Complete' -and ($ChildExitCode -ne 0 -or $safeCode -cne 'NONE')) { throw 'UPDATE_DIAGNOSTIC_INVALID' }
    if ($safeStage -ne 'Complete' -and $ChildExitCode -eq 0 -and $safeCode -ceq 'NONE') { throw 'UPDATE_DIAGNOSTIC_INVALID' }
    return [ordered]@{
        Schema=$script:F2UpdateDiagnosticSchema
        Authority=$script:F2UpdateDiagnosticAuthority
        RequestId=[string]$Request.RequestId
        Nonce=[string]$Request.Nonce
        SourceCommit=[string]$Request.SourceCommit
        LauncherSha256=[string]$Request.LauncherSha256
        UpdaterSha256=[string]$Request.UpdaterSha256
        CandidateManifestSha256=[string]$Request.CandidateManifestSha256
        RequesterPid=[int]$Request.RequesterPid
        RequesterCreationUtcTicks=[long]$Request.RequesterCreationUtcTicks
        RequesterSidSha256=[string]$Request.RequesterSidSha256
        ChildPid=$ChildPid
        ChildCreationUtcTicks=$ChildCreationUtcTicks
        ChildExitCode=$ChildExitCode
        Stage=$safeStage
        ErrorCode=$safeCode
    }
}

function New-F2UpdateDiagnosticFrame {
    param([Parameter(Mandatory)]$Record)
    $json = ConvertTo-Json -InputObject $Record -Depth 4 -Compress
    $payload = [Text.Encoding]::UTF8.GetBytes($json)
    if ($payload.Length -lt 2 -or $payload.Length -gt $script:F2UpdateDiagnosticMaxPayloadBytes) { throw 'UPDATE_DIAGNOSTIC_INVALID' }
    $digest = ConvertFrom-F2UpdateDiagnosticHex -Hex (Get-F2UpdateDiagnosticSha256 -Bytes $payload)
    $header = [BitConverter]::GetBytes([int]$payload.Length)
    $frame = New-Object byte[] ($header.Length + $payload.Length + $digest.Length)
    [Buffer]::BlockCopy($header,0,$frame,0,$header.Length)
    [Buffer]::BlockCopy($payload,0,$frame,$header.Length,$payload.Length)
    [Buffer]::BlockCopy($digest,0,$frame,$header.Length+$payload.Length,$digest.Length)
    return ,$frame
}

function Send-F2UpdateDiagnosticRecord {
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$ErrorCode,
        [Parameter(Mandatory)][int]$ChildExitCode,
        [ValidateRange(100,10000)][int]$ConnectTimeoutMilliseconds=3000
    )
    $client = $null
    try {
        $process = [Diagnostics.Process]::GetCurrentProcess()
        $ticks = $process.StartTime.ToUniversalTime().Ticks
        $record = New-F2UpdateDiagnosticRecord -Request $Request -ChildPid $PID -ChildCreationUtcTicks $ticks -ChildExitCode $ChildExitCode -Stage $Stage -ErrorCode $ErrorCode
        $frame = New-F2UpdateDiagnosticFrame -Record $record
        $client = New-Object IO.Pipes.NamedPipeClientStream('.', [string]$Request.PipeName, [IO.Pipes.PipeDirection]::Out, [IO.Pipes.PipeOptions]::None)
        $client.Connect($ConnectTimeoutMilliseconds)
        $client.Write($frame,0,$frame.Length)
        $client.Flush()
        return $true
    } catch { return $false }
    finally { if ($null -ne $client) { try { $client.Dispose() } catch {} } }
}

function Read-F2UpdateDiagnosticExact {
    param([Parameter(Mandatory)][IO.Pipes.NamedPipeServerStream]$Stream,[Parameter(Mandatory)][int]$Count,[Parameter(Mandatory)][Diagnostics.Stopwatch]$Clock,[Parameter(Mandatory)][int]$DeadlineMilliseconds)
    $buffer=New-Object byte[] $Count;$offset=0
    while($offset -lt $Count){
        $remaining=$DeadlineMilliseconds-[int]$Clock.ElapsedMilliseconds
        if($remaining -le 0){throw 'UPDATE_DIAGNOSTIC_TIMEOUT'}
        $readTask=$Stream.ReadAsync($buffer,$offset,$Count-$offset)
        $waitClock=[Diagnostics.Stopwatch]::StartNew()
        while(-not $readTask.IsCompleted -and $waitClock.ElapsedMilliseconds -lt $remaining){Start-Sleep -Milliseconds ([Math]::Min(25,[Math]::Max(1,$remaining-[int]$waitClock.ElapsedMilliseconds)))}
        if(-not $readTask.IsCompleted){[F2UpdateDiagnostics.NativePipe]::CancelPendingIo($Stream.SafePipeHandle);$readTask.Wait(1000) | Out-Null;throw 'UPDATE_DIAGNOSTIC_TIMEOUT'}
        $read=[int]$readTask.Result
        if($read -le 0){throw 'UPDATE_DIAGNOSTIC_INVALID'}
        $offset+=$read
    }
    return ,$buffer
}

function Test-F2UpdateDiagnosticEof {
    param([Parameter(Mandatory)][IO.Pipes.NamedPipeServerStream]$Stream,[Parameter(Mandatory)][Diagnostics.Stopwatch]$Clock,[Parameter(Mandatory)][int]$DeadlineMilliseconds)
    $remaining=$DeadlineMilliseconds-[int]$Clock.ElapsedMilliseconds
    if($remaining -le 0){throw 'UPDATE_DIAGNOSTIC_TIMEOUT'}
    $one=New-Object byte[] 1;$readTask=$Stream.ReadAsync($one,0,1);$waitClock=[Diagnostics.Stopwatch]::StartNew()
    while(-not $readTask.IsCompleted -and $waitClock.ElapsedMilliseconds -lt $remaining){Start-Sleep -Milliseconds ([Math]::Min(25,[Math]::Max(1,$remaining-[int]$waitClock.ElapsedMilliseconds)))}
    if(-not $readTask.IsCompleted){[F2UpdateDiagnostics.NativePipe]::CancelPendingIo($Stream.SafePipeHandle);$readTask.Wait(1000) | Out-Null;throw 'UPDATE_DIAGNOSTIC_TIMEOUT'}
    if([int]$readTask.Result -ne 0){throw 'UPDATE_DIAGNOSTIC_INVALID'}
    return $true
}

function ConvertFrom-F2UpdateDiagnosticFrame {
    param([Parameter(Mandatory)][byte[]]$Payload,[Parameter(Mandatory)][byte[]]$Digest,$Request,[int]$PipeClientPid,[int]$ChildPid,[long]$ChildCreationUtcTicks)
    if($Payload.Length -gt $script:F2UpdateDiagnosticMaxPayloadBytes -or $Payload.Length -lt 2){throw 'UPDATE_DIAGNOSTIC_INVALID'}
    $expectedDigest=ConvertFrom-F2UpdateDiagnosticHex -Hex (Get-F2UpdateDiagnosticSha256 -Bytes $Payload)
    if(-not [Linq.Enumerable]::SequenceEqual([byte[]]$expectedDigest,[byte[]]$Digest)){throw 'UPDATE_DIAGNOSTIC_INVALID'}
    try{$json=[Text.UTF8Encoding]::new($false,$true).GetString($Payload);$parsed=ConvertFrom-Json -InputObject $json -ErrorAction Stop}catch{throw 'UPDATE_DIAGNOSTIC_INVALID'}
    $expectedNames=@('Schema','Authority','RequestId','Nonce','SourceCommit','LauncherSha256','UpdaterSha256','CandidateManifestSha256','RequesterPid','RequesterCreationUtcTicks','RequesterSidSha256','ChildPid','ChildCreationUtcTicks','ChildExitCode','Stage','ErrorCode')
    $names=@($parsed.PSObject.Properties | ForEach-Object Name)
    if($names.Count -ne $expectedNames.Count){throw 'UPDATE_DIAGNOSTIC_INVALID'}
    for($i=0;$i -lt $expectedNames.Count;$i++){if($names[$i] -cne $expectedNames[$i]){throw 'UPDATE_DIAGNOSTIC_INVALID'}}
    $record=[ordered]@{}
    foreach($name in $expectedNames){$record[$name]=$parsed.$name}
    $canonical=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $record -Depth 4 -Compress))
    if(-not [Linq.Enumerable]::SequenceEqual([byte[]]$Payload,[byte[]]$canonical)){throw 'UPDATE_DIAGNOSTIC_INVALID'}
    if($record.Schema -cne $script:F2UpdateDiagnosticSchema -or $record.Authority -cne $script:F2UpdateDiagnosticAuthority){throw 'UPDATE_DIAGNOSTIC_INVALID'}
    if($record.RequestId -cne $Request.RequestId -or $record.Nonce -cne $Request.Nonce -or $record.SourceCommit -cne $Request.SourceCommit -or $record.LauncherSha256 -cne $Request.LauncherSha256 -or $record.UpdaterSha256 -cne $Request.UpdaterSha256 -or $record.CandidateManifestSha256 -cne $Request.CandidateManifestSha256 -or [int64]$record.RequesterPid -ne [int64]$Request.RequesterPid -or [int64]$record.RequesterCreationUtcTicks -ne [int64]$Request.RequesterCreationUtcTicks -or $record.RequesterSidSha256 -cne $Request.RequesterSidSha256){throw 'UPDATE_DIAGNOSTIC_IDENTITY_MISMATCH'}
    foreach($numericName in @('RequesterPid','RequesterCreationUtcTicks','ChildPid','ChildCreationUtcTicks','ChildExitCode')){if($record[$numericName] -is [string] -or $record[$numericName] -is [bool]){throw 'UPDATE_DIAGNOSTIC_INVALID'}}
    if([int]$record.ChildPid -ne $ChildPid -or $PipeClientPid -ne $ChildPid -or [int64]$record.ChildCreationUtcTicks -ne $ChildCreationUtcTicks -or [int64]$record.RequesterCreationUtcTicks -le 0 -or [int]$record.RequesterPid -le 0 -or [int64]$record.ChildCreationUtcTicks -le 0){throw 'UPDATE_DIAGNOSTIC_IDENTITY_MISMATCH'}
    if($record.Stage -cnotin $script:F2UpdateDiagnosticStages -or $record.ErrorCode -cnotin $script:F2UpdateDiagnosticCodes){throw 'UPDATE_DIAGNOSTIC_INVALID'}
    if($record.Stage -ceq 'Complete' -and ([int]$record.ChildExitCode -ne 0 -or $record.ErrorCode -cne 'NONE')){throw 'UPDATE_DIAGNOSTIC_INVALID'}
    if($record.Stage -cne 'Complete' -and [int]$record.ChildExitCode -eq 0 -and $record.ErrorCode -ceq 'NONE'){throw 'UPDATE_DIAGNOSTIC_INVALID'}
    return [pscustomobject]$record
}

function Receive-F2UpdateDiagnosticRecord {
    param(
        [Parameter(Mandatory)][IO.Pipes.NamedPipeServerStream]$Server,
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][Diagnostics.Process]$ChildProcess,
        [Parameter(Mandatory)][ValidateRange(0,9223372036854775807)][long]$ChildCreationUtcTicks,
        [ValidateRange(1,600)][int]$TimeoutSeconds=600,
        [ValidateRange(100,10000)][int]$PostExitWaitMilliseconds=2500,
        [ValidateRange(100,10000)][int]$RecordTimeoutMilliseconds=5000
    )
    $clock=[Diagnostics.Stopwatch]::StartNew();$connected=$false;$resolved=$false;$record=$null;$recordHash=$null;$status='MISSING';$diagCode='UPDATE_DIAGNOSTIC_MISSING';$exitCode=$null;$timedOut=$false
    $connectResult=$null;$exitObservedAt=$null
    try { $connectResult=$Server.BeginWaitForConnection($null,$null) }
    catch { return [pscustomobject]@{ActualChildExitCode=$null;TimedOut=$false;DiagnosticStatus='CHANNEL_FAILED';DiagnosticErrorCode='UPDATE_DIAGNOSTIC_CHANNEL_FAILURE';Record=$null;RecordSha256=$null;ChildPid=$ChildProcess.Id} }
    while($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds){
        try{$ChildProcess.Refresh();if($ChildProcess.HasExited -and $null -eq $exitObservedAt){$exitObservedAt=$clock.ElapsedMilliseconds;$exitCode=[int]$ChildProcess.ExitCode}}catch{}
        if(-not $resolved -and $null -ne $connectResult -and $connectResult.IsCompleted){
            $resolved=$true
            try{
                $Server.EndWaitForConnection($connectResult);$connected=$true
                $clientPid=[F2UpdateDiagnostics.NativePipe]::GetClientProcessId($Server.SafePipeHandle)
                if($clientPid -ne [int]$ChildProcess.Id -or $ChildCreationUtcTicks -le 0){throw 'UPDATE_DIAGNOSTIC_IDENTITY_MISMATCH'}
                $readClock=[Diagnostics.Stopwatch]::StartNew()
                $header=Read-F2UpdateDiagnosticExact -Stream $Server -Count 4 -Clock $readClock -DeadlineMilliseconds $RecordTimeoutMilliseconds
                $length=[BitConverter]::ToInt32($header,0)
                if($length -lt 2 -or $length -gt $script:F2UpdateDiagnosticMaxPayloadBytes){throw 'UPDATE_DIAGNOSTIC_INVALID'}
                $payload=Read-F2UpdateDiagnosticExact -Stream $Server -Count $length -Clock $readClock -DeadlineMilliseconds $RecordTimeoutMilliseconds
                $digest=Read-F2UpdateDiagnosticExact -Stream $Server -Count 32 -Clock $readClock -DeadlineMilliseconds $RecordTimeoutMilliseconds
                Test-F2UpdateDiagnosticEof -Stream $Server -Clock $readClock -DeadlineMilliseconds $RecordTimeoutMilliseconds | Out-Null
                $record=ConvertFrom-F2UpdateDiagnosticFrame -Payload $payload -Digest $digest -Request $Request -PipeClientPid $clientPid -ChildPid $ChildProcess.Id -ChildCreationUtcTicks $ChildCreationUtcTicks
                $recordHash=Get-F2UpdateDiagnosticSha256 -Bytes $payload;$status='VALIDATED';$diagCode='NONE'
            }catch{
                $status='INVALID';$message=[string]$_.Exception.Message
                if($message -ceq 'UPDATE_DIAGNOSTIC_IDENTITY_MISMATCH'){$diagCode=$message}else{$diagCode='UPDATE_DIAGNOSTIC_INVALID'}
            }
        }
        if($null -ne $exitObservedAt){
            if($resolved){break}
            if(($clock.ElapsedMilliseconds-[long]$exitObservedAt) -ge $PostExitWaitMilliseconds){$status='MISSING';$diagCode='UPDATE_DIAGNOSTIC_MISSING';break}
        }
        Start-Sleep -Milliseconds 25
    }
    if($null -eq $exitObservedAt -and $clock.Elapsed.TotalSeconds -ge $TimeoutSeconds){$timedOut=$true;$status=if($resolved){$status}else{'TIMEOUT'};$diagCode=if($resolved){$diagCode}else{'UPDATE_DIAGNOSTIC_TIMEOUT'}}
    if($null -ne $exitObservedAt){$exitCode=[int]$ChildProcess.ExitCode}
    if($status -ceq 'VALIDATED' -and $null -ne $exitCode -and [int]$record.ChildExitCode -ne [int]$exitCode){$status='INVALID';$diagCode='UPDATE_DIAGNOSTIC_IDENTITY_MISMATCH';$record=$null;$recordHash=$null}
    return [pscustomobject]@{ActualChildExitCode=$exitCode;TimedOut=$timedOut;DiagnosticStatus=$status;DiagnosticErrorCode=$diagCode;Record=$record;RecordSha256=$recordHash;ChildPid=$ChildProcess.Id}
}
