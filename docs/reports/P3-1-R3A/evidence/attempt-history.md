# R3A execution attempt ledger

All attempts below are retained under this evidence directory or the original external TEMP root. Only the final full campaign is used for comparative results.

| Attempt | Stage | Outcome | Classification |
|---|---|---|---|
| campaign-01 | First full matrix | Exit 0 and wrote 9 rows, but the cave control passed an invalid empty mesh snapshot and emitted many Godot `SCRIPT ERROR` messages (stderr 939,330 bytes). | **Invalid evidence.** The scenario marker was misleading; excluded from results. Raw logs and JSONL/CSV/summary are retained in `attempt-01-invalid/`. |
| campaign-02 | Launcher/capture retry | stdout/stderr redirected pipes were not drained while waiting, so the wrapper hung; exact Godot process PID 46700 was terminated and wrapper recorded exit `-1`. No trustworthy scenario terminal result. | **Invalid pre-scenario orchestration.** Retained in `attempt-02-capture/`; no result used. |
| campaign-03 | Pre-scenario launch | Required output-root environment variable was absent; process exited 2 before scenario dispatch. | **Invalid pre-scenario setup.** Retained in `attempt-03-launch/`; no result used. |
| campaign-04 | Corrected full matrix before incremental-delta extension | 9 rows passed; later superseded because the prototype source gained ordered incremental snapshot update and reload tests. | **Valid historical experiment, not final source.** Raw files retained in `campaign-04/`; not used as the final comparison table. |
| cave-smoke-02 | Focused canonical cave control | Exit 0; 1 scenario; nine canonical centerline samples open and snapshot lattice had 0/9; snapshot rejected as approximate. | Focused confirmation only; `campaign-06` supersedes as final-source evidence. |
| incremental-smoke | Focused incremental snapshot update | Exit 0; invalid sequence delta rejected atomically; valid appended operation matched complete lattice rebuild and reload at all grid nodes. | Focused final-source check; selected 256-op layout only. |
| campaign-06 | Final full matrix | Exit 0; 9 rows; 23 reference hash checks; 0 harness failures; stderr empty; 284,152 ms internal duration. | **Final comparative evidence.** Full raw result and process samples retained in `campaign-06/`. |

The final campaign used a file-redirection process wrapper that completes both stdout/stderr capture before reading the exit code. PID evidence in `campaign-06/process.json` records launcher PID 55096, console host PID 49528, engine PID 44588 (parent 55096). No automatic rerun occurred after a scenario started; recoverable attempts were corrected before the final full matrix.
