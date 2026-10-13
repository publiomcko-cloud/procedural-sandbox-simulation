Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:F2LaunchExpectedSourceRoot = 'C:\Dev\f2-g1-protected-updater-source'
$script:F2LaunchExpectedCandidateRoot = 'C:\Dev\f2-g1-protected-updater'
$script:F2LaunchExpectedSourceCommit = '396c44965c90c08292ad2835f8317e81b6b9daaf'
$script:F2LaunchExpectedCandidateCommit = '7f99bc10f3e2258d2340cea4e7ba1352022cbb6d'
$script:F2LaunchExpectedRemote = 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
$script:F2LaunchExpectedGitPath = 'C:\Program Files\Git\cmd\git.exe'
$script:F2LaunchExpectedGitSha256 = '7b7971dd13f0c3a284e538601f2f9770b3a87dfaccb5fb52d68141c67ed22364'
$script:F2LaunchExpectedWrapperSha256 = '194eda47254eb0ea981253a60c60aeae0f34265801dbbee929e75d97d934df6a'
$script:F2LaunchExpectedProbeModuleSha256 = '4541338491269ac2bf409c5ba0c63d93d6a5e3fd9896c9d378c79dbea43ee7ee'
$script:F2LaunchExpectedUpdaterSha256 = 'd9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2'
$script:F2LaunchExpectedHistoricalLauncherSha256 = '9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9'
$script:F2LaunchExpectedProtocolSha256 = '66466fd15ce161fe2b522c77cfd6500845012480fc64890aa8435f54197eedc7'
$script:F2LaunchExpectedCandidateSha256 = 'b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022'
$script:F2LaunchMaxRecordBytes = 8192
$script:F2LaunchNativeTypeName = 'F2HistoricalLaunchNative'
$script:F2LaunchNativeSource = @'
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;
public static class F2HistoricalLaunchNative {
    [StructLayout(LayoutKind.Sequential)] private struct SECURITY_ATTRIBUTES { public int nLength; public IntPtr lpSecurityDescriptor; public int bInheritHandle; }
    [StructLayout(LayoutKind.Sequential)] private struct TOKEN_ELEVATION { public int TokenIsElevated; }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern SafePipeHandle CreateNamedPipeW(string name, uint openMode, uint pipeMode, uint maxInstances, uint outBuffer, uint inBuffer, uint timeout, ref SECURITY_ATTRIBUTES security);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool GetNamedPipeClientProcessId(IntPtr pipe, out uint processId);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool GetNamedPipeServerProcessId(IntPtr pipe, out uint processId);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern IntPtr OpenProcess(uint access, bool inherit, uint processId);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError=true)] private static extern bool GetTokenInformation(IntPtr token, int infoClass, IntPtr info, int length, out int returned);
    [DllImport("advapi32.dll", SetLastError=true)] private static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
    [DllImport("advapi32.dll", SetLastError=true)] private static extern IntPtr GetSidSubAuthority(IntPtr sid, uint index);
    public static SafePipeHandle CreateLocalServer(string shortName, byte[] selfRelativeSecurityDescriptor) {
        if (String.IsNullOrWhiteSpace(shortName) || shortName.IndexOfAny(new char[]{'\\','/'}) >= 0 || selfRelativeSecurityDescriptor == null || selfRelativeSecurityDescriptor.Length == 0) throw new ArgumentException("invalid local pipe input");
        IntPtr descriptor = Marshal.AllocHGlobal(selfRelativeSecurityDescriptor.Length);
        try {
            Marshal.Copy(selfRelativeSecurityDescriptor,0,descriptor,selfRelativeSecurityDescriptor.Length);
            SECURITY_ATTRIBUTES sa = new SECURITY_ATTRIBUTES(); sa.nLength=Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES)); sa.lpSecurityDescriptor=descriptor; sa.bInheritHandle=0;
            const uint PIPE_ACCESS_DUPLEX=0x3, FILE_FLAG_OVERLAPPED=0x40000000, PIPE_TYPE_BYTE=0, PIPE_READMODE_BYTE=0, PIPE_WAIT=0, PIPE_REJECT_REMOTE_CLIENTS=0x8, FILE_FLAG_FIRST_PIPE_INSTANCE=0x00080000;
            SafePipeHandle pipe=CreateNamedPipeW(@"\\.\pipe\"+shortName,PIPE_ACCESS_DUPLEX|FILE_FLAG_OVERLAPPED|FILE_FLAG_FIRST_PIPE_INSTANCE,PIPE_TYPE_BYTE|PIPE_READMODE_BYTE|PIPE_WAIT|PIPE_REJECT_REMOTE_CLIENTS,1,8192,8192,10000,ref sa);
            if (pipe == null || pipe.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
            return pipe;
        } finally { Marshal.FreeHGlobal(descriptor); }
    }
    public static uint ClientPid(IntPtr pipe) { uint pid; if(!GetNamedPipeClientProcessId(pipe,out pid)) throw new Win32Exception(Marshal.GetLastWin32Error()); return pid; }
    public static uint ServerPid(IntPtr pipe) { uint pid; if(!GetNamedPipeServerProcessId(pipe,out pid)) throw new Win32Exception(Marshal.GetLastWin32Error()); return pid; }
    public static string ProcessSid(uint pid) { IntPtr process=OpenProcess(0x1000,false,pid); if(process==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error()); IntPtr token=IntPtr.Zero; IntPtr buffer=IntPtr.Zero; try { if(!OpenProcessToken(process,0x0008,out token)) throw new Win32Exception(Marshal.GetLastWin32Error()); int needed; GetTokenInformation(token,1,IntPtr.Zero,0,out needed); buffer=Marshal.AllocHGlobal(needed); if(!GetTokenInformation(token,1,buffer,needed,out needed)) throw new Win32Exception(Marshal.GetLastWin32Error()); return new SecurityIdentifier(Marshal.ReadIntPtr(buffer)).Value; } finally { if(buffer!=IntPtr.Zero) Marshal.FreeHGlobal(buffer); if(token!=IntPtr.Zero) CloseHandle(token); CloseHandle(process); } }
    public static bool TokenIsElevated(IntPtr token) { IntPtr buffer=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(TOKEN_ELEVATION))); try { int needed; if(!GetTokenInformation(token,20,buffer,Marshal.SizeOf(typeof(TOKEN_ELEVATION)),out needed)) throw new Win32Exception(Marshal.GetLastWin32Error()); return Marshal.ReadInt32(buffer)!=0; } finally { Marshal.FreeHGlobal(buffer); } }
    public static int TokenIntegrityRid(IntPtr token) { IntPtr buffer=IntPtr.Zero; try { int needed; GetTokenInformation(token,25,IntPtr.Zero,0,out needed); buffer=Marshal.AllocHGlobal(needed); if(!GetTokenInformation(token,25,buffer,needed,out needed)) throw new Win32Exception(Marshal.GetLastWin32Error()); IntPtr sid=Marshal.ReadIntPtr(buffer); byte count=Marshal.ReadByte(GetSidSubAuthorityCount(sid)); if(count==0) throw new InvalidOperationException("invalid token label"); return Marshal.ReadInt32(GetSidSubAuthority(sid,(uint)(count-1))); } finally { if(buffer!=IntPtr.Zero) Marshal.FreeHGlobal(buffer); } }
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
    private sealed class BoundedRead { public string Text; public bool Overflow; }
    private static BoundedRead ReadBounded(StreamReader reader,int limit) { StringBuilder b=new StringBuilder(); bool overflow=false;char[] c=new char[4096]; int n; while((n=reader.Read(c,0,c.Length))>0){if(b.Length+n>limit){overflow=true;int take=Math.Max(0,limit-b.Length);if(take>0)b.Append(c,0,take);}else if(!overflow)b.Append(c,0,n);}return new BoundedRead{Text=b.ToString(),Overflow=overflow}; }
    public static string RunGitBounded(string fileName,string arguments,string workingDirectory,string systemRoot,int timeoutMs,int outputLimit,out string standardError,out int exitCode,out bool timedOut,out bool outputOverflow,out bool readersComplete) {
        using(Process p=new Process()) {
            ProcessStartInfo s=new ProcessStartInfo();s.FileName=fileName;s.Arguments=arguments;s.WorkingDirectory=workingDirectory;s.UseShellExecute=false;s.CreateNoWindow=true;s.RedirectStandardOutput=true;s.RedirectStandardError=true;s.EnvironmentVariables.Clear();s.EnvironmentVariables["SystemRoot"]=systemRoot;s.EnvironmentVariables["WINDIR"]=systemRoot;s.EnvironmentVariables["PATH"]=System.IO.Path.Combine(systemRoot,"System32");s.EnvironmentVariables["GIT_CONFIG_NOSYSTEM"]="1";s.EnvironmentVariables["GIT_CONFIG_GLOBAL"]="NUL";s.EnvironmentVariables["GIT_OPTIONAL_LOCKS"]="0";p.StartInfo=s;
            Task<BoundedRead> outTask=null,errTask=null;
            if(!p.Start())throw new InvalidOperationException("git start failed");
            outTask=Task.Factory.StartNew(()=>ReadBounded(p.StandardOutput,outputLimit),TaskCreationOptions.LongRunning);
            errTask=Task.Factory.StartNew(()=>ReadBounded(p.StandardError,4096),TaskCreationOptions.LongRunning);
            timedOut=!p.WaitForExit(timeoutMs);
            if(timedOut){try{p.Kill();}catch{};p.WaitForExit(2000);}
            readersComplete=outTask.Wait(2000)&&errTask.Wait(2000);
            if(!readersComplete){try{p.StandardOutput.Close();p.StandardError.Close();}catch{};readersComplete=outTask.Wait(1000)&&errTask.Wait(1000);}
            outputOverflow=readersComplete&&(outTask.Result.Overflow||errTask.Result.Overflow);
            standardError=readersComplete?errTask.Result.Text:"";
            exitCode=p.HasExited?p.ExitCode:-1;
            return readersComplete?outTask.Result.Text:"";
        }
    }
}
'@

function Get-F2LaunchSha256 {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-F2LaunchUtf8 {
    return New-Object System.Text.UTF8Encoding($false,$true)
}

function ConvertTo-F2LaunchVerifiedScriptBlock {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
          [Parameter(Mandatory)][string]$ExpectedSha256,
          [Parameter(Mandatory)][int]$MaximumBytes)
    if ($Bytes.Length -lt 1 -or $Bytes.Length -gt $MaximumBytes -or $ExpectedSha256 -notmatch '^[0-9a-f]{64}$') { throw 'LAUNCH_FILE_TYPE_OR_SIZE_INVALID' }
    if ((Get-F2LaunchSha256 -Bytes $Bytes) -cne $ExpectedSha256) { throw 'LAUNCH_FILE_HASH_MISMATCH' }
    $text=(Get-F2LaunchUtf8).GetString($Bytes)
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
    if ($null -eq $ast -or $errors.Count -ne 0) { throw 'LAUNCH_SCRIPT_PARSE_REJECTED' }
    return [scriptblock]::Create($text)
}

function Test-F2LaunchTokenFacts {
    param([Parameter(Mandatory)][ValidateSet('STANDARD','ELEVATED')][string]$RequiredClass,
          [Parameter(Mandatory)][string]$UserSid,
          [Parameter(Mandatory)][bool]$IsElevated,
          [Parameter(Mandatory)][bool]$IsAdministrator,
          [Parameter(Mandatory)][int]$IntegrityRid,
          [Parameter(Mandatory)][string]$ExpectedUserSid)
    if ($UserSid -cne $ExpectedUserSid) { return $false }
    if ($RequiredClass -ceq 'STANDARD') {
        return (-not $IsElevated -and -not $IsAdministrator -and $IntegrityRid -lt 0x3000)
    }
    return ($IsElevated -and $IsAdministrator -and $IntegrityRid -ge 0x3000)
}

function Test-F2LaunchRepositoryFacts {
    param([Parameter(Mandatory)][string]$CanonicalRoot,
          [Parameter(Mandatory)][string]$ExpectedRoot,
          [Parameter(Mandatory)][string]$Origin,
          [Parameter(Mandatory)][string]$ExpectedOrigin,
          [Parameter(Mandatory)][string]$Head,
          [Parameter(Mandatory)][string]$ExpectedHead,
          [Parameter(Mandatory)][bool]$Clean,
          [Parameter(Mandatory)][bool]$ReparseFree)
    return ($CanonicalRoot -ceq $ExpectedRoot -and $Origin -ceq $ExpectedOrigin -and
        $Head -ceq $ExpectedHead -and $Clean -and $ReparseFree)
}

function Test-F2LaunchHashSet {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Observed,
          [Parameter(Mandatory)][System.Collections.IDictionary]$Expected)
    if ($Observed.Count -ne $Expected.Count) { return $false }
    foreach ($name in $Expected.Keys) {
        if (-not $Observed.Contains($name) -or ([string]$Observed[$name]).ToLowerInvariant() -cne ([string]$Expected[$name]).ToLowerInvariant()) { return $false }
    }
    return $true
}

function Test-F2LaunchPreflightFacts {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Facts)
    $checks = [ordered]@{
        PowerShell51 = ($Facts.PowerShellMajor -eq 5 -and $Facts.PowerShellMinor -eq 1)
        StandardToken = [bool]$Facts.StandardTokenPass
        SourceCheckout = [bool]$Facts.SourceCheckoutPass
        CandidateCheckout = [bool]$Facts.CandidateCheckoutPass
        FixedPathsAndNoReparse = [bool]$Facts.FixedPathsAndNoReparse
        SourceHashes = [bool]$Facts.SourceHashesPass
        CandidateHash = [bool]$Facts.CandidateHashPass
        WrapperAndModuleHashes = [bool]$Facts.WrapperAndModuleHashesPass
        HistoricalPins = [bool]$Facts.HistoricalPinsPass
        SingleUseState = ([int]$Facts.PriorLaunchCount -eq 0)
    }
    $failed = @($checks.Keys | Where-Object { -not $checks[$_] })
    return [pscustomobject][ordered]@{
        Pass = ($failed.Count -eq 0)
        FailedGateCodes = @($failed | ForEach-Object { 'LAUNCH_GATE_' + $_.ToUpperInvariant() + '_FAILED' })
        LaunchCountAfterDecision = if ($failed.Count -eq 0) { 1 } else { 0 }
    }
}

function New-F2LaunchRequest {
    param([Parameter(Mandatory)][string]$RequesterSid,
          [Parameter(Mandatory)][int]$RequesterPid,
          [Parameter(Mandatory)][long]$RequesterStartUtcTicks,
          [Parameter(Mandatory)][string]$GitPath,
          [Parameter(Mandatory)][string]$GitSha256,
          [Parameter(Mandatory)][string]$LaunchCommitSha,
          [Parameter(Mandatory)][string]$LaunchModuleSha256,
          [Parameter(Mandatory)][string]$WrapperSha256,
          [Parameter(Mandatory)][string]$ModuleSha256)
    $random = New-Object byte[] 32
    $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
    try { $rng.GetBytes($random) } finally { $rng.Dispose() }
    return [pscustomobject][ordered]@{
        Schema = 'f2-g1-diagnostic-launch-request-v1'
        RequestId = [guid]::NewGuid().ToString('N')
        Nonce = ([BitConverter]::ToString($random)).Replace('-','').ToLowerInvariant()
        RequesterSid = $RequesterSid
        RequesterPid = $RequesterPid
        RequesterStartUtcTicks = $RequesterStartUtcTicks
        GitPath = $GitPath
        GitSha256 = $GitSha256
        LaunchCommitSha = $LaunchCommitSha
        LaunchModuleSha256 = $LaunchModuleSha256
        WrapperSha256 = $WrapperSha256
        ModuleSha256 = $ModuleSha256
        HistoricalSourceCommit = $script:F2LaunchExpectedSourceCommit
        HistoricalCandidateCommit = $script:F2LaunchExpectedCandidateCommit
        UacAttempt = 1
    }
}

function Test-F2LaunchRequest {
    param([Parameter(Mandatory)]$Request)
    $expected = @('Schema','RequestId','Nonce','RequesterSid','RequesterPid','RequesterStartUtcTicks','GitPath','GitSha256','LaunchCommitSha','LaunchModuleSha256','WrapperSha256','ModuleSha256','HistoricalSourceCommit','HistoricalCandidateCommit','UacAttempt')
    $actual = @($Request.PSObject.Properties | ForEach-Object { $_.Name })
    if ($actual.Count -ne $expected.Count -or @($actual | Where-Object { $expected -notcontains $_ }).Count -ne 0) { return $false }
    return ($Request.Schema -ceq 'f2-g1-diagnostic-launch-request-v1' -and
        [string]$Request.RequestId -match '^[0-9a-f]{32}$' -and [string]$Request.Nonce -match '^[0-9a-f]{64}$' -and
        [string]$Request.RequesterSid -match '^S-1-[0-9-]+$' -and [int]$Request.RequesterPid -gt 0 -and
        [long]$Request.RequesterStartUtcTicks -gt 0 -and [string]$Request.GitPath -ceq $script:F2LaunchExpectedGitPath -and
        [string]$Request.GitSha256 -ceq $script:F2LaunchExpectedGitSha256 -and [string]$Request.LaunchCommitSha -match '^[0-9a-f]{40}$' -and
        [string]$Request.LaunchModuleSha256 -match '^[0-9a-f]{64}$' -and
        [string]$Request.WrapperSha256 -match '^[0-9a-f]{64}$' -and [string]$Request.ModuleSha256 -match '^[0-9a-f]{64}$' -and
        $Request.HistoricalSourceCommit -ceq $script:F2LaunchExpectedSourceCommit -and
        $Request.HistoricalCandidateCommit -ceq $script:F2LaunchExpectedCandidateCommit -and [int]$Request.UacAttempt -eq 1)
}

function Test-F2LaunchResponse {
    param([Parameter(Mandatory)]$Response,
          [Parameter(Mandatory)]$Request,
          [Parameter(Mandatory)][int]$PipePeerPid,
          [Parameter(Mandatory)][long]$PipePeerStartUtcTicks,
          [Parameter(Mandatory)][int]$ActualExitCode)
    $expected = @('Schema','RequestId','Nonce','ChildPid','ChildStartUtcTicks','Status','Stage','ErrorCode','Stdout','StderrCodes','LaunchModuleSha256','WrapperSha256','ModuleSha256','UpdaterEntrypointInvoked','RecoveryEntrypointInvoked','ProtectedWritePerformed')
    $actual = @($Response.PSObject.Properties | ForEach-Object { $_.Name })
    if ($actual.Count -ne $expected.Count -or @($actual | Where-Object { $expected -notcontains $_ }).Count -ne 0) { return $false }
    if (-not (Test-F2LaunchRequest $Request)) { return $false }
    if ($Response.Schema -cne 'f2-g1-diagnostic-launch-response-v1' -or $Response.RequestId -cne $Request.RequestId -or $Response.Nonce -cne $Request.Nonce) { return $false }
    if ([int]$Response.ChildPid -ne $PipePeerPid -or [long]$Response.ChildStartUtcTicks -ne $PipePeerStartUtcTicks) { return $false }
    if ([string]$Response.LaunchModuleSha256 -cne $Request.LaunchModuleSha256) { return $false }
    if ([string]$Response.WrapperSha256 -cne $Request.WrapperSha256 -or [string]$Response.ModuleSha256 -cne $Request.ModuleSha256) { return $false }
    $allowedStages=@('ChildBootstrap','TokenValidation','SourceIdentityValidation','InputIntegrityValidation','ProbeInitialization','ModuleIntegrityValidation','HistoricalInputRead','HistoricalBootstrapShapeValidation','CandidateManifestValidation','ProbeSerialization','DiagnosticSerialization')
    if ($Response.Status -notin @('PASS','FAIL') -or $Response.Stage -notin $allowedStages) { return $false }
    $safeCodes=@('NONE','UNLISTED','PropertyNotFoundStrict','UPDATE_MANIFEST_SIZE_INVALID','UPDATE_MANIFEST_HASH_MISMATCH','UPDATE_MANIFEST_JSON_INVALID','UPDATE_MANIFEST_SCHEMA_INVALID','UPDATE_MANIFEST_IDENTITY_OR_BASELINE_INVALID','UPDATE_SOURCE_PINS_HASH_INVALID','UPDATE_MANIFEST_FILE_SET_INVALID','UPDATE_MANIFEST_FILE_PIN_INVALID','UPDATE_MANIFEST_PACKAGE_ROOT_INVALID','UPDATE_CANDIDATE_COMMIT_MISMATCH','PROBE_UNEXPECTED_ARGUMENTS','PROBE_REPARSE_INPUT_REJECTED','PROBE_MODULE_HASH_MISMATCH','PROBE_MODULE_INPUT_INVALID','PROBE_INPUT_UNAVAILABLE','PROBE_INPUT_TYPE_OR_SIZE_INVALID','PROBE_OUTPUT_BOUND_EXCEEDED','PROBE_UPDATER_HASH_MISMATCH','PROBE_LAUNCHER_HASH_MISMATCH','PROBE_PROTOCOL_HASH_MISMATCH','PROBE_CANDIDATE_HASH_MISMATCH','PROBE_BOOTSTRAP_STATEMENT_MISMATCH','PROBE_SOURCE_FUNCTION_SHAPE_INVALID','PROBE_SOURCE_PARSE_FAILED','PROBE_SOURCE_INPUT_INVALID','PROBE_UNCLASSIFIED_FAILURE','PROBE_BOOTSTRAP_CALL_SHAPE_INVALID','PROBE_BOOTSTRAP_COMPARISON_SHAPE_INVALID','PROBE_BOOTSTRAP_STATEMENT_TEXT_INVALID','LAUNCH_CHILD_BOOTSTRAP_FAILED','LAUNCH_TOKEN_MISMATCH','LAUNCH_SOURCE_CHECKOUT_MISMATCH','LAUNCH_PROBE_SOURCE_PIN_MISMATCH','LAUNCH_DIAGNOSTIC_OUTPUT_INVALID','LAUNCH_PATH_UNAVAILABLE','LAUNCH_REPARSE_PATH_REJECTED','LAUNCH_FILE_TYPE_OR_SIZE_INVALID','LAUNCH_FILE_CHANGED_DURING_READ','LAUNCH_FILE_TRUNCATED','LAUNCH_FILE_HASH_MISMATCH','LAUNCH_GIT_START_FAILED','LAUNCH_GIT_TIMEOUT','LAUNCH_GIT_OUTPUT_LIMIT','LAUNCH_GIT_DRAIN_INCOMPLETE','LAUNCH_GIT_QUERY_FAILED','LAUNCH_GIT_PATH_REJECTED','LAUNCH_CHECKOUT_METADATA_REJECTED','LAUNCH_PIPE_NAME_INVALID','LAUNCH_RECORD_SIZE_INVALID','LAUNCH_FRAME_SIZE_INVALID','LAUNCH_FRAME_LENGTH_INVALID','LAUNCH_FRAME_TRUNCATED','LAUNCH_ELEVATED_TOKEN_REQUIRED','LAUNCH_PIPE_SERVER_PID_MISMATCH','LAUNCH_PIPE_SERVER_START_MISMATCH','LAUNCH_REQUEST_INVALID','LAUNCH_REQUEST_PARENT_MISMATCH','LAUNCH_REQUEST_PARENT_SID_MISMATCH','LAUNCH_SOURCE_PIN_MISMATCH','LAUNCH_REQUESTER_IDENTITY_MISMATCH','LAUNCH_SOURCE_CHECKOUT_MISMATCH','LAUNCH_PROBE_SOURCE_PIN_MISMATCH','LAUNCH_DIAGNOSTIC_OUTPUT_INVALID')
    if([string]$Response.ErrorCode -cnotin $safeCodes){return $false}
    if ([string]$Response.Stdout -notmatch '^\{.{0,4094}\}$' -or [string]$Response.Stdout -match '(?i)([A-Z]:\\|S-1-|BaselineMailboxId|ExceptionMessage|SDDL)') { return $false }
    if (@($Response.StderrCodes | Where-Object { $_ -notin $safeCodes }).Count -gt 0 -or @($Response.StderrCodes).Count -gt 16) { return $false }
    if ($Response.Status -ceq 'PASS' -and @($Response.StderrCodes).Count -ne 0) { return $false }
    if ($Response.UpdaterEntrypointInvoked -ne $false -or $Response.RecoveryEntrypointInvoked -ne $false -or $Response.ProtectedWritePerformed -ne $false) { return $false }
    if (($Response.Status -ceq 'PASS' -and $ActualExitCode -ne 0) -or ($Response.Status -ceq 'FAIL' -and $ActualExitCode -eq 0)) { return $false }
    if (($Response.Status -ceq 'PASS' -and [string]$Response.ErrorCode -cne 'NONE') -or ($Response.Status -ceq 'FAIL' -and [string]$Response.ErrorCode -ceq 'NONE')) { return $false }
    try { $diagnostic=ConvertFrom-Json -InputObject ([string]$Response.Stdout) -ErrorAction Stop } catch { return $false }
    $diagnosticRequired=@('Schema','Authority','Status','Stage','OperationClassification','ExceptionCategory','FullyQualifiedErrorId','ErrorCode','TokenClass','HistoricalSourceCommit','HistoricalUpdaterSha256','HistoricalLauncherSha256','HistoricalCandidateSha256','UpdaterEntrypointInvoked','RecoveryEntrypointInvoked','ProtectedWritePerformed')
    $diagnosticNames=@($diagnostic.PSObject.Properties|ForEach-Object{$_.Name})
    $diagnosticAllowed=@($diagnosticRequired+'ParsedReviewedCommitSha')
    if (@($diagnosticNames|Where-Object{$diagnosticAllowed -notcontains $_}).Count -ne 0) { return $false }
    foreach($name in $diagnosticRequired){if($null -eq $diagnostic.PSObject.Properties[$name]){return $false}}
    if ([string]$diagnostic.Schema -cne 'f2-g1-historical-manifest-diagnostic-v1' -or [string]$diagnostic.Authority -cne 'NON_AUTHORITATIVE_DIAGNOSTIC_ONLY') { return $false }
    if ([string]$diagnostic.Status -cne [string]$Response.Status -or [string]$diagnostic.Stage -cne [string]$Response.Stage -or [string]$diagnostic.ErrorCode -cne [string]$Response.ErrorCode) { return $false }
    if ([string]$diagnostic.FullyQualifiedErrorId -cnotin $safeCodes -or [string]$diagnostic.FullyQualifiedErrorId -cne [string]$diagnostic.ErrorCode) { return $false }
    if ([string]$diagnostic.HistoricalSourceCommit -cne $script:F2LaunchExpectedSourceCommit -or [string]$diagnostic.HistoricalUpdaterSha256 -cne $script:F2LaunchExpectedUpdaterSha256 -or [string]$diagnostic.HistoricalLauncherSha256 -cne $script:F2LaunchExpectedHistoricalLauncherSha256 -or [string]$diagnostic.HistoricalCandidateSha256 -cne $script:F2LaunchExpectedCandidateSha256) { return $false }
    if ([string]$diagnostic.TokenClass -notin @('STANDARD','ELEVATED')) { return $false }
    if ($diagnostic.UpdaterEntrypointInvoked -ne $false -or $diagnostic.RecoveryEntrypointInvoked -ne $false -or $diagnostic.ProtectedWritePerformed -ne $false) { return $false }
    if ($Response.Status -ceq 'PASS') {
        if ($diagnosticNames.Count -ne ($diagnosticRequired.Count+1)) { return $false }
        if ([string]$diagnostic.ExceptionCategory -cne 'NONE' -or [string]$diagnostic.FullyQualifiedErrorId -cne 'NONE' -or [string]$diagnostic.OperationClassification -cne 'ManifestParseAndReviewedCommitComparison') { return $false }
        if ($null -eq $diagnostic.PSObject.Properties['ParsedReviewedCommitSha'] -or [string]$diagnostic.ParsedReviewedCommitSha -cne $script:F2LaunchExpectedSourceCommit) { return $false }
    } else {
        if ($diagnosticNames.Count -ne $diagnosticRequired.Count) { return $false }
        if ([string]$diagnostic.ExceptionCategory -notin @('STRICTMODE_MISSING_PROPERTY','HISTORICAL_MANIFEST_REJECTION','REVIEWED_COMMIT_MISMATCH','PROBE_VALIDATION_FAILURE','UNEXPECTED_POWERSHELL_EXCEPTION','SAFE_LAUNCH_FAILURE')) { return $false }
        if ([string]$diagnostic.OperationClassification -notin @('HistoricalInputHashValidation','PinnedSourceParsing','HistoricalManifestParserCall','ReviewedCommitShaComparison','ProbeInitialization','LaunchPreflight')) { return $false }
    }
    return $true
}

function ConvertTo-F2LaunchFrame {
    param([Parameter(Mandatory)][string]$Json)
    $bytes = (Get-F2LaunchUtf8).GetBytes($Json)
    if ($bytes.Length -lt 2 -or $bytes.Length -gt $script:F2LaunchMaxRecordBytes) { throw 'LAUNCH_RECORD_SIZE_INVALID' }
    $frame = New-Object byte[] ($bytes.Length + 4)
    [BitConverter]::GetBytes([int]$bytes.Length).CopyTo($frame,0)
    [Array]::Copy($bytes,0,$frame,4,$bytes.Length)
    return ,$frame
}

function Read-F2LaunchFrameBytes {
    param([Parameter(Mandatory)][byte[]]$Frame)
    if ($Frame.Length -lt 6 -or $Frame.Length -gt ($script:F2LaunchMaxRecordBytes + 4)) { throw 'LAUNCH_FRAME_SIZE_INVALID' }
    $length = [BitConverter]::ToInt32($Frame,0)
    if ($length -ne ($Frame.Length - 4) -or $length -gt $script:F2LaunchMaxRecordBytes) { throw 'LAUNCH_FRAME_LENGTH_INVALID' }
    $payload = New-Object byte[] $length
    [Array]::Copy($Frame,4,$payload,0,$length)
    return (Get-F2LaunchUtf8).GetString($payload)
}

function Test-F2LaunchPeerFacts {
    param([Parameter(Mandatory)][int]$ExpectedPid,
          [Parameter(Mandatory)][long]$ExpectedStartUtcTicks,
          [Parameter(Mandatory)][int]$ObservedPid,
          [Parameter(Mandatory)][long]$ObservedStartUtcTicks,
          [Parameter(Mandatory)][bool]$CommandLineMatches,
          [Parameter(Mandatory)][bool]$TokenMatches)
    return ($ExpectedPid -gt 0 -and $ExpectedPid -eq $ObservedPid -and $ExpectedStartUtcTicks -gt 0 -and
        $ExpectedStartUtcTicks -eq $ObservedStartUtcTicks -and $CommandLineMatches -and $TokenMatches)
}

function Test-F2LaunchProcessCommandLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$ProcessId,
          [Parameter(Mandatory)][string]$ExpectedImagePath,
          [Parameter(Mandatory)][string]$ExpectedEncodedCommand)
    if ($ProcessId -le 0 -or [string]::IsNullOrWhiteSpace($ExpectedEncodedCommand) -or $ExpectedEncodedCommand -notmatch '^[A-Za-z0-9+/=]+$') { return $false }
    try {
        $instances = @(Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId = {0}' -f $ProcessId) -ErrorAction Stop)
        return Test-F2LaunchCommandLineRecord -Instances $instances -ExpectedProcessId $ProcessId -ExpectedImagePath $ExpectedImagePath -ExpectedEncodedCommand $ExpectedEncodedCommand
    } catch {
        return $false
    }
}

function Test-F2LaunchCommandLineRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Instances,
          [Parameter(Mandatory)][int]$ExpectedProcessId,
          [Parameter(Mandatory)][string]$ExpectedImagePath,
          [Parameter(Mandatory)][string]$ExpectedEncodedCommand)
    if ($ExpectedProcessId -le 0 -or $Instances.Count -ne 1 -or [string]::IsNullOrWhiteSpace($ExpectedEncodedCommand) -or $ExpectedEncodedCommand -notmatch '^[A-Za-z0-9+/=]+$') { return $false }
    $instance=$Instances[0]
    if ([int]$instance.ProcessId -ne $ExpectedProcessId -or [string]$instance.Name -cne 'powershell.exe') { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$instance.ExecutablePath) -or [string]::IsNullOrWhiteSpace([string]$instance.CommandLine)) { return $false }
    try { if ([IO.Path]::GetFullPath([string]$instance.ExecutablePath) -cne [IO.Path]::GetFullPath($ExpectedImagePath)) { return $false } }
    catch { return $false }
    $imagePattern = [regex]::Escape([IO.Path]::GetFullPath($ExpectedImagePath))
    $commandPattern = '^\s*"' + $imagePattern + '"\s+-NoLogo\s+-NoProfile\s+-NonInteractive\s+-ExecutionPolicy\s+Bypass\s+-EncodedCommand\s+(?<encoded>[A-Za-z0-9+/=]+)\s*$'
    $match = [regex]::Match([string]$instance.CommandLine,$commandPattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::CultureInvariant)
    return ($match.Success -and $match.Groups['encoded'].Value -ceq $ExpectedEncodedCommand)
}

function Test-F2LaunchHello {
    param([Parameter(Mandatory)]$Hello,[Parameter(Mandatory)][int]$ExpectedPid,[Parameter(Mandatory)][long]$ExpectedStartUtcTicks)
    $expected=@('Schema','ProcessId','StartUtcTicks')
    $actual=@($Hello.PSObject.Properties|ForEach-Object{$_.Name})
    if($actual.Count -ne $expected.Count -or @($actual|Where-Object{$expected -notcontains $_}).Count -ne 0){return $false}
    return ($Hello.Schema -ceq 'f2-g1-diagnostic-launch-hello-v1' -and [int]$Hello.ProcessId -eq $ExpectedPid -and [long]$Hello.StartUtcTicks -eq $ExpectedStartUtcTicks)
}

function New-F2LaunchPipeSecurity {
    param([Parameter(Mandatory)][string]$RequesterSid)
    $security = New-Object System.IO.Pipes.PipeSecurity
    $requester = New-Object System.Security.Principal.SecurityIdentifier($RequesterSid)
    $admins = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $system = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
    $security.SetOwner($requester)
    $security.SetAccessRuleProtection($true,$false)
    $rights = [System.IO.Pipes.PipeAccessRights]::ReadWrite
    foreach ($sid in @($requester,$admins,$system)) {
        $rule = New-Object System.IO.Pipes.PipeAccessRule($sid,$rights,[System.Security.AccessControl.AccessControlType]::Allow)
        [void]$security.AddAccessRule($rule)
    }
    return $security
}

function New-F2LaunchServerStream {
    param([Parameter(Mandatory)][string]$ShortName,
          [Parameter(Mandatory)][string]$RequesterSid)
    if ($ShortName -notmatch '^F2D_[0-9a-f]{32}$') { throw 'LAUNCH_PIPE_NAME_INVALID' }
    $handle=$null
    try {
        $security = New-F2LaunchPipeSecurity -RequesterSid $RequesterSid
        $handle = [F2HistoricalLaunchNative]::CreateLocalServer($ShortName,$security.GetSecurityDescriptorBinaryForm())
        return New-Object System.IO.Pipes.NamedPipeServerStream([System.IO.Pipes.PipeDirection]::InOut,$true,$false,$handle)
    } catch {
        if($null -ne $handle){try{$handle.Dispose()}catch{}}
        throw 'LAUNCH_PIPE_CREATE_FAILED'
    }
}

function Initialize-F2LaunchNative {
    if ($null -eq ('F2HistoricalLaunchNative' -as [type])) {
        Add-Type -TypeDefinition $script:F2LaunchNativeSource -Language CSharp -ErrorAction Stop
    }
    return $script:F2LaunchNativeSource
}

function Test-F2LaunchNoForbiddenOperations {
    param([Parameter(Mandatory)][string[]]$SourcePaths)
    $forbidden = @('Invoke-F2ProtectedReleaseUpdate','Invoke-F2ProtectedReleaseRecovery','Invoke-F2UpdateTransaction','Resolve-F2UpdateTransaction','Set-Acl','icacls','Get-VM','Get-VMNetworkAdapter','New-VM','Start-VM','Stop-VM','Get-Disk','Get-Volume','Format-Volume','Mount-VHD','Add-VMHardDiskDrive','Set-VM','Set-Content','Add-Content','Out-File','Clear-Content','Remove-Item','Move-Item','Copy-Item','Rename-Item','New-Item','New-ItemProperty','Set-ItemProperty','Remove-ItemProperty','Clear-Item','Invoke-Expression','Invoke-Command','Start-Job','Register-ScheduledTask','schtasks.exe','reg.exe','regedit.exe','diskpart.exe','format.com')
    foreach ($path in $SourcePaths) {
        $tokens=$null; $errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        if ($null -eq $ast -or $errors.Count -ne 0) { return $false }
        $commands=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst]},$true)|ForEach-Object{[string]$_.GetCommandName()})
        if (@($commands|Where-Object{$forbidden -icontains $_}).Count -gt 0) { return $false }
        $methods=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.InvokeMemberExpressionAst]},$true)|ForEach-Object{[string]$_.Member.Extent.Text})
        if (@($methods|Where-Object{$_ -match '^(?i:WriteAllBytes|WriteAllText|AppendAllText|CreateDirectory|CreateFile|OpenWrite|CreateText|AppendText|Delete|Move|SetAccessControl|SetSecurityDescriptor|Format|Mount)' }).Count -gt 0) { return $false }
        $writeMethods=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and [string]$n.Member.Extent.Text -ceq 'Write'},$true))
        foreach($writeMethod in $writeMethods){if($writeMethod.Expression.Extent.Text -notin @('$pipe','$script:pipe')){return $false}}
    }
    return $true
}

function Test-F2LaunchNoReparsePath {
    param([Parameter(Mandatory)][string]$Path)
    $current=[IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrEmpty($current)) {
        if (-not ([IO.File]::Exists($current) -or [IO.Directory]::Exists($current))) { throw 'LAUNCH_PATH_UNAVAILABLE' }
        $item=Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'LAUNCH_REPARSE_PATH_REJECTED' }
        $parent=[IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $current) { break }
        $current=$parent
    }
    return $true
}

function Read-F2LaunchPinnedFile {
    param([Parameter(Mandatory)][string]$Path,
          [Parameter(Mandatory)][string]$ExpectedSha256,
          [Parameter(Mandatory)][int]$MaximumBytes)
    Test-F2LaunchNoReparsePath -Path $Path | Out-Null
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or $item.Length -lt 1 -or $item.Length -gt $MaximumBytes) { throw 'LAUNCH_FILE_TYPE_OR_SIZE_INVALID' }
    $stream=New-Object IO.FileStream($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        if ($stream.Length -ne $item.Length) { throw 'LAUNCH_FILE_CHANGED_DURING_READ' }
        $bytes=New-Object byte[] ([int]$stream.Length)
        $offset=0
        while ($offset -lt $bytes.Length) {
            $read=$stream.Read($bytes,$offset,$bytes.Length-$offset)
            if ($read -le 0) { throw 'LAUNCH_FILE_TRUNCATED' }
            $offset += $read
        }
    } finally { $stream.Dispose() }
    if ((Get-F2LaunchSha256 -Bytes $bytes) -cne $ExpectedSha256.ToLowerInvariant()) { throw 'LAUNCH_FILE_HASH_MISMATCH' }
    return ,$bytes
}

function Invoke-F2LaunchGitReadOnly {
    param([Parameter(Mandatory)][string]$GitPath,
          [Parameter(Mandatory)][string]$Repository,
          [Parameter(Mandatory)][ValidateSet('Top','Origin','Head','Status')][string]$Query)
    $arguments = switch ($Query) {
        'Top' { '-C "' + $Repository + '" -c core.fsmonitor=false -c core.hooksPath=NUL rev-parse --show-toplevel' }
        'Origin' { '-C "' + $Repository + '" -c core.fsmonitor=false -c core.hooksPath=NUL config --local --get remote.origin.url' }
        'Head' { '-C "' + $Repository + '" -c core.fsmonitor=false -c core.hooksPath=NUL rev-parse HEAD' }
        'Status' { '-C "' + $Repository + '" -c core.fsmonitor=false -c core.hooksPath=NUL status --porcelain=v1 --untracked-files=all' }
    }
    Test-F2LaunchNoReparsePath -Path $GitPath | Out-Null
    if ([IO.Path]::GetFullPath($GitPath) -cne [IO.Path]::GetFullPath($script:F2LaunchExpectedGitPath)) { throw 'LAUNCH_GIT_PATH_REJECTED' }
    if ($null -eq ('F2HistoricalLaunchNative' -as [type])) { Initialize-F2LaunchNative | Out-Null }
    $stderr='';$exit=0;$timedOut=$false;$overflow=$false;$readersComplete=$false
    $stdout=[F2HistoricalLaunchNative]::RunGitBounded($GitPath,$arguments,$Repository,$env:SystemRoot,10000,65536,[ref]$stderr,[ref]$exit,[ref]$timedOut,[ref]$overflow,[ref]$readersComplete)
    if($timedOut){throw 'LAUNCH_GIT_TIMEOUT'}
    if($overflow){throw 'LAUNCH_GIT_OUTPUT_LIMIT'}
    if(-not $readersComplete){throw 'LAUNCH_GIT_DRAIN_INCOMPLETE'}
    if($exit -ne 0){throw 'LAUNCH_GIT_QUERY_FAILED'}
    return ([string]$stdout).TrimEnd("`r","`n")
}

function Get-F2LaunchRepositoryFacts {
    param([Parameter(Mandatory)][string]$GitPath,
          [Parameter(Mandatory)][string]$ExpectedGitSha256,
          [Parameter(Mandatory)][string]$Repository,
          [Parameter(Mandatory)][string]$ExpectedRoot,
          [Parameter(Mandatory)][string]$ExpectedHead)
    Test-F2LaunchNoReparsePath -Path $Repository | Out-Null
    $metadataPath=Join-Path ([IO.Path]::GetFullPath($Repository)) '.git'
    Test-F2LaunchGitMetadataPath -Path $metadataPath | Out-Null
    if ([IO.Path]::GetFullPath($GitPath) -cne [IO.Path]::GetFullPath($script:F2LaunchExpectedGitPath) -or $ExpectedGitSha256 -cne $script:F2LaunchExpectedGitSha256) { throw 'LAUNCH_GIT_PATH_REJECTED' }
    $gitStream=New-Object IO.FileStream($GitPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        if ($gitStream.Length -gt 67108864) { throw 'LAUNCH_GIT_PATH_REJECTED' }
        $gitBytes=New-Object byte[] ([int]$gitStream.Length);$offset=0
        while($offset -lt $gitBytes.Length){$read=$gitStream.Read($gitBytes,$offset,$gitBytes.Length-$offset);if($read -le 0){throw 'LAUNCH_GIT_PATH_REJECTED'};$offset+=$read}
        if((Get-F2LaunchSha256 -Bytes $gitBytes) -cne $ExpectedGitSha256){throw 'LAUNCH_GIT_PATH_REJECTED'}
        $top=Invoke-F2LaunchGitReadOnly -GitPath $GitPath -Repository $Repository -Query Top
        $origin=Invoke-F2LaunchGitReadOnly -GitPath $GitPath -Repository $Repository -Query Origin
        $head=Invoke-F2LaunchGitReadOnly -GitPath $GitPath -Repository $Repository -Query Head
        $status=Invoke-F2LaunchGitReadOnly -GitPath $GitPath -Repository $Repository -Query Status
    } finally { $gitStream.Dispose() }
    $canonical=[IO.Path]::GetFullPath($top).TrimEnd('\')
    $expected=[IO.Path]::GetFullPath($ExpectedRoot).TrimEnd('\')
    return [pscustomobject][ordered]@{ Pass=(Test-F2LaunchRepositoryFacts -CanonicalRoot $canonical -ExpectedRoot $expected -Origin $origin -ExpectedOrigin $script:F2LaunchExpectedRemote -Head $head -ExpectedHead $ExpectedHead -Clean ([string]::IsNullOrEmpty($status)) -ReparseFree $true); Origin=$origin; Head=$head; Clean=([string]::IsNullOrEmpty($status)); RootMatches=($canonical -ceq $expected) }
}

function Test-F2LaunchGitMetadataPath {
    param([Parameter(Mandatory)][string]$Path)
    Test-F2LaunchNoReparsePath -Path $Path | Out-Null
    if ([IO.Directory]::Exists($Path)) { return $true }
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or $item.Length -lt 8 -or $item.Length -gt 4096) { throw 'LAUNCH_CHECKOUT_METADATA_REJECTED' }
    $stream=New-Object IO.FileStream($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        if ($stream.Length -ne $item.Length) { throw 'LAUNCH_CHECKOUT_METADATA_REJECTED' }
        $bytes=New-Object byte[] ([int]$stream.Length);$offset=0
        while($offset -lt $bytes.Length){$n=$stream.Read($bytes,$offset,$bytes.Length-$offset);if($n -le 0){throw 'LAUNCH_CHECKOUT_METADATA_REJECTED'};$offset+=$n}
    } finally { $stream.Dispose() }
    $text=(Get-F2LaunchUtf8).GetString($bytes)
    if ($text -notmatch '^gitdir:\s+(?<target>(?:[A-Za-z]:[\\/]|\\\\)[^\r\n]+)\r?\n?$') { throw 'LAUNCH_CHECKOUT_METADATA_REJECTED' }
    $gitDirectory=[IO.Path]::GetFullPath($Matches.target)
    if (-not [IO.Directory]::Exists($gitDirectory)) { throw 'LAUNCH_CHECKOUT_METADATA_REJECTED' }
    Test-F2LaunchNoReparsePath -Path $gitDirectory | Out-Null
    return $true
}

function Get-F2LaunchTokenFacts {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal=New-Object Security.Principal.WindowsPrincipal($identity)
        $tokenPtr=$identity.Token
        if ($null -eq ('F2HistoricalLaunchNative' -as [type])) { Initialize-F2LaunchNative | Out-Null }
        return [pscustomobject][ordered]@{ UserSid=$identity.User.Value; IsAdministrator=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); IsElevated=[F2HistoricalLaunchNative]::TokenIsElevated($tokenPtr); IntegrityRid=[F2HistoricalLaunchNative]::TokenIntegrityRid($tokenPtr) }
    } finally { $identity.Dispose() }
}

function Get-F2LaunchProcessIdentity {
    param([Parameter(Mandatory)][int]$ProcessId)
    $process=[Diagnostics.Process]::GetProcessById($ProcessId)
    try { return [pscustomobject][ordered]@{ ProcessId=$process.Id; StartUtcTicks=$process.StartTime.ToUniversalTime().Ticks; ImagePath=$process.MainModule.FileName } }
    finally { $process.Dispose() }
}

Export-ModuleMember -Function Get-F2LaunchSha256,ConvertTo-F2LaunchVerifiedScriptBlock,Test-F2LaunchTokenFacts,Test-F2LaunchRepositoryFacts,Test-F2LaunchHashSet,Test-F2LaunchPreflightFacts,New-F2LaunchRequest,Test-F2LaunchRequest,Test-F2LaunchResponse,ConvertTo-F2LaunchFrame,Read-F2LaunchFrameBytes,Test-F2LaunchPeerFacts,Test-F2LaunchProcessCommandLine,Test-F2LaunchCommandLineRecord,Test-F2LaunchHello,Test-F2LaunchNoForbiddenOperations,New-F2LaunchPipeSecurity,New-F2LaunchServerStream,Initialize-F2LaunchNative,Test-F2LaunchNoReparsePath,Read-F2LaunchPinnedFile,Get-F2LaunchRepositoryFacts,Get-F2LaunchTokenFacts,Get-F2LaunchProcessIdentity
