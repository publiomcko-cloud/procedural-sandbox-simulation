Set-StrictMode -Version Latest

$script:F2AclSchema = 'f2-acl-baseline-v1'
$script:F2AclMaxPayloadBytes = 262144

if ($null -eq ('F2Acl.NativeDirectory' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace F2Acl {
    public static class NativeDirectory {
        [StructLayout(LayoutKind.Sequential)]
        private struct SECURITY_ATTRIBUTES {
            public int nLength;
            public IntPtr lpSecurityDescriptor;
            [MarshalAs(UnmanagedType.Bool)] public bool bInheritHandle;
        }
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string sddl, uint revision, out IntPtr descriptor, out uint size);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true, EntryPoint="GetNamedSecurityInfoW")]
        private static extern uint GetNamedSecurityInfoNative(string path, int objectType, uint securityInfo, out IntPtr owner, out IntPtr group, out IntPtr dacl, out IntPtr sacl, out IntPtr descriptor);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool ConvertSecurityDescriptorToStringSecurityDescriptorW(IntPtr descriptor, uint revision, uint securityInfo, out IntPtr sddl, out uint size);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true, EntryPoint="CreateDirectoryW")]
        private static extern bool CreateDirectoryNative(string path, ref SECURITY_ATTRIBUTES attributes);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool GetVolumePathNameW(string fileName, System.Text.StringBuilder volumePathName, uint bufferLength);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool GetVolumeNameForVolumeMountPointW(string volumeMountPoint, System.Text.StringBuilder volumeName, uint bufferLength);
        [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr memory);

        public static void CreateWithSddl(string path, string sddl) {
            IntPtr descriptor;
            uint size;
            if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, 1, out descriptor, out size))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not build restricted directory security descriptor.");
            try {
                SECURITY_ATTRIBUTES attributes = new SECURITY_ATTRIBUTES();
                attributes.nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
                attributes.lpSecurityDescriptor = descriptor;
                attributes.bInheritHandle = false;
                if (!CreateDirectoryNative(path, ref attributes))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not create restricted evidence directory atomically.");
            }
            finally { LocalFree(descriptor); }
        }

        public static string GetSddl(string path) {
            IntPtr owner, group, dacl, sacl, descriptor;
            uint status = GetNamedSecurityInfoNative(path, 1, 0x7, out owner, out group, out dacl, out sacl, out descriptor);
            if (status != 0) throw new Win32Exception((int)status, "Could not read owner/group/DACL security descriptor.");
            try {
                IntPtr text;
                uint chars;
                if (!ConvertSecurityDescriptorToStringSecurityDescriptorW(descriptor, 1, 0x7, out text, out chars))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not serialize security descriptor to SDDL.");
                try { return Marshal.PtrToStringUni(text); }
                finally { LocalFree(text); }
            }
            finally { LocalFree(descriptor); }
        }

        public static string GetVolumeGuidForPath(string path) {
            var volumePath = new System.Text.StringBuilder(32768);
            if (!GetVolumePathNameW(path, volumePath, (uint)volumePath.Capacity))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not resolve path to a volume mount point.");
            var volumeName = new System.Text.StringBuilder(32768);
            if (!GetVolumeNameForVolumeMountPointW(volumePath.ToString(), volumeName, (uint)volumeName.Capacity))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not resolve volume GUID.");
            return volumeName.ToString().TrimEnd('\\');
        }
    }
}
'@ -ErrorAction Stop
}

function Get-F2AclSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Test-F2AclElevatedIdentityPair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RequesterSid,
        [Parameter(Mandatory)][string]$CoordinatorSid,
        [Parameter(Mandatory)][bool]$CoordinatorIsAdministrator
    )
    try { [void][Security.Principal.SecurityIdentifier]::new($RequesterSid); [void][Security.Principal.SecurityIdentifier]::new($CoordinatorSid) }
    catch { return [pscustomobject]@{Pass=$false;SameIdentity=$false;Reason='InvalidUserSid'} }
    if (-not $CoordinatorIsAdministrator) { return [pscustomobject]@{Pass=$false;SameIdentity=($RequesterSid -ceq $CoordinatorSid);Reason='ElevatedAdministratorRequired'} }
    return [pscustomobject]@{Pass=$true;SameIdentity=($RequesterSid -ceq $CoordinatorSid);Reason=if($RequesterSid -ceq $CoordinatorSid){'SameIdentityElevated'}else{'CredentialedAdministratorIdentityAccepted'}}
}

function Test-F2AclCoordinatorStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Status,[Parameter(Mandatory)][int]$ActualProcessExitCode,[Parameter(Mandatory)][string]$ExpectedRequesterSid)
    $errors = [Collections.Generic.List[string]]::new()
    $required = @('Schema','Outcome','RequesterSid','CoordinatorSid','AdministratorRoleVerified','WorkerExitCode','WorkerProcessId','WorkerDiagnostics','WorkerExpectedFiles','WorkerDiagnosticFiles','WorkerDiagnosticFallback','ExpectedProcessExitCode','PayloadSha256','StreamsSha256','Errors')
    if (-not (Test-F2AclHasProperties $Status $required)) { return [pscustomobject]@{Pass=$false;Errors=@('CoordinatorStatusFieldsMissing')} }
    if ($Status.Schema -cne 'f2-acl-elevated-coordinator-v1') { $errors.Add('CoordinatorStatusSchemaMismatch') }
    if ([string]$Status.RequesterSid -cne $ExpectedRequesterSid) { $errors.Add('CoordinatorRequesterIdentityMismatch') }
    $administratorVerified = ($Status.AdministratorRoleVerified -is [bool] -and $Status.AdministratorRoleVerified)
    $identity = Test-F2AclElevatedIdentityPair -RequesterSid $ExpectedRequesterSid -CoordinatorSid ([string]$Status.CoordinatorSid) -CoordinatorIsAdministrator $administratorVerified
    if (-not $identity.Pass) { $errors.Add('CoordinatorTokenNotAuthorized:' + $identity.Reason) }
    if (($Status.ExpectedProcessExitCode -isnot [int] -and $Status.ExpectedProcessExitCode -isnot [long]) -or [int64]$Status.ExpectedProcessExitCode -ne $ActualProcessExitCode) { $errors.Add('CoordinatorProcessExitMismatch') }
    if ($Status.Outcome -cne 'COMPLETE_READ_ONLY_ACL_BASELINE') { $errors.Add('CoordinatorDidNotComplete') }
    if (($Status.WorkerExitCode -isnot [int] -and $Status.WorkerExitCode -isnot [long]) -or [int64]$Status.WorkerExitCode -ne 0 -or $ActualProcessExitCode -ne 0) { $errors.Add('CoordinatorOrWorkerExitNonzero') }
    $worker = $Status.WorkerDiagnostics
    $workerRequired = @('Started','ProcessId','State','TimedOut','ExitCode','OutputComplete','StdoutBytes','StdoutSha256','StdoutTruncated','StderrBytes','StderrSha256','StderrTruncated','FatalError','Stages','ReaderErrors')
    if (-not (Test-F2AclHasProperties $worker $workerRequired)) { $errors.Add('WorkerDiagnosticsFieldsMissing') }
    else {
        if ($worker.Started -ne $true -or $worker.State -cne 'Exited' -or $worker.TimedOut -ne $false -or $worker.OutputComplete -ne $true) { $errors.Add('WorkerExecutionStateIncomplete') }
        if (($worker.ProcessId -isnot [int] -and $worker.ProcessId -isnot [long]) -or [int64]$worker.ProcessId -le 0 -or $worker.ExitCode -ne $Status.WorkerExitCode -or $Status.WorkerProcessId -ne $worker.ProcessId) { $errors.Add('WorkerExecutionIdentityOrExitMismatch') }
        if ($worker.StdoutTruncated -ne $false -or $worker.StderrTruncated -ne $false -or @($worker.ReaderErrors).Count -ne 0 -or $null -ne $worker.FatalError) { $errors.Add('WorkerDiagnosticsContainFailure') }
        if ([int64]$worker.StdoutBytes -gt 16384 -or [int64]$worker.StderrBytes -gt 16384 -or [string]$worker.StdoutSha256 -notmatch '^[0-9a-f]{64}$' -or [string]$worker.StderrSha256 -notmatch '^[0-9a-f]{64}$') { $errors.Add('WorkerDiagnosticBoundsOrDigestInvalid') }
        $requiredStages = @('EntrypointReached','InvocationStarted','SourceVerified','MailboxVerified','CollectorEntered','FramePublished','StreamPublished','InvocationReturned')
        foreach ($stage in $requiredStages) { if (@($worker.Stages) -cnotcontains $stage) { $errors.Add('WorkerStageMissing:' + $stage) } }
    }
    $expectedNames = @($Status.WorkerExpectedFiles | ForEach-Object { [string]$_.Name })
    $expectedNamesExact = (@($expectedNames | Sort-Object) -join ',') -ceq 'acl-baseline.frame,powershell-streams.json'
    if ($Status.WorkerExpectedFiles -isnot [array] -or -not $expectedNamesExact -or @($Status.WorkerExpectedFiles | Where-Object { $_.Exists -ne $true -or $_.Length -le 0 }).Count -ne 0) { $errors.Add('WorkerExpectedArtifactsIncomplete') }
    $diagnosticNames = @($Status.WorkerDiagnosticFiles | ForEach-Object { [string]$_.Name })
    $diagnosticNamesExact = (@($diagnosticNames | Sort-Object) -join ',') -ceq 'worker-stderr.json,worker-stdout.json'
    if ($Status.WorkerDiagnosticFiles -isnot [array] -or -not $diagnosticNamesExact -or @($Status.WorkerDiagnosticFiles | Where-Object { [string]$_.Sha256 -notmatch '^[0-9a-f]{64}$' -or $_.Bytes -le 0 -or $_.Bytes -gt 65536 }).Count -ne 0) { $errors.Add('WorkerDiagnosticArtifactsIncomplete') }
    if ([string]$Status.PayloadSha256 -notmatch '^[0-9a-f]{64}$' -or [string]$Status.StreamsSha256 -notmatch '^[0-9a-f]{64}$') { $errors.Add('CoordinatorResultDigestInvalid') }
    if ($Status.Errors -isnot [array] -or @($Status.Errors).Count -ne 0) { $errors.Add('CoordinatorErrorsPresent') }
    if ($null -ne $Status.WorkerDiagnosticFallback) { $errors.Add('UnexpectedWorkerDiagnosticFallbackOnCompleteResult') }
    return [pscustomobject]@{Pass=($errors.Count -eq 0);Errors=@($errors);SameIdentity=$identity.SameIdentity}
}

function Write-F2AclAtomicCreateNewFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,[Parameter(Mandatory)][ValidateRange(1,1048576)][int]$MaxBytes)
    if ($Bytes.Length -lt 1 -or $Bytes.Length -gt $MaxBytes) { throw 'EvidenceFileLengthOutsideLimit.' }
    if ([IO.File]::Exists($Path) -or [IO.Directory]::Exists($Path)) { throw 'EvidenceFileAlreadyExists.' }
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.pending'
    try {
        $stream = [IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $stream.Write($Bytes,0,$Bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        if ([IO.File]::Exists($Path) -or [IO.Directory]::Exists($Path)) { throw 'EvidenceFileAlreadyExists.' }
        [IO.File]::Move($temporary,$Path)
        return $Path
    }
    catch {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        throw
    }
}

function Read-F2AclBoundedFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][ValidateRange(1,1048576)][int]$MaxBytes)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'EvidenceFileTypeOrReparseInvalid.' }
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        if ($stream.Length -lt 1 -or $stream.Length -gt $MaxBytes) { throw 'EvidenceFileLengthOutsideLimit.' }
        $bytes = [byte[]]::new([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes,$offset,$bytes.Length-$offset)
            if ($read -le 0) { throw 'EvidenceFileShortRead.' }
            $offset += $read
        }
        if ($stream.ReadByte() -ne -1) { throw 'EvidenceFileGrewDuringRead.' }
        return ,$bytes
    }
    finally { $stream.Dispose() }
}

function ConvertFrom-F2AclHex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidatePattern('^(?:[0-9a-fA-F]{2})+$')][string]$Hex)

    $bytes = [byte[]]::new($Hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16)
    }
    return ,$bytes
}

function Test-F2AclFixedTimeEqual {
    param([Parameter(Mandatory)][byte[]]$A, [Parameter(Mandatory)][byte[]]$B)

    if ($A.Length -ne $B.Length) { return $false }
    $difference = 0
    for ($i = 0; $i -lt $A.Length; $i++) { $difference = $difference -bor ($A[$i] -bxor $B[$i]) }
    return ($difference -eq 0)
}

function Test-F2AclHasProperties {
    param([Parameter(Mandatory)][AllowNull()]$Object, [Parameter(Mandatory)][string[]]$Names)
    if ($null -eq $Object) { return $false }
    foreach ($name in $Names) {
        if ($Object -is [System.Collections.IDictionary]) {
            if (-not $Object.Contains($name)) { return $false }
        }
        elseif ($null -eq $Object.PSObject.Properties[$name]) { return $false }
    }
    return $true
}

function ConvertTo-F2AclCollapsedWhitespace {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    return ([regex]::Replace($Value.Trim(), '\s+', ' '))
}

function Test-F2AclKingstonStorageIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Observation)

    $errors = [Collections.Generic.List[string]]::new()
    $required = @('Win32MatchCount','DiskMatchCount','PhysicalMatchCount','Win32Serial','DiskSerial','PhysicalSerial','Win32Model','DiskFriendlyName','DiskModel','BusType','DiskHealth','DiskOperationalStatus','PhysicalHealth','GPartitionCount','PartitionDiskNumber','DiskNumber','Win32Index','VolumeFileSystem','VolumeHealth')
    if (-not (Test-F2AclHasProperties $Observation $required)) {
        return [pscustomobject]@{Pass=$false;SerialPass=$false;ModelPass=$false;TransportPass=$false;HealthPass=$false;MappingPass=$false;CanonicalModel='';Errors=@('StorageObservationFieldsMissing')}
    }
    foreach ($name in $required) {
        $value = if ($Observation -is [System.Collections.IDictionary]) { $Observation[$name] } else { $Observation.PSObject.Properties[$name].Value }
        if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrWhiteSpace($value))) { $errors.Add("StorageFieldUnavailable:$name") }
    }

    $expectedSerial = '152D20337A0C'
    $serialValues = @([string]$Observation.Win32Serial, [string]$Observation.DiskSerial, [string]$Observation.PhysicalSerial) | ForEach-Object { ($_ -replace '\s', '').ToUpperInvariant() }
    $serialPass = ([int]$Observation.Win32MatchCount -eq 1 -and [int]$Observation.DiskMatchCount -eq 1 -and [int]$Observation.PhysicalMatchCount -eq 1 -and @($serialValues | Where-Object { $_ -cne $expectedSerial }).Count -eq 0)
    if (-not $serialPass) { $errors.Add('KingstonSerialNotUniqueOrConsistent') }

    $rawWin32 = ConvertTo-F2AclCollapsedWhitespace ([string]$Observation.Win32Model)
    $rawFriendly = ConvertTo-F2AclCollapsedWhitespace ([string]$Observation.DiskFriendlyName)
    $rawDiskModel = ConvertTo-F2AclCollapsedWhitespace ([string]$Observation.DiskModel)
    $win32ModelPass = $rawWin32 -cmatch '^KINGSTON SA400S37240G(?: USB Device)?$'
    $friendlyModelPass = $rawFriendly -ceq 'KINGSTON SA400S37240G'
    $diskModelPass = $rawDiskModel -ceq 'SA400S37240G'
    $modelPass = $win32ModelPass -and $friendlyModelPass -and $diskModelPass
    if (-not $modelPass) { $errors.Add('KingstonModelFieldsMismatch') }

    $transportPass = ([string]$Observation.BusType -ceq 'USB')
    if (-not $transportPass) { $errors.Add('KingstonTransportMismatch') }
    $diskOnline = @($Observation.DiskOperationalStatus | ForEach-Object { [string]$_ }) -contains 'Online'
    $healthPass = ([string]$Observation.DiskHealth -ceq 'Healthy' -and [string]$Observation.PhysicalHealth -ceq 'Healthy' -and $diskOnline)
    if (-not $healthPass) { $errors.Add('KingstonHealthOrOnlineMismatch') }
    $mappingPass = ([int]$Observation.GPartitionCount -eq 1 -and [int]$Observation.PartitionDiskNumber -eq [int]$Observation.DiskNumber -and [int]$Observation.Win32Index -eq [int]$Observation.DiskNumber -and [string]$Observation.VolumeFileSystem -ceq 'NTFS' -and [string]$Observation.VolumeHealth -ceq 'Healthy')
    if (-not $mappingPass) { $errors.Add('KingstonGVolumeMappingMismatch') }
    return [pscustomobject]@{Pass=($errors.Count -eq 0 -and $serialPass -and $modelPass -and $transportPass -and $healthPass -and $mappingPass);SerialPass=$serialPass;ModelPass=$modelPass;TransportPass=$transportPass;HealthPass=$healthPass;MappingPass=$mappingPass;CanonicalModel=if($modelPass){'KINGSTON SA400S37240G'}else{''};RawWin32Model=[string]$Observation.Win32Model;NormalizedWin32Model=$rawWin32;RawDiskFriendlyName=[string]$Observation.DiskFriendlyName;NormalizedDiskFriendlyName=$rawFriendly;RawDiskModel=[string]$Observation.DiskModel;NormalizedDiskModel=$rawDiskModel;Errors=@($errors)}
}

function Test-F2AclZeroNicCount {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Value)

    if ($null -eq $Value) { return $false }
    $numericTypes = @('System.Byte','System.SByte','System.Int16','System.UInt16','System.Int32','System.UInt32','System.Int64','System.UInt64')
    if ($Value.GetType().FullName -notin $numericTypes) { return $false }
    try { return ([decimal]$Value -eq [decimal]0) }
    catch { return $false }
}

function Test-F2AclVmStorageSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$VmId,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$VmState,
        [Parameter(Mandatory)][string]$ExpectedVmId,
        [Parameter(Mandatory)][string]$ExpectedVmName,
        [Parameter(Mandatory)][string]$ExpectedConfiguration,
        [Parameter(Mandatory)][string]$ExpectedCheckpoints,
        [Parameter(Mandatory)][string]$ExpectedSmartPaging,
        [Parameter(Mandatory)][string[]]$ExpectedVhdPaths,
        [Parameter(Mandatory)][string]$Configuration,
        [Parameter(Mandatory)][string]$Checkpoints,
        [Parameter(Mandatory)][string]$SmartPaging,
        [Parameter(Mandatory)][string[]]$VhdPaths,
        [Parameter(Mandatory)][AllowNull()]$NicCount
    )

    $identityPass = ($VmId.ToLowerInvariant() -ceq $ExpectedVmId.ToLowerInvariant() -and $VmName -ceq $ExpectedVmName -and $VmState -ceq 'Off')
    $canonicalConfiguration = ConvertTo-F2AclCanonicalPath $Configuration
    $canonicalCheckpoints = ConvertTo-F2AclCanonicalPath $Checkpoints
    $canonicalPaging = ConvertTo-F2AclCanonicalPath $SmartPaging
    $canonicalVhds = @($VhdPaths | ForEach-Object { ConvertTo-F2AclCanonicalPath $_ } | Sort-Object)
    $canonicalExpectedVhds = @($ExpectedVhdPaths | ForEach-Object { ConvertTo-F2AclCanonicalPath $_ } | Sort-Object)
    $pathsPass = ($canonicalConfiguration -ceq (ConvertTo-F2AclCanonicalPath $ExpectedConfiguration) -and $canonicalCheckpoints -ceq (ConvertTo-F2AclCanonicalPath $ExpectedCheckpoints) -and $canonicalPaging -ceq (ConvertTo-F2AclCanonicalPath $ExpectedSmartPaging) -and $canonicalVhds.Count -eq $canonicalExpectedVhds.Count -and @((Compare-Object $canonicalVhds $canonicalExpectedVhds)).Count -eq 0)
    $nicPass = Test-F2AclZeroNicCount -Value $NicCount
    return [pscustomobject]@{Pass=($identityPass -and $pathsPass -and $nicPass);IdentityPass=$identityPass;PathsPass=$pathsPass;NicPass=$nicPass;ObservedState=$VmState;Configuration=$canonicalConfiguration;Checkpoints=$canonicalCheckpoints;SmartPaging=$canonicalPaging;VhdPaths=$canonicalVhds}
}

function Test-F2AclStorageObservationsEquivalent {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Initial, [Parameter(Mandatory)]$Final)

    $fields = @('Win32MatchCount','DiskMatchCount','PhysicalMatchCount','Win32Serial','DiskSerial','PhysicalSerial','Win32Model','DiskFriendlyName','DiskModel','BusType','DiskHealth','DiskOperationalStatus','PhysicalHealth','GPartitionCount','PartitionDiskNumber','DiskNumber','Win32Index','VolumeFileSystem','VolumeHealth')
    if (-not (Test-F2AclHasProperties $Initial $fields) -or -not (Test-F2AclHasProperties $Final $fields)) { return $false }
    foreach ($field in $fields) {
        $left = if ($field -eq 'DiskOperationalStatus') { @($Initial.$field | ForEach-Object { [string]$_ } | Sort-Object) -join "`n" } else { [string]$Initial.$field }
        $right = if ($field -eq 'DiskOperationalStatus') { @($Final.$field | ForEach-Object { [string]$_ } | Sort-Object) -join "`n" } else { [string]$Final.$field }
        if ($left -cne $right) { return $false }
    }
    return $true
}

function Assert-F2AclSupportedAce {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Security.AccessControl.GenericAce]$Ace)
    if ($Ace.GetType() -ne [Security.AccessControl.CommonAce]) { throw ('UnsupportedDaclAceClass:' + $Ace.GetType().FullName) }
    if ($Ace.AceType -notin @([Security.AccessControl.AceType]::AccessAllowed, [Security.AccessControl.AceType]::AccessDenied)) { throw ('UnsupportedDaclAceType:' + $Ace.AceType) }
    if (([int]$Ace.AceFlags -band (-bnot 0x1F)) -ne 0) { throw ('UnsupportedDaclAceFlags:' + [int]$Ace.AceFlags) }
    return $true
}

function ConvertTo-F2AclUtf8Bytes {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $bytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($Text)
    return ,$bytes
}

function ConvertTo-F2AclWindowsArgument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    $builder = [Text.StringBuilder]::new()
    [void]$builder.Append('"')
    $slashes = 0
    for ($i = 0; $i -lt $Value.Length; $i++) {
        $character = $Value[$i]
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($slashes * 2) + 1)))
            [void]$builder.Append('"')
            $slashes = 0
            continue
        }
        if ($slashes) { [void]$builder.Append(('\' * $slashes)); $slashes = 0 }
        [void]$builder.Append($character)
    }
    if ($slashes) { [void]$builder.Append(('\' * ($slashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-F2AclCanonicalPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $canonical = [IO.Path]::GetFullPath($Path)
    if ($canonical.Length -gt [IO.Path]::GetPathRoot($canonical).Length) {
        $canonical = $canonical.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    }
    return $canonical
}

function ConvertTo-F2AclRecordContent {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Record)

    return [ordered]@{
        Path = [string]$Record.Path
        Owner = [string]$Record.Owner
        OwnerSid = [string]$Record.OwnerSid
        Sddl = [string]$Record.Sddl
        DaclProtected = [bool]$Record.DaclProtected
        Status = [string]$Record.Status
        Error = [string]$Record.Error
        AceCount = [int]$Record.AceCount
        Aces = @($Record.Aces)
    }
}

function Get-F2AclJsonBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Value)

    $json = ConvertTo-Json -InputObject $Value -Depth 20 -Compress -ErrorAction Stop
    return ConvertTo-F2AclUtf8Bytes -Text $json
}

function Add-F2AclBoundedStreamRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[object]]$Records,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Stream,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [int]$MaxBytes = 65536
    )

    $record = [ordered]@{Stream=$Stream;Message=$Message}
    $recordBytes = (Get-F2AclJsonBytes $record).Length
    if ($recordBytes -gt $MaxBytes -or [int64]$State.Bytes + $recordBytes -gt $MaxBytes) { throw 'PowerShell stream output exceeded the 64 KiB collection cap.' }
    $State.Bytes = [int]$State.Bytes + $recordBytes
    $Records.Add($record)
}

function New-F2AclEvidenceDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$VmId,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string[]]$ExpectedPaths,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Records,
        [Parameter()][object]$Metadata = [ordered]@{},
        [Parameter()][string[]]$Errors = @(),
        [Parameter()][string]$VmState = 'Unknown',
        [Parameter()][string]$CaptureId = ([guid]::NewGuid().ToString('D'))
    )

    $recordRows = @()
    foreach ($record in $Records) {
        $content = ConvertTo-F2AclRecordContent -Record $record
        $content.Path = ConvertTo-F2AclCanonicalPath -Path $content.Path
        $recordHash = Get-F2AclSha256 -Bytes (Get-F2AclJsonBytes -Value $content)
        $row = [ordered]@{}
        foreach ($key in $content.Keys) { $row[$key] = $content[$key] }
        $row.RecordSha256 = $recordHash
        $recordRows += ,$row
    }

    $canonicalExpected = @($ExpectedPaths | ForEach-Object { ConvertTo-F2AclCanonicalPath $_ })
    $canonicalActual = @($recordRows | ForEach-Object { $_.Path })
    $distinct = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $canonicalActual) { [void]$distinct.Add($path) }
    $aceCount = 0
    foreach ($row in $recordRows) { $aceCount += [int]$row.AceCount }
    $orderedHashes = @($recordRows | Sort-Object { $_.Path.ToLowerInvariant() } | ForEach-Object { $_.RecordSha256 })
    $pathManifest = @($canonicalExpected | Sort-Object { $_.ToLowerInvariant() }) -join "`n"
    $recordsManifest = $orderedHashes -join "`n"
    $manifest = [ordered]@{
        ExpectedCount = $canonicalExpected.Count
        ExpectedPaths = @($canonicalExpected | Sort-Object { $_.ToLowerInvariant() })
        RecordCount = $recordRows.Count
        UniquePathCount = $distinct.Count
        AceCount = $aceCount
        ErrorCount = @($Errors).Count
        ExpectedPathsSha256 = Get-F2AclSha256 (ConvertTo-F2AclUtf8Bytes $pathManifest)
        RecordsSha256 = Get-F2AclSha256 (ConvertTo-F2AclUtf8Bytes $recordsManifest)
        Errors = @($Errors)
    }
    $requiredCompletionGates = @('VmImmutableIdentityAndOff','KingstonSerialUniqueAcrossInterfaces','KingstonModelFieldsMatch','KingstonUSBTransport','KingstonDiskHealthAndOnline','GVolumeMapsToSerialSelectedDevice','ConfiguredStoragePathsExact','ZeroVirtualNetworkAdapters','ExactlyElevenUniqueKnownPaths','AllExpectedPathsExistWithoutReparsePoints','PostCollectionVmIdentityAndOff','PostCollectionStoragePathsUnchanged','PostCollectionZeroVirtualNetworkAdapters','PostCollectionKingstonStorageIdentityUnchanged','PostCollectionNoReparsePoints')
    $gateMap = @{}
    $metadataGates = if (Test-F2AclHasProperties $Metadata @('Gates')) { @($Metadata.Gates) } else { @() }
    foreach ($gate in $metadataGates) {
        if ((Test-F2AclHasProperties $gate @('Name','Pass')) -and -not $gateMap.ContainsKey([string]$gate.Name)) { $gateMap[[string]$gate.Name] = ($gate.Pass -eq $true) }
        elseif (Test-F2AclHasProperties $gate @('Name')) { $gateMap[[string]$gate.Name] = $false }
    }
    $requiredGatesPass = $true
    foreach ($gateName in $requiredCompletionGates) { if (-not $gateMap.ContainsKey($gateName) -or -not $gateMap[$gateName]) { $requiredGatesPass = $false } }
    $post = if (Test-F2AclHasProperties $Metadata @('PostCollection')) { $Metadata.PostCollection } else { $null }
    $postEvidencePass = $false
    if ((Test-F2AclHasProperties $post @('VmId','VmName','VmState','Paths','Storage','StorageValidation')) -and (Test-F2AclHasProperties $post.Paths @('VmId','VmName','VmState','Configuration','Checkpoints','SmartPaging','VhdPaths','NicCount'))) {
        $canonicalExpected = @($ExpectedPaths | ForEach-Object { ConvertTo-F2AclCanonicalPath $_ })
        $postSnapshot = Test-F2AclVmStorageSnapshot -VmId ([string]$post.Paths.VmId) -VmName ([string]$post.Paths.VmName) -VmState ([string]$post.Paths.VmState) -ExpectedVmId $VmId -ExpectedVmName $VmName -ExpectedConfiguration $canonicalExpected[1] -ExpectedCheckpoints $canonicalExpected[0] -ExpectedSmartPaging $canonicalExpected[0] -ExpectedVhdPaths @($canonicalExpected[7],$canonicalExpected[8]) -Configuration ([string]$post.Paths.Configuration) -Checkpoints ([string]$post.Paths.Checkpoints) -SmartPaging ([string]$post.Paths.SmartPaging) -VhdPaths @($post.Paths.VhdPaths) -NicCount $post.Paths.NicCount
        $postDiskValidation = Test-F2AclKingstonStorageIdentity -Observation $post.Storage
        $postEvidencePass = ([string]$post.VmId -ceq $VmId.ToLowerInvariant() -and [string]$post.VmName -ceq $VmName -and [string]$post.VmState -ceq 'Off' -and $postSnapshot.Pass -and $postDiskValidation.Pass -and (Test-F2AclStorageObservationsEquivalent -Initial $Metadata.Disk -Final $post.Storage) -and (Test-F2AclHasProperties $post.StorageValidation @('Pass')) -and $post.StorageValidation.Pass -eq $true)
    }
    return [ordered]@{
        Schema = $script:F2AclSchema
        CaptureId = $CaptureId
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        VmId = $VmId.ToLowerInvariant()
        VmName = $VmName
        VmState = $VmState
        Complete = (@($Errors).Count -eq 0 -and $VmState -ceq 'Off' -and $canonicalExpected.Count -eq 11 -and $recordRows.Count -eq 11 -and $distinct.Count -eq 11 -and $requiredGatesPass -and $postEvidencePass)
        Manifest = $manifest
        Metadata = $Metadata
        Records = $recordRows
    }
}

function Write-F2AclFrame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IO.Stream]$Stream,
        [Parameter(Mandatory)][byte[]]$Payload,
        [int]$MaxPayloadBytes = $script:F2AclMaxPayloadBytes
    )

    if ($Payload.Length -lt 1 -or $Payload.Length -gt $MaxPayloadBytes) { throw "Payload length $($Payload.Length) is outside the allowed range." }
    $writer = [IO.BinaryWriter]::new($Stream, [Text.Encoding]::UTF8, $true)
    try {
        $writer.Write([byte[]](0x46, 0x32, 0x41, 0x43, 0x4C, 0x01, 0x0D, 0x0A))
        $writer.Write([int]$Payload.Length)
        $writer.Write($Payload)
        $writer.Write((ConvertFrom-F2AclHex (Get-F2AclSha256 $Payload)))
        $writer.Flush()
    }
    finally { $writer.Dispose() }
}

function Read-F2AclExactBytes {
    param(
        [Parameter(Mandatory)][IO.Stream]$Stream,
        [Parameter(Mandatory)][int]$Count,
        [Parameter(Mandatory)][DateTime]$DeadlineUtc
    )
    $bytes = [byte[]]::new($Count)
    $offset = 0
    while ($offset -lt $Count) {
        $remainingMs = [int][Math]::Floor(($DeadlineUtc - [DateTime]::UtcNow).TotalMilliseconds)
        if ($remainingMs -le 0) { throw 'FrameReadTimeout.' }
        $async = $Stream.BeginRead($bytes, $offset, $Count - $offset, $null, $null)
        try {
            if (-not $async.AsyncWaitHandle.WaitOne($remainingMs)) {
                try { $Stream.Dispose() } catch { }
                throw 'FrameReadTimeout.'
            }
            $read = $Stream.EndRead($async)
        }
        finally { $async.AsyncWaitHandle.Dispose() }
        if ($read -le 0) { throw 'Frame ended before the declared length.' }
        $offset += $read
    }
    return ,$bytes
}

function Read-F2AclFrame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IO.Stream]$Stream,
        [int]$MaxPayloadBytes = $script:F2AclMaxPayloadBytes,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 300
    )

    $reader = [IO.BinaryReader]::new($Stream, [Text.Encoding]::UTF8, $true)
    $deadlineUtc = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    try {
        $magic = Read-F2AclExactBytes $Stream 8 $deadlineUtc
        if ([BitConverter]::ToString($magic) -ne '46-32-41-43-4C-01-0D-0A') { throw 'Frame magic/version is invalid.' }
        $lengthBytes = Read-F2AclExactBytes $Stream 4 $deadlineUtc
        $length = [BitConverter]::ToInt32($lengthBytes, 0)
        if ($length -lt 1 -or $length -gt $MaxPayloadBytes) { throw "Frame payload length $length is outside the allowed range." }
        $payload = Read-F2AclExactBytes $Stream $length $deadlineUtc
        $digest = Read-F2AclExactBytes $Stream 32 $deadlineUtc
        $eofBuffer = [byte[]]::new(1)
        $remainingMs = [int][Math]::Floor(($deadlineUtc - [DateTime]::UtcNow).TotalMilliseconds)
        if ($remainingMs -le 0) { throw 'FrameReadTimeout.' }
        $eofRead = $Stream.BeginRead($eofBuffer, 0, 1, $null, $null)
        try {
            if (-not $eofRead.AsyncWaitHandle.WaitOne($remainingMs)) { try { $Stream.Dispose() } catch { }; throw 'FrameReadTimeout.' }
            $trailingCount = $Stream.EndRead($eofRead)
        }
        finally { $eofRead.AsyncWaitHandle.Dispose() }
        if ($trailingCount -ne 0) { throw 'Frame has trailing bytes.' }
        $actual = ConvertFrom-F2AclHex (Get-F2AclSha256 $payload)
        if (-not (Test-F2AclFixedTimeEqual $actual $digest)) { throw 'Frame SHA-256 does not match.' }
        return [pscustomobject]@{ Payload = $payload; PayloadSha256 = Get-F2AclSha256 $payload; PayloadLength = $length }
    }
    finally { $reader.Dispose() }
}

function Wait-F2AclProcessExit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Diagnostics.Process]$Process,
        [Parameter(Mandatory)][ValidateRange(1, 3600)][int]$TimeoutSeconds,
        [ValidateRange(10, 5000)][int]$PollMilliseconds = 100
    )

    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (-not $Process.HasExited -and $timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Start-Sleep -Milliseconds $PollMilliseconds
    }
    $timedOut = -not $Process.HasExited
    if ($timedOut) {
        $Process.Kill()
        $Process.WaitForExit()
    }
    return [pscustomobject]@{Completed=(-not $timedOut);TimedOut=$timedOut;ExitCode=[int]$Process.ExitCode;ElapsedMilliseconds=[long]$timer.ElapsedMilliseconds}
}

function New-F2AclWorkerBootstrapCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Invocation)

    $prefix = "`$ErrorActionPreference = 'Stop'; [Console]::Out.WriteLine('F2ACL_STAGE:EntrypointReached'); try { [Console]::Out.WriteLine('F2ACL_STAGE:InvocationStarted'); `$workerResult = "
    $suffix = @'
; if ($workerResult -isnot [int] -and $workerResult -isnot [long]) { throw 'WorkerScriptExitCodeMissingOrInvalid.' }; [Console]::Out.WriteLine('F2ACL_STAGE:InvocationReturned'); exit [int]$workerResult } catch { $fatal = [string]$_.Exception.Message; $fatal = [regex]::Replace($fatal, '[\x00-\x08\x0B\x0C\x0E-\x1F]', '?'); if ($fatal.Length -gt 2048) { $fatal = $fatal.Substring(0,2048) }; [Console]::Error.WriteLine('F2ACL_FATAL:' + $fatal); exit 3 }
'@
    return $prefix + $Invocation + $suffix
}

function Invoke-F2AclCapturedPowerShell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PowerShellExe,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$CommandText,
        [Parameter(Mandatory)][ValidateRange(1,3600)][int]$TimeoutSeconds,
        [ValidateRange(1024,65536)][int]$MaxBytesPerStream = 16384,
        [ValidateRange(1,100)][int]$PollMilliseconds = 10,
        [ValidateRange(1,30)][int]$DrainTimeoutSeconds = 3
    )

    $result = [ordered]@{
        Started=$false;ProcessId=$null;State='NotStarted';ExitCode=$null;TimedOut=$false
        StdoutBytes=[byte[]]@();StderrBytes=[byte[]]@();StdoutTruncated=$false;StderrTruncated=$false
        OutputComplete=$false;StartError=$null;ReaderErrors=@();ElapsedMilliseconds=0
    }
    $process = $null
    $states = @()
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($CommandText))
        $argumentLine = @('-NoProfile','-NonInteractive','-WindowStyle','Hidden','-EncodedCommand',$encoded | ForEach-Object { ConvertTo-F2AclWindowsArgument ([string]$_) }) -join ' '
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $PowerShellExe
        $startInfo.Arguments = $argumentLine
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) { throw 'WorkerProcessStartReturnedFalse.' }
        $result.Started = $true
        $result.ProcessId = [int]$process.Id
        $result.State = 'Running'
        foreach ($stream in @($process.StandardOutput.BaseStream,$process.StandardError.BaseStream)) {
            $states += [pscustomobject]@{Stream=$stream;Buffer=[byte[]]::new(4096);Capture=[IO.MemoryStream]::new();Task=$null;Done=$false;Truncated=$false;Name=if($states.Count -eq 0){'Stdout'}else{'Stderr'}}
        }
        foreach ($state in $states) { $state.Task = $state.Stream.ReadAsync($state.Buffer,0,$state.Buffer.Length) }

        $timedOut = $false
        $drainDeadline = $null
        while (@($states | Where-Object { -not $_.Done }).Count -gt 0) {
            if (-not $process.HasExited -and $stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $timedOut = $true
                try { $process.Kill(); [void]$process.WaitForExit(3000) } catch { $result.ReaderErrors += ('WorkerTermination:' + $_.Exception.Message) }
                $drainDeadline = [DateTime]::UtcNow.AddSeconds($DrainTimeoutSeconds)
            }
            foreach ($state in $states) {
                if ($state.Done -or -not $state.Task.IsCompleted) { continue }
                try { $readCount = [int]$state.Task.GetAwaiter().GetResult() }
                catch { $result.ReaderErrors += ($state.Name + ':' + $_.Exception.Message); $state.Done = $true; continue }
                if ($readCount -le 0) { $state.Done = $true; continue }
                $remaining = $MaxBytesPerStream - [int]$state.Capture.Length
                if ($remaining -gt 0) { $take = [Math]::Min($remaining,$readCount); $state.Capture.Write($state.Buffer,0,$take) }
                if ($readCount -gt $remaining) { $state.Truncated = $true }
                $state.Task = $state.Stream.ReadAsync($state.Buffer,0,$state.Buffer.Length)
            }
            if ($timedOut -and $null -ne $drainDeadline -and [DateTime]::UtcNow -ge $drainDeadline -and @($states | Where-Object { -not $_.Done }).Count -gt 0) {
                $result.ReaderErrors += 'WorkerOutputDrainTimeout.'
                foreach ($state in $states) { if (-not $state.Done) { try { $state.Stream.Dispose() } catch {}; $state.Done = $true } }
                break
            }
            if (@($states | Where-Object { -not $_.Done }).Count -gt 0) { Start-Sleep -Milliseconds $PollMilliseconds }
        }
        while (-not $process.HasExited -and $stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) { Start-Sleep -Milliseconds $PollMilliseconds }
        if (-not $process.HasExited) {
            $timedOut = $true
            try { $process.Kill(); [void]$process.WaitForExit(3000) } catch { $result.ReaderErrors += ('WorkerTermination:' + $_.Exception.Message) }
        }
        if ($process.HasExited) { $result.ExitCode = [int]$process.ExitCode; $result.State = if($timedOut){'TimedOutTerminated'}else{'Exited'} }
        else { $result.State = 'StillRunningAtTimeout' }
        $result.TimedOut = $timedOut
        $result.StdoutBytes = $states[0].Capture.ToArray()
        $result.StderrBytes = $states[1].Capture.ToArray()
        $result.StdoutTruncated = [bool]$states[0].Truncated
        $result.StderrTruncated = [bool]$states[1].Truncated
        $result.OutputComplete = (@($result.ReaderErrors).Count -eq 0 -and @($states | Where-Object { -not $_.Done }).Count -eq 0)
    }
    catch {
        $result.StartError = ([string]$_.Exception.Message)
        if (-not $result.Started) { $result.State = 'StartFailed' }
        if ($null -ne $process) {
            try { if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }; if ($process.HasExited) { $result.ExitCode = [int]$process.ExitCode; $result.State = 'ExitedAfterCaptureFailure' } } catch { $result.ReaderErrors += ('WorkerCleanup:' + $_.Exception.Message) }
        }
        foreach ($state in $states) { try { $result.ReaderErrors += ($state.Name + 'StreamCaptureFailed') } catch {} }
    }
    finally {
        $stopwatch.Stop()
        $result.ElapsedMilliseconds = [long]$stopwatch.ElapsedMilliseconds
        foreach ($state in $states) { try { $state.Capture.Dispose() } catch {} }
        if ($null -ne $process) { $process.Dispose() }
    }
    return [pscustomobject]$result
}

function ConvertTo-F2AclSanitizedWorkerError {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Message,[ValidateRange(1,2048)][int]$MaxLength=2048)
    $safe = [regex]::Replace($Message,'[\x00-\x08\x0B\x0C\x0E-\x1F]','?')
    $safe = [regex]::Replace($safe,'(?i)\bS-\d-(?:\d+-?)+','[sid]')
    $safe = [regex]::Replace($safe,'(?i)\b[A-Z]:\\[^\s;,)]+','[path]')
    $safe = [regex]::Replace($safe,'\\\\[^\\\s]+\\[^\\\s;,)]+','[network-path]')
    if ($safe.Length -gt $MaxLength) { $safe=$safe.Substring(0,$MaxLength) }
    return $safe
}

function ConvertTo-F2AclWorkerDiagnosticDocument {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$CapturedProcess,[Parameter(Mandatory)][string]$StreamName)

    if ($StreamName -notin @('stdout','stderr')) { throw 'WorkerDiagnosticStreamNameInvalid.' }
    $bytes = if ($StreamName -ceq 'stdout') { [byte[]]$CapturedProcess.StdoutBytes } else { [byte[]]$CapturedProcess.StderrBytes }
    if ($null -eq $bytes) { $bytes = [byte[]]::new(0) }
    $truncated = if ($StreamName -ceq 'stdout') { [bool]$CapturedProcess.StdoutTruncated } else { [bool]$CapturedProcess.StderrTruncated }
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $text = [regex]::Replace($text,'[\x00-\x08\x0B\x0C\x0E-\x1F]','?')
    $stageNames = @('EntrypointReached','InvocationStarted','SourceVerified','MailboxVerified','CollectorEntered','FramePublished','StreamPublished','InvocationReturned')
    $stages = [Collections.Generic.List[string]]::new()
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '^F2ACL_STAGE:([A-Za-z]+)$' -and $stageNames -ccontains $Matches[1] -and -not $stages.Contains($Matches[1])) { $stages.Add($Matches[1]) }
    }
    $fatal = $null
    if ($StreamName -ceq 'stderr') {
        foreach ($line in ($text -split "`r?`n")) { if ($line.StartsWith('F2ACL_FATAL:',[StringComparison]::Ordinal)) { $fatal=$line.Substring(12); break } }
    }
    if ($null -ne $fatal) { $fatal=ConvertTo-F2AclSanitizedWorkerError -Message $fatal }
    return [pscustomobject]@{Schema='f2-acl-worker-diagnostic-v1';Stream=$StreamName;ByteCount=$bytes.Length;Sha256=(Get-F2AclSha256 -Bytes $bytes);Truncated=$truncated;Text=$text;Stages=@($stages);FatalError=$fatal}
}

function New-F2AclWorkerExecutionReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$CapturedProcess,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ExpectedFiles
    )

    $stdout = ConvertTo-F2AclWorkerDiagnosticDocument -CapturedProcess $CapturedProcess -StreamName stdout
    $stderr = ConvertTo-F2AclWorkerDiagnosticDocument -CapturedProcess $CapturedProcess -StreamName stderr
    $errors = [Collections.Generic.List[string]]::new()
    if ($CapturedProcess.StartError) { $errors.Add('WorkerStartFailure:' + (ConvertTo-F2AclSanitizedWorkerError -Message ([string]$CapturedProcess.StartError))) }
    if ($null -ne $stderr.FatalError) { $errors.Add('WorkerFatal:' + $stderr.FatalError) }
    if ($CapturedProcess.TimedOut) { $errors.Add('WorkerTimeout.') }
    if ($null -eq $CapturedProcess.ExitCode) { $errors.Add('WorkerProcessExitCodeUnavailable.') }
    elseif ([int]$CapturedProcess.ExitCode -ne 0) { $errors.Add('WorkerExitedNonzero:' + [string]$CapturedProcess.ExitCode) }
    if (-not $CapturedProcess.OutputComplete) { $errors.Add('WorkerOutputCaptureIncomplete:' + (@($CapturedProcess.ReaderErrors) -join ';')) }
    if ($stdout.Truncated -or $stderr.Truncated) { $errors.Add('WorkerDiagnosticOutputTruncated.') }

    $fileNames = @($ExpectedFiles | ForEach-Object { [string]$_.Name })
    if ($ExpectedFiles.Count -ne 2 -or @($fileNames | Sort-Object -Unique).Count -ne 2) { $errors.Add('WorkerExpectedArtifactManifestInvalid.') }
    $missing = @($ExpectedFiles | Where-Object { $_.Exists -ne $true } | ForEach-Object { [string]$_.Name })
    if ($missing.Count -gt 0) { $errors.Add('WorkerExpectedFilesMissing:' + ($missing -join ',')) }

    $requiredStages = @('EntrypointReached','InvocationStarted','SourceVerified','MailboxVerified','CollectorEntered','FramePublished','StreamPublished','InvocationReturned')
    foreach ($stage in $requiredStages) { if (@($stdout.Stages) -cnotcontains $stage) { $errors.Add('WorkerStageMissing:' + $stage) } }
    if ($ExpectedFiles.Count -eq 2) {
        $frame = @($ExpectedFiles | Where-Object { $_.Name -ceq 'acl-baseline.frame' })
        $streams = @($ExpectedFiles | Where-Object { $_.Name -ceq 'powershell-streams.json' })
        if ($frame.Count -ne 1 -or ($frame.Count -eq 1 -and (($frame[0].Exists -eq $true) -ne (@($stdout.Stages) -ccontains 'FramePublished')))) { $errors.Add('WorkerFrameStageArtifactMismatch.') }
        if ($streams.Count -ne 1 -or ($streams.Count -eq 1 -and (($streams[0].Exists -eq $true) -ne (@($stdout.Stages) -ccontains 'StreamPublished')))) { $errors.Add('WorkerStreamStageArtifactMismatch.') }
    }

    $stages = [Collections.Generic.List[string]]::new()
    if ($CapturedProcess.Started) { $stages.Add('WorkerLaunched') }
    foreach ($stage in $stdout.Stages) { if (-not $stages.Contains($stage)) { $stages.Add($stage) } }
    if ($null -ne $CapturedProcess.ExitCode) { $stages.Add('WorkerExited') }
    $diagnostics = [ordered]@{
        Started=[bool]$CapturedProcess.Started;ProcessId=$CapturedProcess.ProcessId;State=$CapturedProcess.State;TimedOut=[bool]$CapturedProcess.TimedOut
        ExitCode=$CapturedProcess.ExitCode;ElapsedMilliseconds=$CapturedProcess.ElapsedMilliseconds;OutputComplete=[bool]$CapturedProcess.OutputComplete
        StdoutBytes=$stdout.ByteCount;StdoutSha256=$stdout.Sha256;StdoutTruncated=$stdout.Truncated
        StderrBytes=$stderr.ByteCount;StderrSha256=$stderr.Sha256;StderrTruncated=$stderr.Truncated
        FatalError=$stderr.FatalError;Stages=@($stages);ReaderErrors=@($CapturedProcess.ReaderErrors)
    }
    return [pscustomobject]@{Pass=($errors.Count -eq 0);Errors=@($errors);Diagnostics=$diagnostics;Stdout=$stdout;Stderr=$stderr;ExpectedFiles=@($ExpectedFiles)}
}

function Test-F2AclNoReparseAncestors {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($current)
    while ($true) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "EvidencePathReparseAncestor:$current" }
        }
        if ([string]::Equals($current.TrimEnd('\'), $root.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { throw 'EvidencePathParentWalkFailed.' }
        $current = $parent.FullName
    }
}

function Test-F2AclEvidenceVolumeSeparateFromG {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[string]$ProjectVolumePath='G:\')
    Test-F2AclNoReparseAncestors -Path $Path
    $evidenceVolume = [F2Acl.NativeDirectory]::GetVolumeGuidForPath($Path)
    $projectVolume = [F2Acl.NativeDirectory]::GetVolumeGuidForPath($ProjectVolumePath)
    if ([string]::IsNullOrWhiteSpace($evidenceVolume) -or [string]::IsNullOrWhiteSpace($projectVolume)) { throw 'EvidenceVolumeIdentityUnknown.' }
    if ([string]::Equals($evidenceVolume, $projectVolume, [StringComparison]::OrdinalIgnoreCase)) { throw 'EvidenceMustBeStoredOnVolumeSeparateFromG.' }
    return [pscustomobject]@{EvidenceVolumeGuid=$evidenceVolume;ProjectVolumeGuid=$projectVolume;Separate=$true}
}

function Get-F2AclCoordinatorMailboxPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$CaptureId)
    $commonData = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    if ([string]::IsNullOrWhiteSpace($commonData)) { throw 'CoordinatorMailboxCommonDataPathUnavailable.' }
    return [IO.Path]::GetFullPath((Join-Path $commonData ('F2-G1-ACL-Evidence-' + $CaptureId)))
}

function Get-F2AclCoordinatorMailboxSddl {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RequesterSid)
    try { [void][Security.Principal.SecurityIdentifier]::new($RequesterSid) } catch { throw 'CoordinatorMailboxRequesterSidInvalid.' }
    # OWNER RIGHTS removes the file creator's implicit WRITE_DAC even when same-account UAC
    # means the standard requester SID is also the owner of files created by the coordinator.
    # The requester can read/traverse but cannot write, delete or change DACLs.
    return ('O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;OW)(A;OICI;0x1200a9;;;' + $RequesterSid + ')')
}

function Test-F2AclCoordinatorMailboxSddl {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Sddl,[Parameter(Mandatory)][string]$RequesterSid)
    try { [void][Security.Principal.SecurityIdentifier]::new($RequesterSid) } catch { throw 'CoordinatorMailboxRequesterSidInvalid.' }
    $raw = [Security.AccessControl.RawSecurityDescriptor]::new($Sddl)
    if (($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0 -or $raw.Owner.Value -ne 'S-1-5-32-544') { throw 'Coordinator mailbox must have a protected DACL and Administrators-group owner.' }
    $expectedMasks = [Collections.Generic.Dictionary[string,int]]::new([StringComparer]::OrdinalIgnoreCase)
    $expectedMasks.Add('S-1-5-18',[int][Security.AccessControl.FileSystemRights]::FullControl)
    $expectedMasks.Add('S-1-5-32-544',[int][Security.AccessControl.FileSystemRights]::FullControl)
    $readExecuteMask = [int][Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [int][Security.AccessControl.FileSystemRights]::Synchronize
    $expectedMasks.Add('S-1-3-4',$readExecuteMask)
    $expectedMasks.Add($RequesterSid,$readExecuteMask)
    $expectedFlags = [int][Security.AccessControl.AceFlags]::ObjectInherit -bor [int][Security.AccessControl.AceFlags]::ContainerInherit
    $rules = @($raw.DiscretionaryAcl)
    if ($rules.Count -ne 4) { throw 'Coordinator mailbox DACL has an unexpected ACE count.' }
    $actualSids = @()
    foreach ($rule in $rules) {
        $sid = $rule.SecurityIdentifier.Value
        $actualSids += $sid
        if (-not $expectedMasks.ContainsKey($sid) -or $rule.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or $rule.AccessMask -ne $expectedMasks[$sid] -or [int]$rule.AceFlags -ne $expectedFlags) { throw 'Coordinator mailbox DACL contains an unexpected or writable requester ACE.' }
    }
    $expectedSids = @('S-1-5-18','S-1-5-32-544','S-1-3-4',$RequesterSid)
    if (@($actualSids | Sort-Object -Unique).Count -ne 4 -or @($expectedSids | Where-Object { $_ -notin $actualSids }).Count -ne 0) { throw 'Coordinator mailbox DACL is missing a required principal.' }
    return [pscustomobject]@{OwnerSid=$raw.Owner.Value;RequesterSid=$RequesterSid;RequesterRights='ReadAndExecute';Protected=$true;AceCount=$rules.Count;Sddl=$raw.GetSddlForm([Security.AccessControl.AccessControlSections]::All)}
}

function Test-F2AclCoordinatorMailboxDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$RequesterSid)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Coordinator mailbox type or reparse check failed.' }
    $validated = Test-F2AclCoordinatorMailboxSddl -Sddl ([F2Acl.NativeDirectory]::GetSddl($Path)) -RequesterSid $RequesterSid
    $validated | Add-Member -NotePropertyName Path -NotePropertyValue $item.FullName
    return $validated
}

function Test-F2AclCoordinatorMailboxParentSddl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Sddl,
        [switch]$RequireProtectedDacl,
        [switch]$AllowBuiltinUsersCreateRights
    )

    $raw = [Security.AccessControl.RawSecurityDescriptor]::new($Sddl)
    if ($null -eq $raw.DiscretionaryAcl -or ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclPresent) -eq 0) { throw 'Coordinator mailbox ancestor has a missing or null DACL.' }
    $protected = (($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -ne 0)
    if ($RequireProtectedDacl -and -not $protected) { throw 'Coordinator mailbox parent DACL must be protected from ancestor inheritance.' }

    # For a directory, 0x2/0x4 are add-file/add-subdirectory (not overwrite or
    # delete of an existing child). The observed ProgramData 0x116 additionally
    # contains write-EA and write-attributes on ProgramData itself. Those are
    # accepted only for BUILTIN\Users at the mailbox parent; the mailbox DACL is
    # supplied at atomic creation and protected against inheriting these ACEs.
    $benignParentMask = [long]0x00000116
    $delete = [long]0x00010000
    $deleteChild = [long]0x00000040
    $writeDacl = [long]0x00040000
    $writeOwner = [long]0x00080000
    $genericWrite = [long]0x40000000
    $genericAll = [long]0x10000000
    $requesterSid = 'S-1-5-32-545'
    $issues = [Collections.Generic.List[string]]::new()

    foreach ($ace in $raw.DiscretionaryAcl) {
        if ($ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed) { continue }
        # Inherit-only ACEs do not apply to this ancestor. The exact mailbox
        # DACL is separately required to be protected and is set at creation.
        if (([int]$ace.AceFlags -band [int][Security.AccessControl.AceFlags]::InheritOnly) -ne 0) { continue }
        $sid = $ace.SecurityIdentifier.Value
        if ($sid -in @('S-1-5-18','S-1-5-32-544',$raw.Owner.Value)) { continue }
        $mask = [long]([int64]$ace.AccessMask -band 0xFFFFFFFFL)
        $untrustedControl = $mask -band ($delete -bor $deleteChild -bor $writeDacl -bor $writeOwner -bor $genericWrite -bor $genericAll)
        if ($untrustedControl -ne 0) {
            $issues.Add(('UntrustedMailboxParentControl:{0}:0x{1:X8}' -f $sid,$mask))
            continue
        }
        $createRights = $mask -band $benignParentMask
        if ($createRights -eq 0) { continue }
        if ($AllowBuiltinUsersCreateRights -and $sid -eq $requesterSid -and (($mask -band (-bnot $benignParentMask)) -eq 0)) { continue }
        if (-not $RequireProtectedDacl -and (($mask -band (-bnot $benignParentMask)) -eq 0)) { continue }
        $issues.Add(('UnapprovedMailboxParentWrite:{0}:0x{1:X8}' -f $sid,$mask))
    }
    if ($issues.Count -gt 0) { throw ('Coordinator mailbox parent ACL is unsafe: ' + ($issues -join ',')) }
    return [pscustomobject]@{Pass=$true;OwnerSid=$raw.Owner.Value;Protected=$protected;AceCount=@($raw.DiscretionaryAcl).Count;Policy=if($RequireProtectedDacl){'ProtectedMailboxParent'}else{'AncestorNoReplace'};Sddl=$raw.GetSddlForm([Security.AccessControl.AccessControlSections]::All)}
}

function Test-F2AclCoordinatorMailboxParentChain {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$MailboxParentPath)

    $fullParent = [IO.Path]::GetFullPath($MailboxParentPath)
    $current = $fullParent
    $chain = [Collections.Generic.List[string]]::new()
    while ($true) {
        $chain.Add($current)
        $root = [IO.Path]::GetPathRoot($current)
        if ([string]::Equals($current.TrimEnd('\\'),$root.TrimEnd('\\'),[StringComparison]::OrdinalIgnoreCase)) { break }
        $directory = [IO.Directory]::GetParent($current)
        if ($null -eq $directory) { throw 'CoordinatorMailboxParentChainInvalid.' }
        $current = $directory.FullName
    }

    $results = [Collections.Generic.List[object]]::new()
    $trustedOwners = @('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    foreach ($path in $chain) {
        $sddl = [F2Acl.NativeDirectory]::GetSddl($path)
        if ([string]::Equals($path,$fullParent,[StringComparison]::OrdinalIgnoreCase)) {
            $result = Test-F2AclCoordinatorMailboxParentSddl -Sddl $sddl -RequireProtectedDacl -AllowBuiltinUsersCreateRights
        }
        else {
            $result = Test-F2AclCoordinatorMailboxParentSddl -Sddl $sddl
        }
        if ($result.OwnerSid -notin $trustedOwners) { throw ('Coordinator mailbox ancestor owner is untrusted: ' + $path) }
        $results.Add($result)
    }
    return @($results)
}

function New-F2AclCoordinatorMailboxDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$CaptureId,[Parameter(Mandatory)][string]$RequesterSid,[string]$ProjectVolumePath='G:\')
    $fullPath = Get-F2AclCoordinatorMailboxPath -CaptureId $CaptureId
    $parentPath = [IO.Directory]::GetParent($fullPath).FullName
    Test-F2AclEvidenceVolumeSeparateFromG -Path $parentPath -ProjectVolumePath $ProjectVolumePath | Out-Null
    Test-F2AclNoReparseAncestors -Path $parentPath
    $parentRaw = [Security.AccessControl.RawSecurityDescriptor]::new([F2Acl.NativeDirectory]::GetSddl($parentPath))
    if ($null -eq $parentRaw.DiscretionaryAcl -or ($parentRaw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclPresent) -eq 0) { throw 'Coordinator mailbox parent has a missing or null DACL.' }
    if ($parentRaw.Owner.Value -notin @('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')) { throw 'Coordinator mailbox parent owner is not a recognized protected system principal.' }
    [void](Test-F2AclCoordinatorMailboxParentChain -MailboxParentPath $parentPath)
    if (Test-Path -LiteralPath $fullPath) { throw 'Coordinator mailbox path already exists; refusing overwrite.' }
    $sddl = Get-F2AclCoordinatorMailboxSddl -RequesterSid $RequesterSid
    [F2Acl.NativeDirectory]::CreateWithSddl($fullPath,$sddl)
    try { return Test-F2AclCoordinatorMailboxDirectory -Path $fullPath -RequesterSid $RequesterSid }
    catch {
        try { if (@(Get-ChildItem -LiteralPath $fullPath -Force -ErrorAction Stop).Count -eq 0) { Remove-Item -LiteralPath $fullPath -Force -ErrorAction Stop } } catch { }
        throw
    }
}

function New-F2AclRestrictedDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$OwnerSid, [string]$ProjectVolumePath='G:\')

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $fullPath) { throw 'Restricted directory already exists; refusing overwrite.' }
    $parentPath = [IO.Directory]::GetParent($fullPath).FullName
    Test-F2AclEvidenceVolumeSeparateFromG -Path $parentPath -ProjectVolumePath $ProjectVolumePath | Out-Null
    $parentSddl = [F2Acl.NativeDirectory]::GetSddl($parentPath)
    $parentRaw = [Security.AccessControl.RawSecurityDescriptor]::new($parentSddl)
    if ($null -eq $parentRaw.DiscretionaryAcl -or ($parentRaw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclPresent) -eq 0) { throw 'Restricted evidence parent has a missing or null DACL.' }
    $parentRules = @($parentRaw.DiscretionaryAcl | ForEach-Object {
        [pscustomobject]@{IdentityReference=$_.SecurityIdentifier;AccessControlType=if ($_.AceQualifier -eq [Security.AccessControl.AceQualifier]::AccessAllowed) { 'Allow' } else { 'Deny' };FileSystemRights=[Security.AccessControl.FileSystemRights]$_.AccessMask}
    })
    $unexpectedWriters = @(Get-F2AclUnexpectedWritableSids -Rules $parentRules -OwnerSid $OwnerSid)
    if ($unexpectedWriters.Count -gt 0) { throw ('Restricted evidence parent grants write-capable access to an unexpected SID: ' + ($unexpectedWriters -join ',')) }
    $sddl = 'O:' + $OwnerSid + 'D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;FA;;;' + $OwnerSid + ')'
    try {
        [F2Acl.NativeDirectory]::CreateWithSddl($fullPath, $sddl)
        [void](Test-F2AclRestrictedDirectory -Path $fullPath -OwnerSid $OwnerSid)
        return $fullPath
    }
    catch {
        try {
            $children = @(Get-ChildItem -LiteralPath $fullPath -Force -ErrorAction Stop)
            $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
            if ($children.Count -eq 0 -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { Remove-Item -LiteralPath $fullPath -Force -ErrorAction Stop }
        }
        catch { }
        throw
    }
}

function Test-F2AclRestrictedDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$OwnerSid)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Evidence directory is a reparse point.' }
    $raw = [Security.AccessControl.RawSecurityDescriptor]::new([F2Acl.NativeDirectory]::GetSddl($Path))
    if (($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0 -or $raw.Owner.Value -ne $OwnerSid) { throw 'Evidence directory owner or protected-DACL check failed.' }
    $allowed = @('S-1-5-18', 'S-1-5-32-544', $OwnerSid)
    $rules = @($raw.DiscretionaryAcl)
    if ($rules.Count -ne 3) { throw 'Evidence directory ACL has an unexpected ACE count.' }
    $actualSids = @()
    foreach ($rule in $rules) {
        $sid = $rule.SecurityIdentifier.Value
        $actualSids += $sid
        $expectedFlags = [int][Security.AccessControl.AceFlags]::ObjectInherit -bor [int][Security.AccessControl.AceFlags]::ContainerInherit
        if ($sid -notin $allowed -or $rule.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or $rule.AccessMask -ne [int][Security.AccessControl.FileSystemRights]::FullControl -or [int]$rule.AceFlags -ne $expectedFlags) { throw 'Evidence directory ACL contains an unexpected ACE.' }
    }
    $uniqueSids = @($actualSids | Sort-Object -Unique)
    $missingSids = @($allowed | Where-Object { $_ -notin $uniqueSids })
    if ($uniqueSids.Count -ne 3 -or $missingSids.Count -ne 0) { throw 'Evidence directory ACL is missing an expected unique principal.' }
    return [pscustomobject]@{Path=$item.FullName;OwnerSid=$OwnerSid;Protected=$true;AceCount=$rules.Count;AllowedSids=$allowed;Sddl=$raw.GetSddlForm([Security.AccessControl.AccessControlSections]::All)}
}

function Get-F2AclUnexpectedWritableSids {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Rules, [Parameter(Mandatory)][string]$OwnerSid)

    # Specific write/delete/ownership bits, including WRITE_ATTRIBUTES,
    # plus GENERIC_WRITE and GENERIC_ALL. ReadAndExecute does not overlap these.
    $writeBits = [long]0x000D0156 -bor [long]0x10000000 -bor [long]0x40000000
    $trustedWriteSids = @('S-1-5-18', 'S-1-5-32-544', $OwnerSid)
    $unexpected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($rule in $Rules) {
        if ($rule.AccessControlType -ne 'Allow') { continue }
        try { $sidText = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value }
        catch { throw ('Restricted evidence parent has an unresolvable ACE: ' + [string]$rule.IdentityReference) }
        $mask = [long]([int64]$rule.FileSystemRights -band 0xFFFFFFFFL)
        if (($mask -band $writeBits) -ne 0 -and $sidText -notin $trustedWriteSids) { [void]$unexpected.Add($sidText) }
    }
    return @($unexpected)
}

function Test-F2AclEvidenceDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$Payload,
        [Parameter(Mandatory)][string]$PayloadSha256,
        [Parameter(Mandatory)][int]$ChildExitCode,
        [Parameter(Mandatory)][string]$ExpectedVmId,
        [Parameter(Mandatory)][string]$ExpectedVmName,
        [Parameter(Mandatory)][string]$ExpectedDiskSerial,
        [Parameter(Mandatory)][string]$ExpectedDiskModel,
        [Parameter(Mandatory)][string[]]$ExpectedPaths,
        [int]$MaxPayloadBytes = $script:F2AclMaxPayloadBytes
    )

    $errors = [Collections.Generic.List[string]]::new()
    if ($Payload.Length -lt 1 -or $Payload.Length -gt $MaxPayloadBytes) { $errors.Add('PayloadLengthInvalid') }
    if ((Get-F2AclSha256 $Payload) -cne $PayloadSha256) { $errors.Add('PayloadSha256Mismatch') }
    if ($errors.Count) { return [pscustomobject]@{ Pass = $false; Errors = @($errors); Document = $null } }

    try { $doc = [Text.Encoding]::UTF8.GetString($Payload) | ConvertFrom-Json -ErrorAction Stop }
    catch { return [pscustomobject]@{ Pass = $false; Errors = @('MalformedJson: ' + $_.Exception.Message); Document = $null } }

    if ($ChildExitCode -ne 0) { $errors.Add("ChildExitCode=$ChildExitCode") }
    $requiredTop = @('Schema','CaptureId','CreatedUtc','VmId','VmName','VmState','Complete','Manifest','Metadata','Records')
    if (-not (Test-F2AclHasProperties $doc $requiredTop)) { return [pscustomobject]@{ Pass=$false; Errors=@($errors)+@('RequiredTopLevelFieldMissing'); Document=$doc } }
    $requiredManifest = @('ExpectedCount','ExpectedPaths','RecordCount','UniquePathCount','AceCount','ErrorCount','ExpectedPathsSha256','RecordsSha256','Errors')
    if (-not (Test-F2AclHasProperties $doc.Manifest $requiredManifest)) { return [pscustomobject]@{ Pass=$false; Errors=@($errors)+@('RequiredManifestFieldMissing'); Document=$doc } }
    if (-not (Test-F2AclHasProperties $doc.Metadata @('Gates','Disk','PostCollection'))) { return [pscustomobject]@{ Pass=$false; Errors=@($errors)+@('RequiredMetadataFieldMissing'); Document=$doc } }
    $requiredDiskFields = @('SerialMatched','Serial','Model','DriveLetter','FileSystem','BusType','Health','PhysicalHealth','VolumeHealth','DiskNumber','Win32Index','PartitionDisk','Win32MatchCount','DiskMatchCount','PhysicalMatchCount','Win32Serial','DiskSerial','PhysicalSerial','Win32Model','DiskFriendlyName','DiskModel','DiskHealth','DiskOperationalStatus','GPartitionCount','PartitionDiskNumber')
    if (-not (Test-F2AclHasProperties $doc.Metadata.Disk $requiredDiskFields)) { return [pscustomobject]@{ Pass=$false; Errors=@($errors)+@('StorageIdentityFieldsMissing'); Document=$doc } }
    if ($doc.Schema -ne $script:F2AclSchema) { $errors.Add('SchemaMismatch') }
    if ($doc.VmId -ne $ExpectedVmId.ToLowerInvariant() -or $doc.VmName -ne $ExpectedVmName -or $doc.VmState -ne 'Off') { $errors.Add('VmIdentityOrStateMismatch') }
    if ($doc.Complete -ne $true) { $errors.Add('DocumentIncomplete') }
    if (@($doc.Manifest.Errors).Count -ne 0 -or $doc.Manifest.ErrorCount -ne 0) { $errors.Add('CollectionErrorsPresent') }
    if ($null -eq $doc.Metadata -or @($doc.Metadata.Gates).Count -eq 0) { $errors.Add('PreflightGatesMissing') }
    else {
        $gateNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($gate in @($doc.Metadata.Gates)) {
            if (-not (Test-F2AclHasProperties $gate @('Name','Pass','Detail'))) { $errors.Add('PreflightGateRecordIncomplete') }
            else {
                if (-not $gateNames.Add([string]$gate.Name)) { $errors.Add('DuplicateGateName: ' + [string]$gate.Name) }
                if ($gate.Pass -ne $true) { $errors.Add('PreflightGateFailed: ' + [string]$gate.Name) }
            }
        }
        $requiredGates = @('VmImmutableIdentityAndOff','KingstonSerialUniqueAcrossInterfaces','KingstonModelFieldsMatch','KingstonUSBTransport','KingstonDiskHealthAndOnline','GVolumeMapsToSerialSelectedDevice','ConfiguredStoragePathsExact','ZeroVirtualNetworkAdapters','ExactlyElevenUniqueKnownPaths','AllExpectedPathsExistWithoutReparsePoints','PostCollectionVmIdentityAndOff','PostCollectionStoragePathsUnchanged','PostCollectionZeroVirtualNetworkAdapters','PostCollectionKingstonStorageIdentityUnchanged','PostCollectionNoReparsePoints')
        foreach ($requiredGate in $requiredGates) { if (-not $gateNames.Contains($requiredGate)) { $errors.Add('RequiredGateMissing: ' + $requiredGate) } }
    }
    $storageValidation = Test-F2AclKingstonStorageIdentity -Observation $doc.Metadata.Disk
    if (-not $storageValidation.Pass -or $doc.Metadata.Disk.SerialMatched -ne $true -or $doc.Metadata.Disk.Serial -ne $ExpectedDiskSerial -or $doc.Metadata.Disk.Model -ne $ExpectedDiskModel -or $doc.Metadata.Disk.DriveLetter -ne 'G:' -or $doc.Metadata.Disk.FileSystem -ne 'NTFS' -or $doc.Metadata.Disk.BusType -ne 'USB' -or $doc.Metadata.Disk.Health -ne 'Healthy' -or $doc.Metadata.Disk.PhysicalHealth -ne 'Healthy' -or $doc.Metadata.Disk.VolumeHealth -ne 'Healthy') { $errors.Add('StorageIdentityIncomplete') }

    $post = $doc.Metadata.PostCollection
    $requiredPostFields = @('VmId','VmName','VmState','Paths','Storage','StorageValidation')
    if (-not (Test-F2AclHasProperties $post $requiredPostFields)) { $errors.Add('PostCollectionEvidenceMissing') }
    else {
        if ([string]$post.VmId -cne $ExpectedVmId.ToLowerInvariant() -or [string]$post.VmName -cne $ExpectedVmName -or [string]$post.VmState -cne 'Off' -or [string]$doc.VmState -cne [string]$post.VmState) { $errors.Add('PostCollectionVmIdentityOrStateMismatch') }
        $requiredPathFields = @('VmId','VmName','VmState','Configuration','Checkpoints','SmartPaging','VhdPaths','NicCount')
        if (-not (Test-F2AclHasProperties $post.Paths $requiredPathFields)) { $errors.Add('PostCollectionPathsMissing') }
        else {
            $postPaths = $post.Paths
            $expectedCanonical = @($ExpectedPaths | ForEach-Object { ConvertTo-F2AclCanonicalPath $_ })
            $snapshot = Test-F2AclVmStorageSnapshot -VmId ([string]$postPaths.VmId) -VmName ([string]$postPaths.VmName) -VmState ([string]$postPaths.VmState) -ExpectedVmId $ExpectedVmId -ExpectedVmName $ExpectedVmName -ExpectedConfiguration $expectedCanonical[1] -ExpectedCheckpoints $expectedCanonical[0] -ExpectedSmartPaging $expectedCanonical[0] -ExpectedVhdPaths @($expectedCanonical[7],$expectedCanonical[8]) -Configuration ([string]$postPaths.Configuration) -Checkpoints ([string]$postPaths.Checkpoints) -SmartPaging ([string]$postPaths.SmartPaging) -VhdPaths @($postPaths.VhdPaths) -NicCount $postPaths.NicCount
            if (-not $snapshot.Pass) { $errors.Add('PostCollectionStorageSnapshotMismatch') }
            if ([string]$postPaths.VmId -cne [string]$post.VmId -or [string]$postPaths.VmName -cne [string]$post.VmName -or [string]$postPaths.VmState -cne [string]$post.VmState) { $errors.Add('PostCollectionSnapshotIdentityMismatch') }
        }
        $postStorageValidation = Test-F2AclKingstonStorageIdentity -Observation $post.Storage
        if (-not $postStorageValidation.Pass -or -not (Test-F2AclStorageObservationsEquivalent -Initial $doc.Metadata.Disk -Final $post.Storage)) { $errors.Add('PostCollectionStorageIdentityMismatch') }
        if (-not (Test-F2AclHasProperties $post.StorageValidation @('Pass','SerialPass','ModelPass','TransportPass','HealthPass','MappingPass')) -or $post.StorageValidation.Pass -ne $true -or $post.StorageValidation.SerialPass -ne $postStorageValidation.SerialPass -or $post.StorageValidation.ModelPass -ne $postStorageValidation.ModelPass -or $post.StorageValidation.TransportPass -ne $postStorageValidation.TransportPass -or $post.StorageValidation.HealthPass -ne $postStorageValidation.HealthPass -or $post.StorageValidation.MappingPass -ne $postStorageValidation.MappingPass) { $errors.Add('PostCollectionStorageValidationMismatch') }
    }

    $expected = @($ExpectedPaths | ForEach-Object { ConvertTo-F2AclCanonicalPath $_ })
    $actualRows = @($doc.Records)
    $actual = @($actualRows | ForEach-Object { ConvertTo-F2AclCanonicalPath ([string]$_.Path) })
    $expectedSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $actualSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $expected) { [void]$expectedSet.Add($path) }
    foreach ($path in $actual) { [void]$actualSet.Add($path) }
    if ($expected.Count -ne 11 -or $expectedSet.Count -ne 11) { $errors.Add('ExpectedPathSetInvalid') }
    $manifestPaths = @($doc.Manifest.ExpectedPaths | ForEach-Object { ConvertTo-F2AclCanonicalPath ([string]$_) })
    $manifestSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $manifestPaths) { [void]$manifestSet.Add($path) }
    if ($manifestPaths.Count -ne 11 -or $manifestSet.Count -ne 11 -or $manifestSet.Count -ne $expectedSet.Count) { $errors.Add('ManifestPathSetInvalid') }
    foreach ($path in $expectedSet) { if (-not $manifestSet.Contains($path)) { $errors.Add('ManifestPathMissing: ' + $path) } }
    if ($actualRows.Count -ne 11 -or $actualSet.Count -ne 11) { $errors.Add('RecordCountOrDuplicatePath') }
    if ($expectedSet.Count -ne $actualSet.Count) { $errors.Add('PathSetCountMismatch') }
    foreach ($path in $expectedSet) { if (-not $actualSet.Contains($path)) { $errors.Add('MissingPath: ' + $path) } }
    foreach ($path in $actualSet) { if (-not $expectedSet.Contains($path)) { $errors.Add('UnexpectedPath: ' + $path) } }
    if ($doc.Manifest.ExpectedCount -ne 11 -or $doc.Manifest.RecordCount -ne 11 -or $doc.Manifest.UniquePathCount -ne 11) { $errors.Add('ManifestCountMismatch') }

    $aceCount = 0
    foreach ($row in $actualRows) {
        if (-not (Test-F2AclHasProperties $row @('Path','Owner','OwnerSid','Sddl','DaclProtected','Status','Error','AceCount','Aces','RecordSha256'))) {
            $errors.Add('RequiredRecordFieldMissing')
            continue
        }
        if ($row.Status -ne 'PASS' -or [string]::IsNullOrWhiteSpace([string]$row.Owner) -or [string]::IsNullOrWhiteSpace([string]$row.OwnerSid) -or [string]::IsNullOrWhiteSpace([string]$row.Sddl) -or $null -eq $row.DaclProtected -or $row.Error) {
            $errors.Add('RecordIncomplete: ' + [string]$row.Path)
        }
        $aces = @($row.Aces)
        if ([int]$row.AceCount -ne $aces.Count) { $errors.Add('AceCountMismatch: ' + [string]$row.Path) }
        $aceCount += $aces.Count
        foreach ($ace in $aces) {
            if (-not (Test-F2AclHasProperties $ace @('Principal','Sid','Type','Rights','AccessMask','InheritanceFlags','PropagationFlags','Inherited'))) {
                $errors.Add('RequiredAceFieldMissing: ' + [string]$row.Path)
                continue
            }
            if ([string]::IsNullOrWhiteSpace([string]$ace.Sid) -or [string]::IsNullOrWhiteSpace([string]$ace.Type) -or [string]::IsNullOrWhiteSpace([string]$ace.Rights) -or $null -eq $ace.AccessMask -or $null -eq $ace.InheritanceFlags -or $null -eq $ace.PropagationFlags -or $null -eq $ace.Inherited) {
                $errors.Add('AceIncomplete: ' + [string]$row.Path)
            }
        }
        try {
            $content = [ordered]@{
                Path = [string]$row.Path; Owner = [string]$row.Owner; OwnerSid = [string]$row.OwnerSid; Sddl = [string]$row.Sddl
                DaclProtected = [bool]$row.DaclProtected; Status = [string]$row.Status; Error = [string]$row.Error
                AceCount = [int]$row.AceCount; Aces = @($row.Aces)
            }
            $recordHash = Get-F2AclSha256 (Get-F2AclJsonBytes $content)
            if ($recordHash -cne [string]$row.RecordSha256) { $errors.Add('RecordSha256Mismatch: ' + [string]$row.Path) }
        }
        catch { $errors.Add('RecordHashError: ' + [string]$row.Path) }
    }
    if ($doc.Manifest.AceCount -ne $aceCount) { $errors.Add('ManifestAceCountMismatch') }
    if (@($doc.Manifest.ExpectedPathsSha256).Count -ne 1 -or @($doc.Manifest.RecordsSha256).Count -ne 1) { $errors.Add('ManifestDigestMissing') }
    else {
        $pathManifest = @($expected | Sort-Object { $_.ToLowerInvariant() }) -join "`n"
        $recordsManifest = @($actualRows | Sort-Object { ([string]$_.Path).ToLowerInvariant() } | ForEach-Object { [string]$_.RecordSha256 }) -join "`n"
        if ((Get-F2AclSha256 (ConvertTo-F2AclUtf8Bytes $pathManifest)) -cne [string]$doc.Manifest.ExpectedPathsSha256) { $errors.Add('ExpectedPathsSha256Mismatch') }
        if ((Get-F2AclSha256 (ConvertTo-F2AclUtf8Bytes $recordsManifest)) -cne [string]$doc.Manifest.RecordsSha256) { $errors.Add('RecordsSha256Mismatch') }
    }
    return [pscustomobject]@{ Pass = ($errors.Count -eq 0); Errors = @($errors); Document = $doc }
}

Export-ModuleMember -Function Get-F2AclSha256, ConvertTo-F2AclUtf8Bytes, ConvertTo-F2AclWindowsArgument, ConvertTo-F2AclCanonicalPath, Assert-F2AclSupportedAce, Test-F2AclKingstonStorageIdentity, Test-F2AclZeroNicCount, Test-F2AclStorageObservationsEquivalent, Test-F2AclVmStorageSnapshot, Test-F2AclElevatedIdentityPair, Test-F2AclCoordinatorStatus, Write-F2AclAtomicCreateNewFile, Read-F2AclBoundedFile, Get-F2AclCoordinatorMailboxPath, Get-F2AclCoordinatorMailboxSddl, Test-F2AclCoordinatorMailboxSddl, Test-F2AclCoordinatorMailboxDirectory, Test-F2AclCoordinatorMailboxParentSddl, Test-F2AclCoordinatorMailboxParentChain, New-F2AclCoordinatorMailboxDirectory, New-F2AclEvidenceDocument, Write-F2AclFrame, Read-F2AclFrame, Wait-F2AclProcessExit, New-F2AclWorkerBootstrapCommand, Invoke-F2AclCapturedPowerShell, ConvertTo-F2AclSanitizedWorkerError, ConvertTo-F2AclWorkerDiagnosticDocument, New-F2AclWorkerExecutionReport, New-F2AclRestrictedDirectory, Test-F2AclRestrictedDirectory, Test-F2AclNoReparseAncestors, Test-F2AclEvidenceVolumeSeparateFromG, Get-F2AclUnexpectedWritableSids, Add-F2AclBoundedStreamRecord, Test-F2AclEvidenceDocument
