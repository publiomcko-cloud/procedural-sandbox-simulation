$ErrorActionPreference='Stop'
$ev='C:\w82\docs\reports\P3-1-R8.2\evidence\final-validation'
$godot='C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
$pwsh='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$args=@('-NoProfile','-ExecutionPolicy','Bypass','-File','C:\w82\scripts\validate.ps1')
$psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$pwsh;$psi.WorkingDirectory='C:\w82';$psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
$psi.Arguments=($args|%{'"'+($_ -replace '"','\"')+'"'}) -join ' '
$psi.EnvironmentVariables['GODOT_BIN']=$godot;$psi.EnvironmentVariables['APPDATA']="$ev\godot-profile\Roaming";$psi.EnvironmentVariables['LOCALAPPDATA']="$ev\godot-profile\Local";$psi.EnvironmentVariables['TEMP']="$ev\godot-profile\Temp";$psi.EnvironmentVariables['TMP']="$ev\godot-profile\Temp"
$hashes=[ordered]@{source_head=(git -C C:\w82 rev-parse HEAD).Trim();validate_sha256=(Get-FileHash 'C:\w82\scripts\validate.ps1' -Algorithm SHA256).Hash;godot_sha256=(Get-FileHash $godot -Algorithm SHA256).Hash;godot_version=(& $godot --version 2>&1|Out-String).Trim()}
$started=[DateTimeOffset]::UtcNow;$watch=[Diagnostics.Stopwatch]::StartNew();$process=[Diagnostics.Process]::Start($psi)
[ordered]@{identity=$hashes;pid=$process.Id;start_utc=$started.ToString('o');exe=$pwsh;arguments=$args;stdout="$ev\stdout.log";stderr="$ev\stderr.log";profile="$ev\godot-profile"}|ConvertTo-Json -Depth 5|Set-Content "$ev\process-start.json" -Encoding utf8
$outTask=$process.StandardOutput.ReadToEndAsync();$errTask=$process.StandardError.ReadToEndAsync();$process.WaitForExit();$watch.Stop();$finish=[DateTimeOffset]::UtcNow;$stdout=$outTask.Result;$stderr=$errTask.Result
[IO.File]::WriteAllText("$ev\stdout.log",$stdout,[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllText("$ev\stderr.log",$stderr,[Text.UTF8Encoding]::new($false))
[ordered]@{pid=$process.Id;finish_utc=$finish.ToString('o');elapsed_ms=$watch.Elapsed.TotalMilliseconds;exit_code=$process.ExitCode;completed=$true;stdout_sha256=(Get-FileHash "$ev\stdout.log" -Algorithm SHA256).Hash;stderr_sha256=(Get-FileHash "$ev\stderr.log" -Algorithm SHA256).Hash}|ConvertTo-Json|Set-Content "$ev\process-exit.json" -Encoding utf8
