# P3.1 R3C — Final campaign addendum R4

**Frozen before the next final-campaign process.** This version supersedes the R3 final-campaign runner source pin only. It does not alter workload bytes, expected results, the adaptive workload, or any numeric gate in the original preregistration/R2 addendum.

## Source and preserved failed campaign

The R3C executable workload, cache, and digest sources remain pinned to `8f7d59d5aab724438f065a3ba6d38986a16b3183`. The campaign dispatcher and process capture source are pinned to `c1470651ea1a2200e85cecfd1aa3d083254d56c8`. The exact full campaign HEAD is the commit containing this R4 addendum and must be present in each run record.

The prior attempt under source `09efc0b5a1f10b7f84477208aae34c9304659e9e` is preserved at `C:\Users\PUBLI\AppData\Local\Temp\p31-r3c-final-09efc0b5a1f1`. Sixteen processes completed their scenario result with `SCENARIO_RUN_SOURCE_AND_ZERO_FAILURES_VERIFIED`, but the runner reported `exit_code = null` and classified them `FAIL_RETAINED`; they are not accepted performance samples because process exit was unverified. The next run, `P31.R3B.CONCENTRATED-8192.R02`, was interrupted after launch and is also excluded. `campaign-abort.json` and `campaign-abort-correction.json` are both retained; the correction records that the interrupted run was R02, not R01, and includes the hash of the original incident file.

The cause was `Start-Process -PassThru` under Windows PowerShell 5.1: for the asynchronous launch shape used here, the returned process object yielded a null `ExitCode` even after its launcher had exited. A controlled synthetic child proved that `System.Diagnostics.ProcessStartInfo` plus concurrent asynchronous stdout/stderr reads, `WaitForExit`, and `ExitCode` capture records exit 17 and both output markers. The same capture path successfully ran the pinned Godot console binary with `--version`, recording exit 0 and the exact pinned version.

## Frozen corrected process contract

The runner now launches with `System.Diagnostics.Process`, quotes the fixed argument vector, starts asynchronous reads for both streams before polling, observes the exact Godot child image by CIM, preserves the 900-second timeout and terminates only the verified engine/launcher pair on timeout. It waits for the launcher and both stream-drain tasks, writes the complete streams to unique evidence files, and records the actual integer exit code when available. A missing exit code, process attribution, source identity, or terminal JSONL result still blocks that run and is retained. No timing sample is rescued from the preceding failed campaign.

The corrected final campaign reruns the frozen eight R3B and eight R3C workloads, five independent processes per workload, sequentially under the exact full Git HEAD. All original R3B gates and R3C gates are unchanged. Preserve all failed process and scenario records; do not replace or delete the earlier attempts. No runner or source edits, fixture changes, or threshold changes are permitted after this addendum is committed. A later correction requires a new source identity and new preregistration before final measurements.
