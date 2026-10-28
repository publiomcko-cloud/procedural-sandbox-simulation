$ErrorActionPreference='Stop'
$evidenceRoot='C:\w82\docs\reports\P3-1-R8.2\evidence\diag-run-009'
$godotPath='C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
$arguments=@('--headless','--path','C:\w82\game','--script','res://tests/prototypes/p3_1_r8_2_xplus_face_oracle.gd')
$psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$godotPath;$psi.WorkingDirectory='C:\w82';$psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
$psi.Arguments=($arguments | ForEach-Object { '"'+($_ -replace '"','\"')+'"' }) -join ' '
$psi.EnvironmentVariables['P31_R82_EVIDENCE_DIR']=$evidenceRoot;$psi.EnvironmentVariables['APPDATA']="$evidenceRoot\godot-profile\Roaming";$psi.EnvironmentVariables['LOCALAPPDATA']="$evidenceRoot\godot-profile\Local";$psi.EnvironmentVariables['TEMP']="$evidenceRoot\godot-profile\Temp";$psi.EnvironmentVariables['TMP']="$evidenceRoot\godot-profile\Temp"
$startedAt=[DateTimeOffset]::UtcNow;$watch=[Diagnostics.Stopwatch]::StartNew();$proc=[Diagnostics.Process]::Start($psi)
[ordered]@{pid=$proc.Id;start_utc=$startedAt.ToString('o');exe=$godotPath;exe_sha256=(Get-FileHash $godotPath -Algorithm SHA256).Hash;script_sha256=(Get-FileHash 'C:\w82\game\tests\prototypes\p3_1_r8_2_xplus_face_oracle.gd' -Algorithm SHA256).Hash;args=$arguments;stdout="$evidenceRoot\stdout.log";stderr="$evidenceRoot\stderr.log"}|ConvertTo-Json -Depth 5|Set-Content "$evidenceRoot\process-start.json" -Encoding utf8
$outTask=$proc.StandardOutput.ReadToEndAsync();$errTask=$proc.StandardError.ReadToEndAsync();$proc.WaitForExit();$watch.Stop();$finishUtc=[DateTimeOffset]::UtcNow;$stdout=$outTask.Result;$stderr=$errTask.Result
[IO.File]::WriteAllText("$evidenceRoot\stdout.log",$stdout,[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllText("$evidenceRoot\stderr.log",$stderr,[Text.UTF8Encoding]::new($false))
[ordered]@{pid=$proc.Id;finish_utc=$finishUtc.ToString('o');elapsed_ms=$watch.Elapsed.TotalMilliseconds;exit_code=$proc.ExitCode;completed=$true;stdout_sha256=(Get-FileHash "$evidenceRoot\stdout.log" -Algorithm SHA256).Hash;stderr_sha256=(Get-FileHash "$evidenceRoot\stderr.log" -Algorithm SHA256).Hash}|ConvertTo-Json|Set-Content "$evidenceRoot\process-exit.json" -Encoding utf8
